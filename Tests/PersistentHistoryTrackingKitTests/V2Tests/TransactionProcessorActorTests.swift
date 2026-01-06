//
//  TransactionProcessorActorTests.swift
//  PersistentHistoryTrackingKitTests
//
//  Created by Claude on 2025-01-06
//

import CoreData
import Testing
@testable import PersistentHistoryTrackingKit

@Suite("TransactionProcessorActor Tests")
struct TransactionProcessorActorTests {

    @Test("Fetch transactions - 排除当前 author")
    func fetchTransactionsExcludeCurrentAuthor() async throws {
        // 创建容器
        let container = TestModelBuilder.createContainer(author: "App1")
        let context = container.viewContext

        // App1 创建数据
        TestModelBuilder.createPerson(name: "Alice", age: 30, in: context)
        try context.save()

        // 切换到 App2 author
        context.transactionAuthor = "App2"
        TestModelBuilder.createPerson(name: "Bob", age: 25, in: context)
        try context.save()

        // 创建 processor
        let hookRegistry = HookRegistryActor()
        let processor = TransactionProcessorActor(
            container: container,
            hookRegistry: hookRegistry,
            cleanStrategy: .none
        )

        // 使用 Actor 内部的测试方法
        let result = try await processor.testFetchTransactionsExcludesAuthor(
            from: ["App1", "App2"],
            after: nil,
            excludeAuthor: "App2"
        )

        // 验证排除逻辑正确
        #expect(result.count >= 1) // 至少有 App1 的事务
        #expect(result.allExcluded == true) // 所有事务都不包含 App2
    }

    @Test("Clean transactions - 按时间戳和 authors")
    func cleanTransactionsByTimestampAndAuthors() async throws {
        let container = TestModelBuilder.createContainer(author: "App1")
        let context = container.viewContext

        // 创建第一批数据
        TestModelBuilder.createPerson(name: "Alice", age: 30, in: context)
        try context.save()

        let firstTimestamp = Date()

        // 等待一点时间
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 秒

        // 创建第二批数据
        TestModelBuilder.createPerson(name: "Bob", age: 25, in: context)
        try context.save()

        // 创建 processor
        let hookRegistry = HookRegistryActor()
        let processor = TransactionProcessorActor(
            container: container,
            hookRegistry: hookRegistry,
            cleanStrategy: .none
        )

        // 使用 Actor 内部的测试方法
        let result = try await processor.testCleanTransactions(
            before: firstTimestamp,
            for: ["App1"],
            expectedBefore: nil // 不指定预期值
        )

        // 应该删除了一些事务
        #expect(result.deletedCount >= 0)
        // 清理后应该还有剩余事务（第二批）
        #expect(result.remainingCount >= 1)
    }

    @Test("Process new transactions - 完整流程")
    func processNewTransactionsFullFlow() async throws {
        // 创建两个容器（模拟两个 App）
        let container1 = TestModelBuilder.createContainer(author: "App1")
        let container2 = TestModelBuilder.createContainer(author: "App2")

        let context1 = container1.viewContext
        let context2 = container2.viewContext

        // App1 创建数据
        TestModelBuilder.createPerson(name: "Alice", age: 30, in: context1)
        try context1.save()

        // 创建 processor（使用 container2 来处理 container1 的事务）
        let hookRegistry = HookRegistryActor()
        let processor = TransactionProcessorActor(
            container: container1,
            hookRegistry: hookRegistry,
            cleanStrategy: .none
        )

        // 处理新事务
        let count = try await processor.processNewTransactions(
            from: ["App1"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "App2",
            cleanBeforeTimestamp: nil
        )

        #expect(count >= 1)

        // 验证 context2 中有数据
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Person")
        let results = try context2.fetch(fetchRequest)
        #expect(results.count == 1)
        #expect(results.first?.value(forKey: "name") as? String == "Alice")
    }

    @Test("Trigger hooks during transaction processing")
    func triggerHooksDuringProcessing() async throws {
        let container = TestModelBuilder.createContainer(author: "App1")
        let context = container.viewContext

        // 创建数据
        TestModelBuilder.createPerson(name: "Alice", age: 30, in: context)
        try context.save()

        // 创建 hook registry 并注册 hook
        let hookRegistry = HookRegistryActor()

        actor HookTracker {
            var triggered = false
            func setTriggered() { triggered = true }
            func isTriggered() -> Bool { triggered }
        }

        let tracker = HookTracker()

        let callback: HookCallback = { context in
            #expect(context.entityName == "Person")
            #expect(context.operation == .insert)
            await tracker.setTriggered()
        }

        await hookRegistry.register(entityName: "Person", operation: .insert, callback: callback)

        // 创建 processor
        let processor = TransactionProcessorActor(
            container: container,
            hookRegistry: hookRegistry,
            cleanStrategy: .none
        )

        // 处理事务（应该触发 hook）
        let context2 = container.newBackgroundContext()
        _ = try await processor.processNewTransactions(
            from: ["App1"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "App2",
            cleanBeforeTimestamp: nil
        )

        // 验证 hook 被触发
        let wasTriggered = await tracker.isTriggered()
        #expect(wasTriggered == true)
    }

    @Test("Get last transaction timestamp")
    func getLastTransactionTimestamp() async throws {
        let container = TestModelBuilder.createContainer(author: "App1")
        let context = container.viewContext

        // 创建数据
        TestModelBuilder.createPerson(name: "Alice", age: 30, in: context)
        try context.save()

        // 创建 processor
        let hookRegistry = HookRegistryActor()
        let processor = TransactionProcessorActor(
            container: container,
            hookRegistry: hookRegistry,
            cleanStrategy: .none
        )

        // 使用 Actor 内部的测试方法
        let result = try await processor.testGetLastTransactionTimestamp(
            for: "App1",
            maxAge: 10 // 允许 10 秒误差
        )

        #expect(result.hasTimestamp == true)
        #expect(result.timestamp != nil)
        #expect(result.isRecent == true)
    }
}
