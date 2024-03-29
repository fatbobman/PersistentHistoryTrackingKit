import CoreData
import PersistentHistoryTrackingKit
import XCTest

@MainActor
final class PersistentHistoryTrackingKitTests: XCTestCase {
    let storeURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        .first?
        .appendingPathComponent("PersistentHistoryKitTestDB.sqlite") ?? URL(fileURLWithPath: "")
    let uniqueString = "PersistentHistoryTrackingKit.lastToken.tests."
    let userDefaults = UserDefaults.standard

    override func setUpWithError() throws {
        // 清除 UserDefaults 环境
        for author in AppActor.allCases {
            userDefaults.removeObject(forKey: uniqueString + author.rawValue)
        }
    }

    override func tearDown() async throws {
        await sleep(seconds: 3)
        try? FileManager.default.removeItem(at: storeURL)
        try? FileManager.default.removeItem(at: storeURL.deletingPathExtension().appendingPathExtension("sqlite-wal"))
        try? FileManager.default.removeItem(at: storeURL.deletingPathExtension().appendingPathExtension("sqlite-shm"))
    }

    func testPersistentHistoryKitInAppGroup() async throws {
        // given
        let container1 = CoreDataHelper.createNSPersistentContainer(storeURL: storeURL)
        let container2 = CoreDataHelper.createNSPersistentContainer(storeURL: storeURL)
        container1.viewContext.transactionAuthor = AppActor.app1.rawValue
        container2.viewContext.transactionAuthor = AppActor.app2.rawValue
        let authors = [AppActor.app1.rawValue, AppActor.app2.rawValue]
        let kit = PersistentHistoryTrackingKit(
            container: container1,
            currentAuthor: AppActor.app1.rawValue,
            allAuthors: authors,
            userDefaults: userDefaults,
            cleanStrategy: .byNotification(times: 1),
            uniqueString: uniqueString,
            logLevel: 3,
            autoStart: false
        )

        kit.start()

        let viewContext1 = container1.viewContext
        let viewContext2 = container2.viewContext
        viewContext1.retainsRegisteredObjects = true
        // when

        let objectID: NSManagedObjectID = viewContext2.performAndWait {
            let event = Event(context: viewContext2)
            event.timestamp = Date()
            viewContext2.saveIfChanged()
            return event.objectID
        }

        // then
        await sleep(seconds: 2)

        await viewContext1.perform {
            XCTAssertNotNil(viewContext1.registeredObject(for: objectID))
        }
        let lastTimestamp = userDefaults.value(forKey: uniqueString + AppActor.app1.rawValue) as? Date
        XCTAssertNotNil(lastTimestamp)

        kit.stop()
        await sleep(seconds: 2)
    }

    // swiftlint:disable:next function_body_length
    func testKitInBatchInsert() async throws {
        guard #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) else {
            return
        }
        // given
        let container1 = CoreDataHelper.createNSPersistentContainer(storeURL: storeURL)
        let viewContext = container1.viewContext
        viewContext.transactionAuthor = AppActor.app1.rawValue
        viewContext.retainsRegisteredObjects = true
        let batchContext = container1.newBackgroundContext()
        batchContext.transactionAuthor = AppActor.app2.rawValue
        let authors = [AppActor.app1.rawValue, AppActor.app2.rawValue]
        let anotherContext = container1.newBackgroundContext()
        anotherContext.retainsRegisteredObjects = true
        let kit = PersistentHistoryTrackingKit(
            viewContext: container1.viewContext,
            contexts: [viewContext, anotherContext], // test merge to multi context
            currentAuthor: AppActor.app1.rawValue,
            allAuthors: authors,
            batchAuthors: [AppActor.app2.rawValue],
            userDefaults: userDefaults,
            cleanStrategy: .byNotification(times: 1),
            uniqueString: uniqueString,
            logLevel: 3
        )
        try batchContext.performAndWait {
            var count = 0

            let batchInsert = NSBatchInsertRequest(entity: Event.entity()) { (dictionary: NSMutableDictionary) in
                dictionary["timestamp"] = Date()
                count += 1
                return count == 10
            }
            try batchContext.execute(batchInsert)
        }

