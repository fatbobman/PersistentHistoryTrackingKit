//
//  KitEndToEndTests.swift
//  PersistentHistoryTrackingKitTests
//
//  Created by Claude on 2025-01-06
//

import CoreData
import Testing
@testable import PersistentHistoryTrackingKit

/// V2 kit end-to-end scenarios that simulate real usage.
@Suite("Kit End-to-End Tests", .serialized)
struct KitEndToEndTests {

    @Test("Kit auto sync - start/stop")
    func kitAutoSyncStartStop() async throws {
        // Create shared container
        let container = TestModelBuilder.createContainer(author: "App1")
        let context1 = container.viewContext
        let context2 = container.newBackgroundContext()

        context1.transactionAuthor = "App1"
        context2.transactionAuthor = "App2"

        // Create the kit from App2's perspective (manual start).
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
            autoStart: false  // manual control
        )

        // App1 creates data
        TestModelBuilder.createPerson(name: "Bob", age: 25, in: context1)
        try context1.save()

        // Manual sync (exercise start/stop behavior).
        kit.start()
        try await Task.sleep(nanoseconds: 100_000_000) // Wait for the task to start.
        kit.stop()

        // Verify data synced
        try await context2.perform {
            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Person")
            let results = try context2.fetch(fetchRequest)
            #expect(results.count >= 1)
        }
    }

    @Test("Kit manual cleaner via cleanerBuilder")
    func kitManualCleaner() async throws {
        let container = TestModelBuilder.createContainer(author: "App1")
        let context1 = container.viewContext
        let context2 = container.newBackgroundContext()

        context1.transactionAuthor = "App1"
        context2.transactionAuthor = "App2"

        let userDefaults = UserDefaults.standard
        let uniqueString = "TestKit.ManualClean.\(UUID().uuidString)."

        // Create the kit (without automatic cleanup).
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

        // Create manual cleaner
        let cleaner = kit.cleanerBuilder()

        // App1 creates data
        TestModelBuilder.createPerson(name: "David", age: 40, in: context1)
        try context1.save()

        // Manual sync
        try await kit.transactionProcessor.processNewTransactions(
            from: ["App1", "App2"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "App2"
        )

        // Verify data synced
        try await context2.perform {
            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Person")
            let results = try context2.fetch(fetchRequest)
            #expect(results.count == 1)
        }

        // Manually run cleanup (just verify it succeeds).
        await cleaner.clean()
    }

    @Test("Kit multi-context synchronization")
    func kitMultiContextSync() async throws {
        let container = TestModelBuilder.createContainer(author: "App1")

        // Create multiple contexts
        let context1 = container.viewContext
        let context2 = container.newBackgroundContext()
        let context3 = container.newBackgroundContext()

        context1.transactionAuthor = "App1"
        context2.transactionAuthor = "App2"
        context3.transactionAuthor = "App3"

        let userDefaults = UserDefaults.standard
        let uniqueString = "TestKit.MultiContext.\(UUID().uuidString)."

        // Kit merges into both context2 and context3.
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

        // App1 creates data
        TestModelBuilder.createPerson(name: "Eve", age: 28, in: context1)
        try context1.save()

        // Manual sync
        try await kit.transactionProcessor.processNewTransactions(
            from: ["App1", "App2", "App3"],
            after: nil,
            mergeInto: [context2, context3],
            currentAuthor: "App3"
        )

        // Ensure context2 and context3 both receive the data.
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

    // TODO: Timestamp persistence tests depend on automated timestamp management.
    // See the TODO comment around PersistentHistoryTrackingKit.swift:248-268.
    //
    // @Test("Kit timestamp persistence")
    // func kitTimestampPersistence() async throws {
    //     // ... test code ...
    // }

    @Test("Kit registers an observer hook")
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

        // Track if the hook was triggered (using a Sendable actor).
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

        // Register Observer Hook
        kit.registerHook(entityName: "Person", operation: .insert) { context in
            Task {
                await tracker.setTriggered(entityName: context.entityName, operation: context.operation)
            }
        }

        // Wait for hook registration to complete.
        try await Task.sleep(nanoseconds: 100_000_000)

        // App1 creates data
        TestModelBuilder.createPerson(name: "Henry", age: 50, in: context1)
        try context1.save()

        // Manual sync
        try await kit.transactionProcessor.processNewTransactions(
            from: ["App1", "App2"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "App2"
        )

        // Wait for the hook to fire.
        try await Task.sleep(nanoseconds: 100_000_000)

        // Verify Hook was triggered
        let triggered = await tracker.triggered
        let entityName = await tracker.entityName
        let operation = await tracker.operation

        #expect(triggered == true)
        #expect(entityName == "Person")
        #expect(operation == .insert)
    }

    @Test("Kit registers a merge hook")
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

        // Track if the merge hook was called (Sendable actor).
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

        // Register the merge hook.
        await kit.registerMergeHook { input in
            await tracker.markCalled(
                transactionCount: input.transactions.count,
                contextCount: input.contexts.count
            )
            return .goOn
        }

        // App1 creates data
        TestModelBuilder.createPerson(name: "Iris", age: 27, in: context1)
        try context1.save()

        // Manual sync
        try await kit.transactionProcessor.processNewTransactions(
            from: ["App1", "App2"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "App2"
        )

        // Verify that the merge hook ran.
        let (called, transactionCount, contextCount) = await (tracker.called, tracker.transactionCount, tracker.contextCount)
        #expect(called == true)
        #expect(transactionCount >= 1)
        #expect(contextCount == 1)
    }

    @Test("Two apps use the kit (V2)")
    func twoAppsWithKit() async throws {
        // Create a shared container (simulating an App Group or shared iCloud store).
        let container = TestModelBuilder.createContainer(author: "App1")

        let context1 = container.viewContext
        let context2 = container.newBackgroundContext()

        context1.transactionAuthor = "App1"
        context2.transactionAuthor = "App2"

        // App1 creates a kit.
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

        // App2 creates a kit.
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

        // App3 writes data.
        let context3 = container.newBackgroundContext()
        context3.transactionAuthor = "App3"

        TestModelBuilder.createPerson(name: "Jack", age: 55, in: context3)
        try context3.save()

        // App1 and App2 both sync the changes.
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

        // Ensure App1 and App2 each have the data.
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
