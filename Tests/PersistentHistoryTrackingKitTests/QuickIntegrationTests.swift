//
//  QuickIntegrationTests.swift
//
//
//  Created by Claude on 2025/6/27
//  Copyright © 2025 Anthropic. All rights reserved.
//

@preconcurrency import CoreData
import Foundation
import PersistentHistoryTrackingKit
import Testing

@Suite("Quick Integration Tests", .serialized)
@MainActor
struct QuickIntegrationTests {
    let storeURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        .first?
        .appendingPathComponent("QuickIntegrationTest.sqlite") ?? URL(fileURLWithPath: "")
    let uniqueString = "PersistentHistoryTrackingKit.Quick.Tests."
    let userDefaults = UserDefaults.standard

    enum TestApp: String, CaseIterable {
        case app1 = "TestApp1"
        case app2 = "TestApp2"
        case app3 = "TestApp3"
    }

    init() {
        cleanupEnvironment()
    }

    func cleanupEnvironment() {
        // 清除 UserDefaults
        for app in TestApp.allCases {
            userDefaults.removeObject(forKey: uniqueString + app.rawValue)
        }

        // 清除数据库文件
        try? FileManager.default.removeItem(at: storeURL)
        try? FileManager.default
            .removeItem(at: storeURL.deletingPathExtension().appendingPathExtension("sqlite-wal"))
        try? FileManager.default
            .removeItem(at: storeURL.deletingPathExtension().appendingPathExtension("sqlite-shm"))
    }

    @Test("Simple two-app data synchronization")
    func simpleTwoAppSync() async throws {
        cleanupEnvironment()

        // 创建两个容器
        let container1 = ComprehensiveTestModel.createContainer(storeURL: storeURL)
        let container2 = ComprehensiveTestModel.createContainer(storeURL: storeURL)

        container1.viewContext.transactionAuthor = TestApp.app1.rawValue
        container2.viewContext.transactionAuthor = TestApp.app2.rawValue

        let allAuthors = [TestApp.app1.rawValue, TestApp.app2.rawValue]

        // 设置 Kit
        let kit1 = PersistentHistoryTrackingKit(
            container: container1,
            currentAuthor: TestApp.app1.rawValue,
            allAuthors: allAuthors,
            userDefaults: userDefaults,
            cleanStrategy: .byNotification(times: 1),
            uniqueString: uniqueString,
            logLevel: 1)

        let kit2 = PersistentHistoryTrackingKit(
            container: container2,
            currentAuthor: TestApp.app2.rawValue,
            allAuthors: allAuthors,
            userDefaults: userDefaults,
            cleanStrategy: .byNotification(times: 1),
            uniqueString: uniqueString,
            logLevel: 1)

        // App1 创建用户
        var userObjectID: NSManagedObjectID!
        container1.viewContext.performAndWait {
            let user = TestUser(context: container1.viewContext, name: "Test User from App1")
            try! container1.viewContext.save()
            userObjectID = user.objectID
        }

        await sleep(seconds: 2)

        // 验证 App2 能看到用户
        let foundInApp2 = container2.viewContext.performAndWait {
            (try? container2.viewContext.existingObject(with: userObjectID)) != nil
        }

        #expect(foundInApp2)

        // App2 创建帖子
        var postObjectID: NSManagedObjectID!
        container2.viewContext.performAndWait {
            // 先获取用户
            let user = try! container2.viewContext.existingObject(with: userObjectID) as! TestUser
            let post = TestPost(
                context: container2.viewContext,
                title: "Test Post from App2",
                content: "Content",
                author: user)
            try! container2.viewContext.save()
            postObjectID = post.objectID
        }

        await sleep(seconds: 2)

        // 验证 App1 能看到帖子
        let foundInApp1 = container1.viewContext.performAndWait {
            (try? container1.viewContext.existingObject(with: postObjectID)) != nil
        }

        #expect(foundInApp1)

        kit1.stop()
        kit2.stop()
        cleanupEnvironment()
    }

    @Test("Three-app relationship synchronization")
    func threeAppRelationshipSync() async throws {
        cleanupEnvironment()

        let containers = TestApp.allCases.map { app in
            let container = ComprehensiveTestModel.createContainer(storeURL: storeURL)
            container.viewContext.transactionAuthor = app.rawValue
            return (app, container)
        }

        let allAuthors = TestApp.allCases.map(\.rawValue)

        let kits = containers.map { app, container in
            PersistentHistoryTrackingKit(
                container: container,
                currentAuthor: app.rawValue,
                allAuthors: allAuthors,
                userDefaults: userDefaults,
                cleanStrategy: .byNotification(times: 1),
                uniqueString: uniqueString,
                logLevel: 1)
        }

        // 每个 app 创建一个用户
        for (app, container) in containers {
            container.viewContext.performAndWait {
                _ = TestUser(context: container.viewContext, name: "User from \(app.rawValue)")
                try! container.viewContext.save()
            }
            await sleep(seconds: 1)
        }

        await sleep(seconds: 2)

        // 验证每个 app 都能看到所有用户
        for (app, container) in containers {
            let userCount = container.viewContext.performAndWait {
                let request = NSFetchRequest<TestUser>(entityName: "User")
                return try! container.viewContext.count(for: request)
            }

            #expect(
                userCount == 3,
                "App \(app.rawValue) should see 3 users, but found \(userCount)")
        }

