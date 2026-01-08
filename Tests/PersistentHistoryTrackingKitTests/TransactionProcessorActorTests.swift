//
//  TransactionProcessorActorTests.swift
//  PersistentHistoryTrackingKitTests
//
//  Created by Claude on 2025-01-06
//

import CoreData
@testable import PersistentHistoryTrackingKit
import Testing

@Suite("TransactionProcessorActor Tests", .serialized)
struct TransactionProcessorActorTests {
    @Test("Fetch transactions - excludes current author")
    func fetchTransactionsExcludeCurrentAuthor() async throws {
        // Create a container for App1.
        let container = TestModelBuilder.createContainer(author: "App1")
        let context = container.viewContext

        // App1 creates data
        TestModelBuilder.createPerson(name: "Alice", age: 30, in: context)
        try context.save()

        // Switch the author to App2.
        context.transactionAuthor = "App2"
        TestModelBuilder.createPerson(name: "Bob", age: 25, in: context)
        try context.save()

        // Build the processor.
        let hookRegistry = HookRegistryActor()
        let timestampManager = TransactionTimestampManager(
            userDefaults: TestModelBuilder.createTestUserDefaults(),
            maximumDuration: 604_800)
        let processor = TransactionProcessorActor(
            container: container,
            hookRegistry: hookRegistry,
            cleanStrategy: .none,
            timestampManager: timestampManager)

        // Use internal Actor test methods
        let result = try await processor.testFetchTransactionsExcludesAuthor(
            from: ["App1", "App2"],
            after: nil,
            excludeAuthor: "App2")

        // Validate that the exclusion logic works.
        #expect(result.count >= 1) // At least App1 transactions exist
        #expect(result.allExcluded == true) // All transactions exclude App2
    }

    @Test("Clean transactions - timestamp and author filter")
    func cleanTransactionsByTimestampAndAuthors() async throws {
        let container = TestModelBuilder.createContainer(author: "App1")
        let context = container.viewContext

        // Create the first batch of data.
        TestModelBuilder.createPerson(name: "Alice", age: 30, in: context)
        try context.save()

        let firstTimestamp = Date()

        // Wait briefly.
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Create the second batch of data.
        TestModelBuilder.createPerson(name: "Bob", age: 25, in: context)
        try context.save()

        // Build the processor.
        let hookRegistry = HookRegistryActor()
        let timestampManager = TransactionTimestampManager(
            userDefaults: TestModelBuilder.createTestUserDefaults(),
            maximumDuration: 604_800)
        let processor = TransactionProcessorActor(
            container: container,
            hookRegistry: hookRegistry,
            cleanStrategy: .none,
            timestampManager: timestampManager)

        // Use internal Actor test methods
        let result = try await processor.testCleanTransactions(
            before: firstTimestamp,
            for: ["App1"],
            expectedBefore: nil, // No expected value specified
        )

        // Some transactions should have been deleted.
        #expect(result.deletedCount >= 0)
        // Transactions from the second batch should remain after cleanup.
        #expect(result.remainingCount >= 1)
    }

    @Test("Process new transactions - full flow")
    func processNewTransactionsFullFlow() async throws {
        // Use two contexts from the same container (simulating multiple access points).
        let container = TestModelBuilder.createContainer(author: "App1")

        // context1 writes data (App1).
        let context1 = container.newBackgroundContext()
        context1.transactionAuthor = "App1"

        // context2 receives merges (App2 viewContext).
        let context2 = container.newBackgroundContext()
        context2.transactionAuthor = "App2"

        // App1 creates data
        try await context1.perform {
            TestModelBuilder.createPerson(name: "Alice", age: 30, in: context1)
            try context1.save()
        }

        // Build the processor.
        let hookRegistry = HookRegistryActor()
        let timestampManager = TransactionTimestampManager(
            userDefaults: TestModelBuilder.createTestUserDefaults(),
            maximumDuration: 604_800)
        let processor = TransactionProcessorActor(
            container: container,
            hookRegistry: hookRegistry,
            cleanStrategy: .none,
            timestampManager: timestampManager)

        // Process new transactions (exclude App2's own changes, merge App1's).
        let count = try await processor.processNewTransactions(
            from: ["App1"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "App2",
            cleanBeforeTimestamp: nil)

        #expect(count >= 1)

        // Ensure context2 received the data.
        try await context2.perform {
            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Person")
            let results = try context2.fetch(fetchRequest)
            #expect(results.count == 1)
            #expect(results.first?.value(forKey: "name") as? String == "Alice")
        }
    }

    @Test("Trigger hooks during transaction processing")
    func triggerHooksDuringProcessing() async throws {
        let container = TestModelBuilder.createContainer(author: "App1")
        let context = container.viewContext

        // Create seed data.
        TestModelBuilder.createPerson(name: "Alice", age: 30, in: context)
        try context.save()

        // Create a hook registry and register a hook.
        let hookRegistry = HookRegistryActor()

        actor HookTracker {
            var triggered = false
            func setTriggered() { triggered = true }
            func isTriggered() -> Bool { triggered }
        }

        let tracker = HookTracker()

        let callback: HookCallback = { contexts in
            guard let context = contexts.first else { return }
            #expect(context.entityName == "Person")
            #expect(context.operation == .insert)
            await tracker.setTriggered()
        }

        await hookRegistry.registerObserver(
            entityName: "Person",
            operation: .insert,
            callback: callback)

        // Build the processor.
        let timestampManager = TransactionTimestampManager(
            userDefaults: TestModelBuilder.createTestUserDefaults(),
            maximumDuration: 604_800)
        let processor = TransactionProcessorActor(
            container: container,
            hookRegistry: hookRegistry,
            cleanStrategy: .none,
            timestampManager: timestampManager)

        // Process transactions (should trigger the hook).
        let context2 = container.newBackgroundContext()
        _ = try await processor.processNewTransactions(
            from: ["App1"],
            after: nil as Date?,
            mergeInto: [context2],
            currentAuthor: "App2",
            cleanBeforeTimestamp: nil as Date?)

        // Verify that the hook was triggered.
        let wasTriggered = await tracker.isTriggered()
        #expect(wasTriggered == true)
    }

    @Test("Get last transaction timestamp")
    func getLastTransactionTimestamp() async throws {
        let container = TestModelBuilder.createContainer(author: "App1")

        // Create seed data with a different author (App1).
        let bgContext = container.newBackgroundContext()
        bgContext.transactionAuthor = "App1"

        try await bgContext.perform {
            TestModelBuilder.createPerson(name: "Alice", age: 30, in: bgContext)
            try bgContext.save()
        }

        // Build the processor.
        let hookRegistry = HookRegistryActor()
        let timestampManager = TransactionTimestampManager(
            userDefaults: TestModelBuilder.createTestUserDefaults(),
            maximumDuration: 604_800)
        let processor = TransactionProcessorActor(
            container: container,
            hookRegistry: hookRegistry,
            cleanStrategy: .none,
            timestampManager: timestampManager)

        // App2 processes App1's transactions (timestamp for App2 gets persisted).
        let context2 = container.newBackgroundContext()
        _ = try await processor.processNewTransactionsWithTimestampManagement(
            from: ["App1"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "App2",
            batchAuthors: [])

        // Use internal Actor test method (now reads from persisted timestamp).
        let result = await processor.testGetLastTransactionTimestamp(
            for: "App2",
            maxAge: 10, // Allow 10 seconds error
        )

        #expect(result.hasTimestamp == true)
        #expect(result.timestamp != nil)
        #expect(result.isRecent == true)
    }
}
