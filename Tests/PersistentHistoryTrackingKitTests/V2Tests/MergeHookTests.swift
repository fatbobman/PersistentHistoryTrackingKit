//
//  MergeHookTests.swift
//  PersistentHistoryTrackingKitTests
//
//  Created by Claude on 2025-01-06
//

import CoreData
import Testing

@testable import PersistentHistoryTrackingKit

@Suite("MergeHook Tests", .serialized)
struct MergeHookTests {
    // MARK: - 基础注册和移除测试

    @Test("注册和移除 Merge Hook")
    func registerAndRemoveMergeHook() async throws {
        let container = TestModelBuilder.createContainer(
            author: "TestAuthor",
            testName: "registerAndRemoveMergeHook")
        let hookRegistry = HookRegistryActor()
        let processor = TransactionProcessorActor(
            container: container,
            hookRegistry: hookRegistry,
            cleanStrategy: .none)

        // 注册 Merge Hook
        let hookId = await processor.registerMergeHook { _ in
            .goOn
        }

        #expect(hookId != UUID())

        // 移除 Merge Hook
        let removed = await processor.removeMergeHook(id: hookId)
        #expect(removed == true)

        // 再次移除应返回 false
        let removedAgain = await processor.removeMergeHook(id: hookId)
        #expect(removedAgain == false)
    }

    @Test("移除所有 Merge Hook")
    func removeAllMergeHooks() async throws {
        let container = TestModelBuilder.createContainer(
            author: "TestAuthor",
            testName: "removeAllMergeHooks")
        let hookRegistry = HookRegistryActor()
        let processor = TransactionProcessorActor(
            container: container,
            hookRegistry: hookRegistry,
            cleanStrategy: .none)

        // 注册多个 Merge Hook
        let hookId1 = await processor.registerMergeHook { _ in .goOn }
        let hookId2 = await processor.registerMergeHook { _ in .goOn }

        // 移除所有
        await processor.removeAllMergeHooks()

        // 验证都已移除
        let removed1 = await processor.removeMergeHook(id: hookId1)
        let removed2 = await processor.removeMergeHook(id: hookId2)
        #expect(removed1 == false)
        #expect(removed2 == false)
    }

    // MARK: - 管道执行测试

