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
    // MARK: - Basic Registration and Removal Tests

    @Test("Register and remove merge hook")
    func registerAndRemoveMergeHook() async throws {
        let container = TestModelBuilder.createContainer(
            author: "TestAuthor",
            testName: "registerAndRemoveMergeHook")
        let hookRegistry = HookRegistryActor()
        let timestampManager = TransactionTimestampManager(
            userDefaults: UserDefaults.standard,
            maximumDuration: 604800
        )
        let processor = TransactionProcessorActor(
            container: container,
            hookRegistry: hookRegistry,
            cleanStrategy: .none,
            timestampManager: timestampManager)

        // Register a merge hook.
        let hookId = await processor.registerMergeHook { _ in
            .goOn
        }

        #expect(hookId != UUID())

        // Remove the merge hook.
        let removed = await processor.removeMergeHook(id: hookId)
        #expect(removed == true)

        // Removing again should return false.
        let removedAgain = await processor.removeMergeHook(id: hookId)
        #expect(removedAgain == false)
    }

    @Test("Remove all merge hooks")
    func removeAllMergeHooks() async throws {
        let container = TestModelBuilder.createContainer(
            author: "TestAuthor",
            testName: "removeAllMergeHooks")
        let hookRegistry = HookRegistryActor()
        let timestampManager = TransactionTimestampManager(
            userDefaults: UserDefaults.standard,
            maximumDuration: 604800
        )
        let processor = TransactionProcessorActor(
            container: container,
            hookRegistry: hookRegistry,
            cleanStrategy: .none,
            timestampManager: timestampManager)

        // Register multiple merge hooks.
        let hookId1 = await processor.registerMergeHook { _ in .goOn }
        let hookId2 = await processor.registerMergeHook { _ in .goOn }

        // Remove them all.
        await processor.removeAllMergeHooks()

        // Confirm they are gone.
        let removed1 = await processor.removeMergeHook(id: hookId1)
        let removed2 = await processor.removeMergeHook(id: hookId2)
        #expect(removed1 == false)
        #expect(removed2 == false)
    }

    // MARK: - Pipeline Execution Tests

    @Test("Merge hook pipeline - goOn keeps running")
    func mergeHookPipelineGoOn() async throws {
        let container = TestModelBuilder.createContainer(
            author: "TestAuthor",
            testName: "mergeHookPipelineGoOn")
        let hookRegistry = HookRegistryActor()
        let timestampManager = TransactionTimestampManager(
            userDefaults: UserDefaults.standard,
            maximumDuration: 604800
        )
        let processor = TransactionProcessorActor(
            container: container,
            hookRegistry: hookRegistry,
            cleanStrategy: .none,
            timestampManager: timestampManager)

        actor Counter {
            var count = 0
            func increment() { count += 1 }
            func get() -> Int { count }
        }

        let counter = Counter()

        // Register two hooks that both return .goOn.
        _ = await processor.registerMergeHook { _ in
            await counter.increment()
            return .goOn
        }

        _ = await processor.registerMergeHook { _ in
            await counter.increment()
            return .goOn
        }

        // Generate test data to trigger transactions.
        let bgContext = container.newBackgroundContext()
        bgContext.transactionAuthor = "OtherAuthor"

        try await bgContext.perform {
            TestModelBuilder.createPerson(name: "Test", age: 25, in: bgContext)
            try bgContext.save()
        }

        // Process the transactions.
        let context2 = container.newBackgroundContext()
        _ = try await processor.processNewTransactions(
            from: ["OtherAuthor"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "TestAuthor")

        // Both hooks should have run.
        let finalCount = await counter.get()
        #expect(finalCount == 2)
    }

    @Test("Merge hook pipeline - finish stops execution")
    func mergeHookPipelineFinish() async throws {
        let container = TestModelBuilder.createContainer(
            author: "TestAuthor",
            testName: "mergeHookPipelineFinish")
        let hookRegistry = HookRegistryActor()
        let timestampManager = TransactionTimestampManager(
            userDefaults: UserDefaults.standard,
            maximumDuration: 604800
        )
        let processor = TransactionProcessorActor(
            container: container,
            hookRegistry: hookRegistry,
            cleanStrategy: .none,
            timestampManager: timestampManager)

        actor Tracker {
            var hook1Called = false
            var hook2Called = false
            func setHook1Called() { hook1Called = true }
            func setHook2Called() { hook2Called = true }
            func getState() -> (Bool, Bool) { (hook1Called, hook2Called) }
        }

        let tracker = Tracker()

        // First hook returns .finish.
        _ = await processor.registerMergeHook { _ in
            await tracker.setHook1Called()
            return .finish
        }

        // Second hook should be skipped.
        _ = await processor.registerMergeHook { _ in
            await tracker.setHook2Called()
            return .goOn
        }

        // Generate test data to trigger transactions.
        let bgContext = container.newBackgroundContext()
        bgContext.transactionAuthor = "OtherAuthor"

        try await bgContext.perform {
            TestModelBuilder.createPerson(name: "Test", age: 25, in: bgContext)
            try bgContext.save()
        }

        // Process the transactions.
        let context2 = container.newBackgroundContext()
        _ = try await processor.processNewTransactions(
            from: ["OtherAuthor"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "TestAuthor")

        // Only the first hook should have run.
        let state = await tracker.getState()
        #expect(state.0 == true)
        #expect(state.1 == false)
    }

    // MARK: - Hook Ordering Tests

    @Test("Merge hook execution order")
    func mergeHookExecutionOrder() async throws {
        let container = TestModelBuilder.createContainer(
            author: "TestAuthor",
            testName: "mergeHookExecutionOrder")
        let hookRegistry = HookRegistryActor()
        let timestampManager = TransactionTimestampManager(
            userDefaults: UserDefaults.standard,
            maximumDuration: 604800
        )
        let processor = TransactionProcessorActor(
            container: container,
            hookRegistry: hookRegistry,
            cleanStrategy: .none,
            timestampManager: timestampManager)

        actor OrderTracker {
            var order: [Int] = []
            func append(_ value: Int) { order.append(value) }
            func get() -> [Int] { order }
        }

        let tracker = OrderTracker()

        // Register three hooks in order.
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

        // Generate test data.
        let bgContext = container.newBackgroundContext()
        bgContext.transactionAuthor = "OtherAuthor"

        try await bgContext.perform {
            TestModelBuilder.createPerson(name: "Test", age: 25, in: bgContext)
            try bgContext.save()
        }

        // Process the transactions.
        let context2 = container.newBackgroundContext()
        _ = try await processor.processNewTransactions(
            from: ["OtherAuthor"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "TestAuthor")

        // Verify execution order.
        let order = await tracker.get()
        #expect(order == [1, 2, 3])
    }

    @Test("Insert merge hook using the before parameter")
    func mergeHookInsertBefore() async throws {
        let container = TestModelBuilder.createContainer(
            author: "TestAuthor",
            testName: "mergeHookInsertBefore")
        let hookRegistry = HookRegistryActor()
        let timestampManager = TransactionTimestampManager(
            userDefaults: UserDefaults.standard,
            maximumDuration: 604800
        )
        let processor = TransactionProcessorActor(
            container: container,
            hookRegistry: hookRegistry,
            cleanStrategy: .none,
            timestampManager: timestampManager)

        actor OrderTracker {
            var order: [String] = []
            func append(_ value: String) { order.append(value) }
            func get() -> [String] { order }
        }

        let tracker = OrderTracker()

        // Register hook A first.
        let hookA = await processor.registerMergeHook { _ in
            await tracker.append("A")
            return .goOn
        }

        // Insert hook B before hook A.
        _ = await processor.registerMergeHook(before: hookA) { _ in
            await tracker.append("B")
            return .goOn
        }

        // Generate test data.
        let bgContext = container.newBackgroundContext()
        bgContext.transactionAuthor = "OtherAuthor"

        try await bgContext.perform {
            TestModelBuilder.createPerson(name: "Test", age: 25, in: bgContext)
            try bgContext.save()
        }

        // Process the transactions.
        let context2 = container.newBackgroundContext()
        _ = try await processor.processNewTransactions(
            from: ["OtherAuthor"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "TestAuthor")

        // Hook B should execute before hook A.
        let order = await tracker.get()
        #expect(order == ["B", "A"])
    }

    // MARK: - MergeHookInput Access Tests

    @Test("Merge hook can access transactions and contexts")
    func mergeHookAccessInput() async throws {
        let container = TestModelBuilder.createContainer(
            author: "TestAuthor",
            testName: "mergeHookAccessInput")
        let hookRegistry = HookRegistryActor()
        let timestampManager = TransactionTimestampManager(
            userDefaults: UserDefaults.standard,
            maximumDuration: 604800
        )
        let processor = TransactionProcessorActor(
            container: container,
            hookRegistry: hookRegistry,
            cleanStrategy: .none,
            timestampManager: timestampManager)

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

        // Generate test data.
        let bgContext = container.newBackgroundContext()
        bgContext.transactionAuthor = "OtherAuthor"

        try await bgContext.perform {
            TestModelBuilder.createPerson(name: "Test", age: 25, in: bgContext)
            try bgContext.save()
        }

        // Process the transactions.
        let context2 = container.newBackgroundContext()
        _ = try await processor.processNewTransactions(
            from: ["OtherAuthor"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "TestAuthor")

        let result = await tracker.get()
        #expect(result.0 >= 1) // At least 1 transaction
        #expect(result.1 == 1) // 1 context
        #expect(result.2 == true) // author is correct
    }

    // MARK: - Default Merge Fallback Tests

    @Test("Fall back to default merge when no hooks exist")
    func defaultMergeWithoutHooks() async throws {
        let container = TestModelBuilder.createContainer(
            author: "TestAuthor",
            testName: "defaultMergeWithoutHooks")
        let hookRegistry = HookRegistryActor()
        let timestampManager = TransactionTimestampManager(
            userDefaults: UserDefaults.standard,
            maximumDuration: 604800
        )
        let processor = TransactionProcessorActor(
            container: container,
            hookRegistry: hookRegistry,
            cleanStrategy: .none,
            timestampManager: timestampManager)

        // Do not register any merge hooks.

        // Generate test data.
        let bgContext = container.newBackgroundContext()
        bgContext.transactionAuthor = "OtherAuthor"

        try await bgContext.perform {
            TestModelBuilder.createPerson(name: "DefaultMergeTest", age: 30, in: bgContext)
            try bgContext.save()
        }

        // Process the transactions.
        let context2 = container.newBackgroundContext()
        let count = try await processor.processNewTransactions(
            from: ["OtherAuthor"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "TestAuthor")

        #expect(count >= 1)

        // Ensure the data merged correctly.
        try await context2.perform {
            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Person")
            fetchRequest.predicate = NSPredicate(format: "name == %@", "DefaultMergeTest")
            let results = try context2.fetch(fetchRequest)
            #expect(results.count == 1)
        }
    }
}
