//
//  IntegrationTests.swift
//  PersistentHistoryTrackingKitTests
//
//  Created by Claude on 2025-01-06
//

import CoreData
import Testing
@testable import PersistentHistoryTrackingKit

@Suite("PersistentHistoryTrackingKit V2 Integration Tests", .serialized)
struct IntegrationTests {

    @Test("两个 App 简单同步")
    func simpleTwoAppSync() async throws {
        // 创建共享的 container（模拟共享数据库）
        let container = TestModelBuilder.createContainer(author: "App1")

        // 创建两个 context
        let context1 = container.viewContext
        let context2 = container.newBackgroundContext()

        context1.transactionAuthor = "App1"
        context2.transactionAuthor = "App2"

        // App1 创建数据
        TestModelBuilder.createPerson(name: "Alice", age: 30, in: context1)
        try context1.save()

        // 创建 Kit（App2 视角）
        let userDefaults = UserDefaults.standard
        let uniqueString = "TestKit.SimpleTwoApp.\(UUID().uuidString)."

        let kit = PersistentHistoryTrackingKit(
            container: container,
            contexts: [context2],
            currentAuthor: "App2",
            allAuthors: ["App1", "App2"],
            userDefaults: userDefaults,
            uniqueString: uniqueString,
            logLevel: 0,
            autoStart: false
        )

        // 手动触发一次同步
        try await kit.transactionProcessor.processNewTransactions(
            from: ["App1", "App2"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "App2",
            cleanBeforeTimestamp: nil
        )

        // 验证 context2 中有 App1 创建的数据
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Person")
        let results = try context2.fetch(fetchRequest)

        #expect(results.count == 1)
        #expect(results.first?.value(forKey: "name") as? String == "Alice")
    }

    @Test("Hook 触发测试")
    func hookTriggerIntegration() async throws {
        let container = TestModelBuilder.createContainer(author: "App1")
        let context1 = container.viewContext
        let context2 = container.newBackgroundContext()

        context1.transactionAuthor = "App1"
        context2.transactionAuthor = "App2"

        // 创建 Kit
        let userDefaults = UserDefaults.standard
        let uniqueString = "TestKit.HookTrigger.\(UUID().uuidString)."

        let kit = PersistentHistoryTrackingKit(
            container: container,
            contexts: [context2],
            currentAuthor: "App2",
            allAuthors: ["App1", "App2"],
            userDefaults: userDefaults,
            uniqueString: uniqueString,
            logLevel: 0,
            autoStart: false
        )

        // 注册 Hook
        actor HookTracker {
            var insertCount = 0
            var updateCount = 0
            var deleteCount = 0

            func recordInsert() { insertCount += 1 }
            func recordUpdate() { updateCount += 1 }
            func recordDelete() { deleteCount += 1 }

            func getCounts() -> (insert: Int, update: Int, delete: Int) {
                (insertCount, updateCount, deleteCount)
            }
        }

        let tracker = HookTracker()

        kit.registerHook(entityName: "Person", operation: .insert) { _ in
            await tracker.recordInsert()
        }

        kit.registerHook(entityName: "Person", operation: .update) { _ in
            await tracker.recordUpdate()
        }

        kit.registerHook(entityName: "Person", operation: .delete) { _ in
            await tracker.recordDelete()
        }

        // App1 创建数据
        let person = TestModelBuilder.createPerson(name: "Alice", age: 30, in: context1)
        try context1.save()

        // 手动触发同步
        try await kit.transactionProcessor.processNewTransactions(
            from: ["App1", "App2"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "App2",
            cleanBeforeTimestamp: nil
        )

        // 验证 Insert Hook 被触发
        let counts1 = await tracker.getCounts()
        #expect(counts1.insert >= 1)

        // App1 更新数据
        person.setValue(31, forKey: "age")
        try context1.save()

        // 再次同步
        try await kit.transactionProcessor.processNewTransactions(
            from: ["App1", "App2"],
            after: Date(timeIntervalSinceNow: -10),
            mergeInto: [context2],
            currentAuthor: "App2",
            cleanBeforeTimestamp: nil
        )

        // 验证 Update Hook 被触发
        let counts2 = await tracker.getCounts()
        #expect(counts2.update >= 1)

        // App1 删除数据
        context1.delete(person)
        try context1.save()

        // 再次同步
        try await kit.transactionProcessor.processNewTransactions(
            from: ["App1", "App2"],
            after: Date(timeIntervalSinceNow: -10),
            mergeInto: [context2],
            currentAuthor: "App2",
            cleanBeforeTimestamp: nil
        )

        // 验证 Delete Hook 被触发
        let counts3 = await tracker.getCounts()
        #expect(counts3.delete >= 1)
    }

    @Test("手动清理器测试")
    func manualCleanerIntegration() async throws {
        let container = TestModelBuilder.createContainer(author: "App1")
        let context = container.viewContext

        // 创建数据
        TestModelBuilder.createPerson(name: "Alice", age: 30, in: context)
        try context.save()

        // 创建 Kit
        let userDefaults = UserDefaults.standard
        let uniqueString = "TestKit.ManualCleaner.\(UUID().uuidString)."

        // 保存时间戳
        userDefaults.set(Date(), forKey: uniqueString + "App1")

        let kit = PersistentHistoryTrackingKit(
            container: container,
            contexts: [context],
            currentAuthor: "App1",
            allAuthors: ["App1"],
            userDefaults: userDefaults,
            uniqueString: uniqueString,
            logLevel: 0,
            autoStart: false
        )

        // 创建 cleaner
        let cleaner = kit.cleanerBuilder()

        // 执行清理
        await cleaner.clean()

        // 验证数据仍然存在
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Person")
        let results = try context.fetch(fetchRequest)
        #expect(results.count == 1)
    }

    @Test("批量操作同步")
    func batchOperationSync() async throws {
        let container = TestModelBuilder.createContainer(author: "App1")
        let context1 = container.viewContext
        let context2 = container.newBackgroundContext()

        context1.transactionAuthor = "App1"
        context2.transactionAuthor = "App2"

        // App1 批量创建数据
        for i in 0..<10 {
            TestModelBuilder.createPerson(name: "Person\(i)", age: Int32(20 + i), in: context1)
        }
        try context1.save()

        // 创建 Kit（App2 视角）
        let userDefaults = UserDefaults.standard
        let uniqueString = "TestKit.BatchOperation.\(UUID().uuidString)."

        let kit = PersistentHistoryTrackingKit(
            container: container,
            contexts: [context2],
            currentAuthor: "App2",
            allAuthors: ["App1", "App2"],
            userDefaults: userDefaults,
            uniqueString: uniqueString,
            logLevel: 0,
            autoStart: false
        )

        // 手动触发同步
        try await kit.transactionProcessor.processNewTransactions(
            from: ["App1", "App2"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "App2",
            cleanBeforeTimestamp: nil
        )

        // 验证所有数据都同步了
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Person")
        let results = try context2.fetch(fetchRequest)
        #expect(results.count == 10)
    }

    @Test("多 Context 同步")
    func multiContextSync() async throws {
        let container = TestModelBuilder.createContainer(author: "App1")
        let context1 = container.viewContext
        let context2 = container.newBackgroundContext()
        let context3 = container.newBackgroundContext()

        context1.transactionAuthor = "App1"
        context2.transactionAuthor = "App2"
        context3.transactionAuthor = "App2"

        // App1 创建数据
        TestModelBuilder.createPerson(name: "Alice", age: 30, in: context1)
        try context1.save()

        // 创建 Kit（App2 视角，合并到两个 context）
        let userDefaults = UserDefaults.standard
        let uniqueString = "TestKit.MultiContext.\(UUID().uuidString)."

        let kit = PersistentHistoryTrackingKit(
            container: container,
            contexts: [context2, context3],
            currentAuthor: "App2",
            allAuthors: ["App1", "App2"],
            userDefaults: userDefaults,
            uniqueString: uniqueString,
            logLevel: 0,
            autoStart: false
        )

        // 手动触发同步
        try await kit.transactionProcessor.processNewTransactions(
            from: ["App1", "App2"],
            after: nil,
            mergeInto: [context2, context3],
            currentAuthor: "App2",
            cleanBeforeTimestamp: nil
        )

        // 验证两个 context 都有数据
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Person")
        let results2 = try context2.fetch(fetchRequest)
        let results3 = try context3.fetch(fetchRequest)

        #expect(results2.count == 1)
        #expect(results3.count == 1)
    }
}
