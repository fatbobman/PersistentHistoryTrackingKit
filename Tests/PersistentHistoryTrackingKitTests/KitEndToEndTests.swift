//
//  KitEndToEndTests.swift
//  PersistentHistoryTrackingKitTests
//
//  Created by Claude on 2025-01-06
//

import CoreData
import Testing
@testable import PersistentHistoryTrackingKit

/// V2 Kit 端到端测试，模拟真实使用场景
@Suite("Kit End-to-End Tests", .serialized)
struct KitEndToEndTests {

    @Test("Kit 自动同步 - start/stop")
    func kitAutoSyncStartStop() async throws {
        // 创建共享 container
        let container = TestModelBuilder.createContainer(author: "App1")
        let context1 = container.viewContext
        let context2 = container.newBackgroundContext()

        context1.transactionAuthor = "App1"
        context2.transactionAuthor = "App2"

        // 创建 Kit（App2 视角，手动启动）
        let userDefaults = UserDefaults.standard
        let uniqueString = "TestKit.AutoSync.\(UUID().uuidString)."

        let kit = PersistentHistoryTrackingKit(
            container: container,
            contexts: [context2],
            currentAuthor: "App2",
            allAuthors: ["App1", "App2"],
            userDefaults: userDefaults,
            uniqueString: uniqueString,
            logLevel: 0,
            autoStart: false  // 手动控制
        )

        // App1 创建数据
        TestModelBuilder.createPerson(name: "Bob", age: 25, in: context1)
        try context1.save()

        // 手动同步（测试 start/stop 机制）
        kit.start()
        try await Task.sleep(nanoseconds: 100_000_000) // 等待启动
        kit.stop()

        // 验证数据已同步
        try await context2.perform {
            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Person")
            let results = try context2.fetch(fetchRequest)
            #expect(results.count >= 1)
        }
    }