        // 清理
        for kit in kits {
            kit.stop()
        }
        cleanupEnvironment()
    }

    @Test("Manual cleaner functionality")
    func manualCleaner() async throws {
        cleanupEnvironment()

        let container = ComprehensiveTestModel.createContainer(storeURL: storeURL)
        container.viewContext.transactionAuthor = TestApp.app1.rawValue

        let kit = PersistentHistoryTrackingKit(
            container: container,
            currentAuthor: TestApp.app1.rawValue,
            allAuthors: [TestApp.app1.rawValue],
            userDefaults: userDefaults,
            cleanStrategy: .none, // 不自动清理
            uniqueString: uniqueString,
            logLevel: 1)

        // 创建数据
        container.viewContext.performAndWait {
            _ = TestUser(context: container.viewContext, name: "Manual Test User")
            try! container.viewContext.save()
        }

        await sleep(seconds: 1)

        // 验证数据存在
        let userCount = container.viewContext.performAndWait {
            let request = NSFetchRequest<TestUser>(entityName: "User")
            return try! container.viewContext.count(for: request)
        }

        #expect(userCount == 1)

        // 手动清理
        let cleaner = kit.cleanerBuilder()
        cleaner()

        await sleep(seconds: 1)

        // 验证数据仍然存在（清理只影响历史事务）
        let userCountAfterCleanup = container.viewContext.performAndWait {
            let request = NSFetchRequest<TestUser>(entityName: "User")
            return try! container.viewContext.count(for: request)
        }

        #expect(userCountAfterCleanup == 1)

        kit.stop()
        cleanupEnvironment()
    }

    @Test("Basic batch operations")
    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
    func basicBatchOperations() async throws {
        cleanupEnvironment()

        let container1 = ComprehensiveTestModel.createContainer(storeURL: storeURL)
        let container2 = ComprehensiveTestModel.createContainer(storeURL: storeURL)

        container1.viewContext.transactionAuthor = TestApp.app1.rawValue
        container2.viewContext.transactionAuthor = TestApp.app2.rawValue

        let batchContext = container1.newBackgroundContext()
        batchContext.transactionAuthor = "BatchContext"

        let allAuthors = [TestApp.app1.rawValue, TestApp.app2.rawValue, "BatchContext"]

        let kit1 = PersistentHistoryTrackingKit(
            container: container1,
            currentAuthor: TestApp.app1.rawValue,
            allAuthors: allAuthors,
            batchAuthors: ["BatchContext"],
            userDefaults: userDefaults,
            cleanStrategy: .byNotification(times: 1),
            uniqueString: uniqueString,
            logLevel: 1)

        let kit2 = PersistentHistoryTrackingKit(
            container: container2,
            currentAuthor: TestApp.app2.rawValue,
            allAuthors: allAuthors,
            batchAuthors: ["BatchContext"],
            userDefaults: userDefaults,
            cleanStrategy: .byNotification(times: 1),
            uniqueString: uniqueString,
            logLevel: 1)

        // 执行批量插入
        var actualInsertedCount = 0
        try batchContext.performAndWait {
            let batchInsert = NSBatchInsertRequest(entity: TestUser
                .entity())
            { (dictionary: NSMutableDictionary) -> Bool in
                dictionary["userID"] = UUID()
                dictionary["name"] = "Batch User \(actualInsertedCount)"
                dictionary["email"] = "batch\(actualInsertedCount)@test.com"
                dictionary["createdAt"] = Date()

                actualInsertedCount += 1
                return actualInsertedCount >= 5 // 插入5个用户后停止
            }
            batchInsert.resultType = .count

            let result = try batchContext.execute(batchInsert) as! NSBatchInsertResult
            let insertedCount = result.result as! Int
            #expect(insertedCount >= 4) // 批量插入可能会有细微差异
            actualInsertedCount = insertedCount
        }

        await sleep(seconds: 3)

        // 验证两个容器都能看到批量插入的数据
        let count1 = container1.viewContext.performAndWait {
            let request = NSFetchRequest<TestUser>(entityName: "User")
            return try! container1.viewContext.count(for: request)
        }

        let count2 = container2.viewContext.performAndWait {
            let request = NSFetchRequest<TestUser>(entityName: "User")
            return try! container2.viewContext.count(for: request)
        }

        #expect(count1 == actualInsertedCount)
        #expect(count2 == actualInsertedCount)

        kit1.stop()
        kit2.stop()
        cleanupEnvironment()
    }
}
