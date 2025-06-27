//
//  FetcherTests.swift
//
//
//  Created by Yang Xu on 2022/2/11
//  Copyright © 2022 Yang Xu. All rights reserved.
//
//  Follow me on Twitter: @fatbobman
//  My Blog: https://www.fatbobman.com
//  微信公共号: 肘子的Swift记事本
//

@preconcurrency import CoreData
@testable import PersistentHistoryTrackingKit
import Testing

@Suite("Fetcher Tests", .serialized)
struct FetcherTest {
    let storeURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        .first?
        .appendingPathComponent("PersistentHistoryKitFetcherTest.sqlite") ??
        URL(fileURLWithPath: "")

    init() {
        // Setup code if needed
    }

    func cleanupStoreFiles() {
        try? FileManager.default.removeItem(at: storeURL)
        try? FileManager.default
            .removeItem(at: storeURL.deletingPathExtension().appendingPathExtension("sqlite-wal"))
        try? FileManager.default
            .removeItem(at: storeURL.deletingPathExtension().appendingPathExtension("sqlite-shm"))
    }

    @Test
    func fetcherAuthorsIncludingCloudKit() async throws {
        // given
        let container1 = CoreDataHelper.createNSPersistentContainer(storeURL: storeURL)
        let app1backgroundContext = container1.newBackgroundContext()

        // when
        let fetcher1 = Fetcher(
            backgroundContext: app1backgroundContext,
            currentAuthor: AppActor.app1.rawValue,
            allAuthors: [AppActor.app1.rawValue, AppActor.app2.rawValue])
        let fetcher2 = Fetcher(
            backgroundContext:
            app1backgroundContext, currentAuthor: AppActor.app1.rawValue,
            allAuthors: [AppActor.app1.rawValue, AppActor.app2.rawValue],
            includingCloudKitMirroring: true)

        // then
        #expect(fetcher1.allAuthors.count == 2)
        #expect(fetcher2.allAuthors.count == 3)
        #expect(fetcher2.allAuthors.contains("NSCloudKitMirroringDelegate.import"))
    }

    /// 使用两个协调器，模拟在app group的情况下，从不同的app或app extension中操作数据库。
    @Test
    func fetcherInAppGroup() async throws {
        // given
        cleanupStoreFiles() // 确保开始时数据库是干净的

        let container1 = CoreDataHelper.createNSPersistentContainer(storeURL: storeURL)
        let container2 = CoreDataHelper.createNSPersistentContainer(storeURL: storeURL)
        let app1backgroundContext = container1.newBackgroundContext()
        let fetcher = Fetcher(
            backgroundContext: app1backgroundContext,
            currentAuthor: AppActor.app1.rawValue,
            allAuthors: [AppActor.app1.rawValue, AppActor.app2.rawValue])

        let app1viewContext = container1.viewContext
        app1viewContext.transactionAuthor = AppActor.app1.rawValue

        let app2viewContext = container2.viewContext
        app2viewContext.transactionAuthor = AppActor.app2.rawValue

        let startTime = Date()

        // when
        app1viewContext.performAndWait {
            let event = Event(context: app1viewContext)
            event.timestamp = Date()
            app1viewContext.saveIfChanged()
        }

        app2viewContext.performAndWait {
            let event = Event(context: app2viewContext)
            event.timestamp = Date()
            app2viewContext.saveIfChanged()
        }

        // then
        // Fetcher 只获取不是当前作者创建的事务，所以应该只有 app2 的 1 个事务
        let transactions = try fetcher.fetchTransactions(from: startTime)
        #expect(transactions.count == 1)

        // 检查所有事件总数应该是 2（app1 创建的 1 个 + app2 创建的 1 个）
        let request = NSFetchRequest<Event>(entityName: "Event")
        let events = try app1viewContext.fetch(request)
        #expect(events.count == 2)

        cleanupStoreFiles() // 清理
    }

    @Test
    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
    func fetcherInBatchOperation() async throws {
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

        // when insert by batch
        viewContext.performAndWait {
            let event = Event(context: viewContext)
            event.timestamp = Date()
            viewContext.saveIfChanged()
        }

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

        // then
        let transactions = try fetcher.fetchTransactions(from: Date().addingTimeInterval(-2))
        #expect(transactions.count == 1)
        #expect(transactions.first?.changes?.count == 9)

        let request = NSFetchRequest<NSNumber>(entityName: "Event")
        let eventCounts = try viewContext.count(for: request)
        #expect(eventCounts == 10)
    }
}
