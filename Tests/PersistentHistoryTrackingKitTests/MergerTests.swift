//
//  MergerTests.swift
//
//
//  Created by Yang Xu on 2022/2/12
//  Copyright © 2022 Yang Xu. All rights reserved.
//
//  Follow me on Twitter: @fatbobman
//  My Blog: https://www.fatbobman.com
//  微信公共号: 肘子的Swift记事本
//

@preconcurrency import CoreData
@testable import PersistentHistoryTrackingKit
import Testing

@Suite("Merger Tests", .serialized)
struct MergerTests {
    let storeURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        .first?
        .appendingPathComponent("PersistentHistoryTrackKitMergeTest.sqlite") ??
        URL(fileURLWithPath: "")

    init() {
        // Setup code if needed
    }

    func cleanupStoreFiles() async {
        await sleep(seconds: 2)
        try? FileManager.default.removeItem(at: storeURL)
        try? FileManager.default
            .removeItem(at: storeURL.deletingPathExtension().appendingPathExtension("sqlite-wal"))
        try? FileManager.default
            .removeItem(at: storeURL.deletingPathExtension().appendingPathExtension("sqlite-shm"))
    }

    @Test
    func mergerInAppGroup() throws {
        // given
        let container1 = CoreDataHelper.createNSPersistentContainer(storeURL: storeURL)
        let container2 = CoreDataHelper.createNSPersistentContainer(storeURL: storeURL)
        let app1backgroundContext = container1.newBackgroundContext()
        let fetcher = Fetcher(
            backgroundContext: app1backgroundContext,
            currentAuthor: AppActor.app1.rawValue,
            allAuthors: [AppActor.app1.rawValue, AppActor.app2.rawValue])
        let merger = Merger()

        let app1viewContext = container1.viewContext
        app1viewContext.transactionAuthor = AppActor.app1.rawValue

        let app2viewContext = container2.viewContext
        app2viewContext.transactionAuthor = AppActor.app2.rawValue

        app2viewContext.performAndWait {
            let event = Event(context: app2viewContext)
            event.timestamp = Date()
            app2viewContext.saveIfChanged()
        }
        let transactions = try fetcher.fetchTransactions(from: Date().addingTimeInterval(-2))

        let userInfo = transactions.first?.objectIDNotification().userInfo ?? [:]
        guard let objectIDs = userInfo["inserted_objectIDs"] as? NSSet,
              let objectID = objectIDs.allObjects.first as? NSManagedObjectID
        else {
            Issue.record("Failed to get object ID from transaction")
            return
        }
        app1viewContext.retainsRegisteredObjects = true // 为检查保持托管对象不清除
        app1backgroundContext.retainsRegisteredObjects = true

        // when
        merger(merge: transactions, into: [app1viewContext, app1backgroundContext])

        // then
        app1viewContext.performAndWait {
            #expect(app1viewContext.registeredObject(for: objectID) != nil)
        }
        app1backgroundContext.performAndWait {
            #expect(app1backgroundContext.registeredObject(for: objectID) != nil)
        }
    }

    @Test
    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
    func mergerInBatchOperation() async throws {
        // given
        let container = CoreDataHelper.createNSPersistentContainer(storeURL: storeURL)
        let viewContext = container.viewContext
        let batchContext = container.newBackgroundContext()
        let backgroundContext = container.newBackgroundContext()

        viewContext.transactionAuthor = AppActor.app1.rawValue
        batchContext.transactionAuthor = AppActor.app2.rawValue // 批量添加使用单独的author

        let fetcher = Fetcher(
            backgroundContext: backgroundContext,
            currentAuthor: AppActor.app1.rawValue,
            allAuthors: [AppActor.app1.rawValue, AppActor.app2.rawValue])

        let merger = Merger()
        // insert by batch
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

        let transactions = try fetcher.fetchTransactions(from: Date().addingTimeInterval(-2))

        let userInfo = transactions.first?.objectIDNotification().userInfo ?? [:]
        guard let objectIDs = userInfo["inserted_objectIDs"] as? NSSet,
              let objectID = objectIDs.allObjects.first as? NSManagedObjectID
        else {
            Issue.record("Failed to get object ID from transaction")
            return
        }
        viewContext.retainsRegisteredObjects = true
        viewContext.performAndWait {
            #expect(viewContext.registeredObject(for: objectID) == nil)
        }
        // when
        merger(merge: transactions, into: [viewContext])

        // then
        viewContext.performAndWait {
            #expect(viewContext.registeredObject(for: objectID) != nil)
        }
    }
}
