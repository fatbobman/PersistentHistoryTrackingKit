@preconcurrency import CoreData
import Foundation
import PersistentHistoryTrackingKit
import Testing

@Suite("Persistent History Tracking Kit Integration Tests", .serialized)
@MainActor
struct PersistentHistoryTrackingKitTests {
    let storeURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        .first?
        .appendingPathComponent("PersistentHistoryKitTestDB.sqlite") ?? URL(fileURLWithPath: "")
    let uniqueString = "PersistentHistoryTrackingKit.lastToken.tests."
    let userDefaults = UserDefaults.standard

    init() {
        // 清除 UserDefaults 环境
        for author in AppActor.allCases {
            userDefaults.removeObject(forKey: uniqueString + author.rawValue)
        }
    }

    func cleanupStoreFiles() async {
        await sleep(seconds: 3)
        try? FileManager.default.removeItem(at: storeURL)
        try? FileManager.default
            .removeItem(at: storeURL.deletingPathExtension().appendingPathExtension("sqlite-wal"))
        try? FileManager.default
            .removeItem(at: storeURL.deletingPathExtension().appendingPathExtension("sqlite-shm"))
    }

    @Test("Kit should work correctly in App Group scenario")
    func persistentHistoryKitInAppGroup() async throws {
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
            autoStart: false)

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

        viewContext1.performAndWait {
            let registeredObject = viewContext1.registeredObject(for: objectID)
            #expect(registeredObject != nil)
        }
        let lastTimestamp = userDefaults
            .value(forKey: uniqueString + AppActor.app1.rawValue) as? Date
        #expect(lastTimestamp != nil)

        kit.stop()
        await sleep(seconds: 2)
    }

    @Test("Kit should work correctly with batch insert")
    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
    func kitInBatchInsert() async throws {
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
            logLevel: 3)
        try batchContext.performAndWait {
            var count = 0

            let batchInsert = NSBatchInsertRequest(entity: Event
                .entity())
            { (dictionary: NSMutableDictionary) in
                dictionary["timestamp"] = Date()
                count += 1
                return count == 10
            }
            try batchContext.execute(batchInsert)
        }

        // when
        let objectID: NSManagedObjectID = batchContext.performAndWait {
            let request = NSFetchRequest<Event>(entityName: "Event")
            request.sortDescriptors = [NSSortDescriptor(
                keyPath: \Event.timestamp,
                ascending: false)]
            guard let results = try? batchContext.fetch(request),
                  let object = results.first
            else {
                Issue.record("Failed to fetch event")
                fatalError()
            }
            return object.objectID
        }
        await sleep(seconds: 2)

        // then
        let result1 = viewContext.performAndWait {
            viewContext.registeredObject(for: objectID) != nil
        }
        #expect(result1)
        let result2 = anotherContext.performAndWait {
            anotherContext.registeredObject(for: objectID) != nil
        }
        #expect(result2)
        kit.stop()
        await sleep(seconds: 2)
    }

    @Test("Manual cleaner should work correctly")
    func manualCleaner() async throws {
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
            autoStart: false)

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

        let result3 = viewContext1.performAndWait {
            viewContext1.registeredObject(for: objectID) != nil
        }
        #expect(result3)
        let lastTimestamp = userDefaults
            .value(forKey: uniqueString + AppActor.app1.rawValue) as? Date
        #expect(lastTimestamp != nil)

        kit.stop()
        await sleep(seconds: 2)
    }

    @Test("Two apps with Kit should clean transactions correctly")
    func twoAppWithKit() async throws {
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
            logLevel: 2)

        let app2kit = PersistentHistoryTrackingKit(
            container: container1,
            contexts: [viewContext2],
            currentAuthor: AppActor.app2.rawValue,
            allAuthors: authors,
            userDefaults: userDefaults,
            uniqueString: uniqueString,
            logLevel: 2)

        let backgroundContext = container1.newBackgroundContext()
        backgroundContext.transactionAuthor = AppActor.app3.rawValue

        // when
        let objectID: NSManagedObjectID = backgroundContext.performAndWait {
            let event = Event(context: backgroundContext)
            event.timestamp = Date()
            backgroundContext.saveIfChanged()
            return event.objectID
        }

        await sleep(seconds: 3)

        // then
        let result4 = viewContext1.performAndWait {
            // 先尝试获取对象，如果不存在则尝试刷新
            if let _ = try? viewContext1.existingObject(with: objectID) {
                return true
            }
            // 如果对象不存在，可能需要刷新context
            viewContext1.refreshAllObjects()
            return (try? viewContext1.existingObject(with: objectID)) != nil
        }
        #expect(result4)

        let result5 = viewContext2.performAndWait {
            // 先尝试获取对象，如果不存在则尝试刷新
            if let _ = try? viewContext2.existingObject(with: objectID) {
                return true
            }
            // 如果对象不存在，可能需要刷新context
            viewContext2.refreshAllObjects()
            return (try? viewContext2.existingObject(with: objectID)) != nil
        }
        #expect(result5)

        app1kit.stop()
        app2kit.stop()
    }
}