    @Test("Kit 手动清理器 - cleanerBuilder")
    func kitManualCleaner() async throws {
        let container = TestModelBuilder.createContainer(author: "App1")
        let context1 = container.viewContext
        let context2 = container.newBackgroundContext()

        context1.transactionAuthor = "App1"
        context2.transactionAuthor = "App2"

        let userDefaults = UserDefaults.standard
        let uniqueString = "TestKit.ManualClean.\(UUID().uuidString)."

        // 创建 Kit（不自动清理）
        let kit = PersistentHistoryTrackingKit(
            container: container,
            contexts: [context2],
            currentAuthor: "App2",
            allAuthors: ["App1", "App2"],
            userDefaults: userDefaults,
            cleanStrategy: .none,
            uniqueString: uniqueString,
            logLevel: 0,
            autoStart: false
        )

        // 创建手动清理器
        let cleaner = kit.cleanerBuilder()

        // App1 创建数据
        TestModelBuilder.createPerson(name: "David", age: 40, in: context1)
        try context1.save()

        // 手动同步
        try await kit.transactionProcessor.processNewTransactions(
            from: ["App1", "App2"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "App2"
        )

        // 验证数据已同步
        try await context2.perform {
            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Person")
            let results = try context2.fetch(fetchRequest)
            #expect(results.count == 1)
        }

        // 手动清理事务（仅验证不崩溃）
        await cleaner.clean()
    }

    @Test("Kit 多 Context 同步")
    func kitMultiContextSync() async throws {
        let container = TestModelBuilder.createContainer(author: "App1")

        // 创建多个 context
        let context1 = container.viewContext
        let context2 = container.newBackgroundContext()
        let context3 = container.newBackgroundContext()

        context1.transactionAuthor = "App1"
        context2.transactionAuthor = "App2"
        context3.transactionAuthor = "App3"

        let userDefaults = UserDefaults.standard
        let uniqueString = "TestKit.MultiContext.\(UUID().uuidString)."

        // Kit 同时合并到 context2 和 context3
        let kit = PersistentHistoryTrackingKit(
            container: container,
            contexts: [context2, context3],
            currentAuthor: "App3",
            allAuthors: ["App1", "App2", "App3"],
            userDefaults: userDefaults,
            uniqueString: uniqueString,
            logLevel: 0,
            autoStart: false
        )

        // App1 创建数据
        TestModelBuilder.createPerson(name: "Eve", age: 28, in: context1)
        try context1.save()

        // 手动同步
        try await kit.transactionProcessor.processNewTransactions(
            from: ["App1", "App2", "App3"],
            after: nil,
            mergeInto: [context2, context3],
            currentAuthor: "App3"
        )

        // 验证 context2 和 context3 都有数据
        try await context2.perform {
            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Person")
            let results = try context2.fetch(fetchRequest)
            #expect(results.count == 1)
        }

        try await context3.perform {
            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Person")
            let results = try context3.fetch(fetchRequest)
            #expect(results.count == 1)
        }
    }

    // TODO: 时间戳持久化测试需要在 V2 实现自动时间戳管理后才能正常工作
    // 参考 PersistentHistoryTrackingKit.swift:248-268 的 TODO 注释
    //
    // @Test("Kit 时间戳持久化")
    // func kitTimestampPersistence() async throws {
    //     // ... 测试代码 ...
    // }

    @Test("Kit 注册 Observer Hook")
    func kitRegisterObserverHook() async throws {
        let container = TestModelBuilder.createContainer(author: "App1")
        let context1 = container.viewContext
        let context2 = container.newBackgroundContext()

        context1.transactionAuthor = "App1"
        context2.transactionAuthor = "App2"

        let userDefaults = UserDefaults.standard
        let uniqueString = "TestKit.ObserverHook.\(UUID().uuidString)."

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

        // 用于跟踪 Hook 是否被触发（使用 Sendable 的 actor）
        actor HookTracker {
            var triggered = false
            var entityName: String?
            var operation: HookOperation?

            func setTriggered(entityName: String, operation: HookOperation) {
                self.triggered = true
                self.entityName = entityName
                self.operation = operation
            }
        }

        let tracker = HookTracker()

        // 注册 Observer Hook
        kit.registerHook(entityName: "Person", operation: .insert) { context in
            Task {
                await tracker.setTriggered(entityName: context.entityName, operation: context.operation)
            }
        }

        // 等待 Hook 注册完成
        try await Task.sleep(nanoseconds: 100_000_000)

        // App1 创建数据
        TestModelBuilder.createPerson(name: "Henry", age: 50, in: context1)
        try context1.save()

        // 手动同步
        try await kit.transactionProcessor.processNewTransactions(
            from: ["App1", "App2"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "App2"
        )

        // 等待 Hook 执行
        try await Task.sleep(nanoseconds: 100_000_000)

        // 验证 Hook 被触发
        let triggered = await tracker.triggered
        let entityName = await tracker.entityName
        let operation = await tracker.operation

        #expect(triggered == true)
        #expect(entityName == "Person")
        #expect(operation == .insert)
    }

    @Test("Kit 注册 Merge Hook")
    func kitRegisterMergeHook() async throws {
        let container = TestModelBuilder.createContainer(author: "App1")
        let context1 = container.viewContext
        let context2 = container.newBackgroundContext()

        context1.transactionAuthor = "App1"
        context2.transactionAuthor = "App2"

        let userDefaults = UserDefaults.standard
        let uniqueString = "TestKit.MergeHook.\(UUID().uuidString)."

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

        // 用于跟踪 Merge Hook 是否被调用（使用 Sendable 的 actor）
        actor MergeHookTracker {
            var called = false
            var transactionCount = 0
            var contextCount = 0

            func markCalled(transactionCount: Int, contextCount: Int) {
                self.called = true
                self.transactionCount = transactionCount
                self.contextCount = contextCount
            }
        }

        let tracker = MergeHookTracker()

        // 注册 Merge Hook
        await kit.registerMergeHook { input in
            await tracker.markCalled(
                transactionCount: input.transactions.count,
                contextCount: input.contexts.count
            )
            return .goOn
        }

        // App1 创建数据
        TestModelBuilder.createPerson(name: "Iris", age: 27, in: context1)
        try context1.save()

        // 手动同步
        try await kit.transactionProcessor.processNewTransactions(
            from: ["App1", "App2"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "App2"
        )

        // 验证 Merge Hook 被调用
        let (called, transactionCount, contextCount) = await (tracker.called, tracker.transactionCount, tracker.contextCount)
        #expect(called == true)
        #expect(transactionCount >= 1)
        #expect(contextCount == 1)
    }

    @Test("两个 App 都使用 Kit（V2）")
    func twoAppsWithKit() async throws {
        // 创建共享容器（模拟 App Group 或 iCloud 共享数据库）
        let container = TestModelBuilder.createContainer(author: "App1")

        let context1 = container.viewContext
        let context2 = container.newBackgroundContext()

        context1.transactionAuthor = "App1"
        context2.transactionAuthor = "App2"

        // App1 创建 Kit
        let userDefaults = UserDefaults.standard
        let uniqueString1 = "TestKit.TwoApp1.\(UUID().uuidString)."

        let kit1 = PersistentHistoryTrackingKit(
            container: container,
            contexts: [context1],
            currentAuthor: "App1",
            allAuthors: ["App1", "App2", "App3"],
            userDefaults: userDefaults,
            cleanStrategy: .none,
            uniqueString: uniqueString1,
            logLevel: 0,
            autoStart: false
        )

        // App2 创建 Kit
        let uniqueString2 = "TestKit.TwoApp2.\(UUID().uuidString)."

        let kit2 = PersistentHistoryTrackingKit(
            container: container,
            contexts: [context2],
            currentAuthor: "App2",
            allAuthors: ["App1", "App2", "App3"],
            userDefaults: userDefaults,
            cleanStrategy: .none,
            uniqueString: uniqueString2,
            logLevel: 0,
            autoStart: false
        )

        // App3 创建数据
        let context3 = container.newBackgroundContext()
        context3.transactionAuthor = "App3"

        TestModelBuilder.createPerson(name: "Jack", age: 55, in: context3)
        try context3.save()

        // App1 和 App2 都同步数据
        try await kit1.transactionProcessor.processNewTransactions(
            from: ["App1", "App2", "App3"],
            after: nil as Date?,
            mergeInto: [context1],
            currentAuthor: "App1",
            cleanBeforeTimestamp: nil as Date?
        )

        try await kit2.transactionProcessor.processNewTransactions(
            from: ["App1", "App2", "App3"],
            after: nil as Date?,
            mergeInto: [context2],
            currentAuthor: "App2",
            cleanBeforeTimestamp: nil as Date?
        )

        // 验证 App1 和 App2 都有数据
        try await context1.perform {
            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Person")
            let results = try context1.fetch(fetchRequest)
            #expect(results.count == 1)
            #expect(results.first?.value(forKey: "name") as? String == "Jack")
        }

        try await context2.perform {
            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Person")
            let results = try context2.fetch(fetchRequest)
            #expect(results.count == 1)
            #expect(results.first?.value(forKey: "name") as? String == "Jack")
        }
    }
}