    @Test("Merge Hook 管道 - goOn 继续执行")
    func mergeHookPipelineGoOn() async throws {
        let container = TestModelBuilder.createContainer(
            author: "TestAuthor",
            testName: "mergeHookPipelineGoOn")
        let hookRegistry = HookRegistryActor()
        let processor = TransactionProcessorActor(
            container: container,
            hookRegistry: hookRegistry,
            cleanStrategy: .none)

        actor Counter {
            var count = 0
            func increment() { count += 1 }
            func get() -> Int { count }
        }

        let counter = Counter()

        // 注册两个返回 .goOn 的 hook
        _ = await processor.registerMergeHook { _ in
            await counter.increment()
            return .goOn
        }

        _ = await processor.registerMergeHook { _ in
            await counter.increment()
            return .goOn
        }

        // 创建测试数据触发事务
        let bgContext = container.newBackgroundContext()
        bgContext.transactionAuthor = "OtherAuthor"

        try await bgContext.perform {
            TestModelBuilder.createPerson(name: "Test", age: 25, in: bgContext)
            try bgContext.save()
        }

        // 处理事务
        let context2 = container.newBackgroundContext()
        _ = try await processor.processNewTransactions(
            from: ["OtherAuthor"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "TestAuthor")

        // 两个 hook 都应该被执行
        let finalCount = await counter.get()
        #expect(finalCount == 2)
    }

    @Test("Merge Hook 管道 - finish 终止执行")
    func mergeHookPipelineFinish() async throws {
        let container = TestModelBuilder.createContainer(
            author: "TestAuthor",
            testName: "mergeHookPipelineFinish")
        let hookRegistry = HookRegistryActor()
        let processor = TransactionProcessorActor(
            container: container,
            hookRegistry: hookRegistry,
            cleanStrategy: .none)

        actor Tracker {
            var hook1Called = false
            var hook2Called = false
            func setHook1Called() { hook1Called = true }
            func setHook2Called() { hook2Called = true }
            func getState() -> (Bool, Bool) { (hook1Called, hook2Called) }
        }

        let tracker = Tracker()

        // 第一个 hook 返回 .finish
        _ = await processor.registerMergeHook { _ in
            await tracker.setHook1Called()
            return .finish
        }

        // 第二个 hook 不应该被执行
        _ = await processor.registerMergeHook { _ in
            await tracker.setHook2Called()
            return .goOn
        }

        // 创建测试数据触发事务
        let bgContext = container.newBackgroundContext()
        bgContext.transactionAuthor = "OtherAuthor"

        try await bgContext.perform {
            TestModelBuilder.createPerson(name: "Test", age: 25, in: bgContext)
            try bgContext.save()
        }

        // 处理事务
        let context2 = container.newBackgroundContext()
        _ = try await processor.processNewTransactions(
            from: ["OtherAuthor"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "TestAuthor")

        // 只有第一个 hook 被执行
        let state = await tracker.getState()
        #expect(state.0 == true)
        #expect(state.1 == false)
    }

    // MARK: - Hook 顺序测试

    @Test("Merge Hook 执行顺序")
    func mergeHookExecutionOrder() async throws {
        let container = TestModelBuilder.createContainer(
            author: "TestAuthor",
            testName: "mergeHookExecutionOrder")
        let hookRegistry = HookRegistryActor()
        let processor = TransactionProcessorActor(
            container: container,
            hookRegistry: hookRegistry,
            cleanStrategy: .none)

        actor OrderTracker {
            var order: [Int] = []
            func append(_ value: Int) { order.append(value) }
            func get() -> [Int] { order }
        }

        let tracker = OrderTracker()

        // 按顺序注册三个 hook
        _ = await processor.registerMergeHook { _ in
            await tracker.append(1)
            return .goOn
        }

        _ = await processor.registerMergeHook { _ in
            await tracker.append(2)
            return .goOn
        }

        _ = await processor.registerMergeHook { _ in
            await tracker.append(3)
            return .goOn
        }

        // 创建测试数据触发事务
        let bgContext = container.newBackgroundContext()
        bgContext.transactionAuthor = "OtherAuthor"

        try await bgContext.perform {
            TestModelBuilder.createPerson(name: "Test", age: 25, in: bgContext)
            try bgContext.save()
        }

        // 处理事务
        let context2 = container.newBackgroundContext()
        _ = try await processor.processNewTransactions(
            from: ["OtherAuthor"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "TestAuthor")

        // 验证执行顺序
        let order = await tracker.get()
        #expect(order == [1, 2, 3])
    }

    @Test("使用 before 参数插入 Merge Hook")
    func mergeHookInsertBefore() async throws {
        let container = TestModelBuilder.createContainer(
            author: "TestAuthor",
            testName: "mergeHookInsertBefore")
        let hookRegistry = HookRegistryActor()
        let processor = TransactionProcessorActor(
            container: container,
            hookRegistry: hookRegistry,
            cleanStrategy: .none)

        actor OrderTracker {
            var order: [String] = []
            func append(_ value: String) { order.append(value) }
            func get() -> [String] { order }
        }

        let tracker = OrderTracker()

        // 先注册 hook A
        let hookA = await processor.registerMergeHook { _ in
            await tracker.append("A")
            return .goOn
        }

        // 在 hook A 之前插入 hook B
        _ = await processor.registerMergeHook(before: hookA) { _ in
            await tracker.append("B")
            return .goOn
        }

        // 创建测试数据触发事务
        let bgContext = container.newBackgroundContext()
        bgContext.transactionAuthor = "OtherAuthor"

        try await bgContext.perform {
            TestModelBuilder.createPerson(name: "Test", age: 25, in: bgContext)
            try bgContext.save()
        }

        // 处理事务
        let context2 = container.newBackgroundContext()
        _ = try await processor.processNewTransactions(
            from: ["OtherAuthor"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "TestAuthor")

        // B 应该在 A 之前执行
        let order = await tracker.get()
        #expect(order == ["B", "A"])
    }

    // MARK: - MergeHookInput 访问测试

    @Test("Merge Hook 可以访问 transactions 和 contexts")
    func mergeHookAccessInput() async throws {
        let container = TestModelBuilder.createContainer(
            author: "TestAuthor",
            testName: "mergeHookAccessInput")
        let hookRegistry = HookRegistryActor()
        let processor = TransactionProcessorActor(
            container: container,
            hookRegistry: hookRegistry,
            cleanStrategy: .none)

        actor InputTracker {
            var transactionCount = 0
            var contextCount = 0
            var hasAuthor = false

            func record(transactions: Int, contexts: Int, hasAuthor: Bool) {
                self.transactionCount = transactions
                self.contextCount = contexts
                self.hasAuthor = hasAuthor
            }

            func get() -> (Int, Int, Bool) {
                (transactionCount, contextCount, hasAuthor)
            }
        }

        let tracker = InputTracker()

        _ = await processor.registerMergeHook { input in
            let txCount = input.transactions.count
            let ctxCount = input.contexts.count
            let hasAuthor = input.transactions.first?.author == "OtherAuthor"
            await tracker.record(transactions: txCount, contexts: ctxCount, hasAuthor: hasAuthor)
            return .goOn
        }

        // 创建测试数据触发事务
        let bgContext = container.newBackgroundContext()
        bgContext.transactionAuthor = "OtherAuthor"

        try await bgContext.perform {
            TestModelBuilder.createPerson(name: "Test", age: 25, in: bgContext)
            try bgContext.save()
        }

        // 处理事务
        let context2 = container.newBackgroundContext()
        _ = try await processor.processNewTransactions(
            from: ["OtherAuthor"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "TestAuthor")

        let result = await tracker.get()
        #expect(result.0 >= 1) // 至少有 1 个 transaction
        #expect(result.1 == 1) // 1 个 context
        #expect(result.2 == true) // author 正确
    }

    // MARK: - 默认合并兜底测试

    @Test("无 Merge Hook 时使用默认合并")
    func defaultMergeWithoutHooks() async throws {
        let container = TestModelBuilder.createContainer(
            author: "TestAuthor",
            testName: "defaultMergeWithoutHooks")
        let hookRegistry = HookRegistryActor()
        let processor = TransactionProcessorActor(
            container: container,
            hookRegistry: hookRegistry,
            cleanStrategy: .none)

        // 不注册任何 merge hook

        // 创建测试数据
        let bgContext = container.newBackgroundContext()
        bgContext.transactionAuthor = "OtherAuthor"

        try await bgContext.perform {
            TestModelBuilder.createPerson(name: "DefaultMergeTest", age: 30, in: bgContext)
            try bgContext.save()
        }

        // 处理事务
        let context2 = container.newBackgroundContext()
        let count = try await processor.processNewTransactions(
            from: ["OtherAuthor"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "TestAuthor")

        #expect(count >= 1)

        // 验证数据已合并
        try await context2.perform {
            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Person")
            fetchRequest.predicate = NSPredicate(format: "name == %@", "DefaultMergeTest")
            let results = try context2.fetch(fetchRequest)
            #expect(results.count == 1)
        }
    }
}