        // when
        let objectID: NSManagedObjectID = batchContext.performAndWait {
            let request = NSFetchRequest<Event>(entityName: "Event")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Event.timestamp, ascending: false)]
            guard let results = try? batchContext.fetch(request),
                  let object = results.first else { fatalError() }
            return object.objectID
        }
        await sleep(seconds: 2)
        // then
        viewContext.performAndWait {
            XCTAssertNotNil(viewContext.registeredObject(for: objectID))
        }
        anotherContext.performAndWait {
            XCTAssertNotNil(anotherContext.registeredObject(for: objectID))
        }
        kit.stop()
        await sleep(seconds: 2)
    }

    func testManualCleaner() async throws {
        // given
        let container1 = CoreDataHelper.createNSPersistentContainer(storeURL: storeURL)
        let container2 = CoreDataHelper.createNSPersistentContainer(storeURL: storeURL)
        container1.viewContext.transactionAuthor = AppActor.app1.rawValue
        container2.viewContext.transactionAuthor = AppActor.app2.rawValue
        let authors = [AppActor.app1.rawValue, AppActor.app2.rawValue]
        let kit = PersistentHistoryTrackingKit(
            container: container1,
            currentAuthor: AppActor.app1.rawValue,
            allAuthors: authors,
            userDefaults: userDefaults,
            cleanStrategy: .none,
            uniqueString: uniqueString,
            logLevel: 2,
            autoStart: false
        )

        let cleaner = kit.cleanerBuilder()

        kit.start()

        let viewContext1 = container1.viewContext
        let viewContext2 = container2.viewContext
        viewContext1.retainsRegisteredObjects = true

        // when

        let objectID: NSManagedObjectID = viewContext2.performAndWait {
            let event = Event(context: viewContext2)
            event.timestamp = Date()
            viewContext2.saveIfChanged()
            return event.objectID
        }

        // then
        await sleep(seconds: 2)

        cleaner() // 手动清除

        viewContext1.performAndWait {
            XCTAssertNotNil(viewContext1.registeredObject(for: objectID))
        }
        let lastTimestamp = userDefaults.value(forKey: uniqueString + AppActor.app1.rawValue) as? Date
        XCTAssertNotNil(lastTimestamp)

        kit.stop()
        await sleep(seconds: 2)
    }

    /// 测试两个app都执行了Kit后，transaction 是否有被清除
    func testTwoAppWithKit() async throws {
        // given
        let container1 = CoreDataHelper.createNSPersistentContainer(storeURL: storeURL)
        let container2 = CoreDataHelper.createNSPersistentContainer(storeURL: storeURL)
        let viewContext1 = container1.viewContext
        viewContext1.transactionAuthor = AppActor.app1.rawValue
        let viewContext2 = container2.viewContext
        viewContext2.transactionAuthor = AppActor.app2.rawValue
        viewContext1.retainsRegisteredObjects = true
        viewContext2.retainsRegisteredObjects = true
        let authors = [AppActor.app1.rawValue, AppActor.app2.rawValue, AppActor.app3.rawValue]

        let app1kit = PersistentHistoryTrackingKit(
            container: container1,
            contexts: [viewContext1],
            currentAuthor: AppActor.app1.rawValue,
            allAuthors: authors,
            userDefaults: userDefaults,
            uniqueString: uniqueString,
            logLevel: 2
        )

        let app2kit = PersistentHistoryTrackingKit(
            container: container1,
            contexts: [viewContext2],
            currentAuthor: AppActor.app2.rawValue,
            allAuthors: authors,
            userDefaults: userDefaults,
            uniqueString: uniqueString,
            logLevel: 2
        )

        let backgroundContext = container1.newBackgroundContext()
        backgroundContext.transactionAuthor = AppActor.app3.rawValue

        // when
        let objectID: NSManagedObjectID = backgroundContext.performAndWait {
            let event = Event(context: backgroundContext)
            event.timestamp = Date()
            backgroundContext.saveIfChanged()
            return event.objectID
        }

        await sleep(seconds: 2)

        // then
        viewContext1.performAndWait {
            XCTAssertNotNil(viewContext1.registeredObject(for: objectID))
        }

        viewContext2.performAndWait {
            XCTAssertNotNil(viewContext2.registeredObject(for: objectID))
        }

        app1kit.stop()
        app2kit.stop()
    }
}
