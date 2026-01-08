//
//  IntegrationTests.swift
//  PersistentHistoryTrackingKitTests
//
//  Created by Claude on 2025-01-06
//

import CoreData
@testable import PersistentHistoryTrackingKit
import Testing

@Suite("PersistentHistoryTrackingKit V2 Integration Tests", .serialized)
struct IntegrationTests {
    @Test("Two apps perform a simple sync")
    func simpleTwoAppSync() async throws {
        // Create a shared container (simulating a shared database).
        let container = TestModelBuilder.createContainer(author: "App1")

        // Create two contexts.
        let context1 = container.viewContext
        let context2 = container.newBackgroundContext()

        context1.transactionAuthor = "App1"
        context2.transactionAuthor = "App2"

        // App1 creates data
        TestModelBuilder.createPerson(name: "Alice", age: 30, in: context1)
        try context1.save()

        // Create the kit from App2's perspective.
        let userDefaults = TestModelBuilder.createTestUserDefaults()
        let uniqueString = "TestKit.SimpleTwoApp.\(UUID().uuidString)."

        let kit = PersistentHistoryTrackingKit(
            container: container,
            contexts: [context2],
            currentAuthor: "App2",
            allAuthors: ["App1", "App2"],
            userDefaults: userDefaults,
            uniqueString: uniqueString,
            logLevel: 0,
            autoStart: false)

        // Manually trigger a sync.
        try await kit.transactionProcessor.processNewTransactions(
            from: ["App1", "App2"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "App2",
            cleanBeforeTimestamp: nil)

        // Ensure context2 contains the data from App1.
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Person")
        let results = try context2.fetch(fetchRequest)

        #expect(results.count == 1)
        #expect(results.first?.value(forKey: "name") as? String == "Alice")
    }

    @Test("Hook trigger integration test")
    func hookTriggerIntegration() async throws {
        let container = TestModelBuilder.createContainer(author: "App1")
        let context1 = container.viewContext
        let context2 = container.newBackgroundContext()

        context1.transactionAuthor = "App1"
        context2.transactionAuthor = "App2"

        // Create Kit
        let userDefaults = TestModelBuilder.createTestUserDefaults()
        let uniqueString = "TestKit.HookTrigger.\(UUID().uuidString)."

        let kit = PersistentHistoryTrackingKit(
            container: container,
            contexts: [context2],
            currentAuthor: "App2",
            allAuthors: ["App1", "App2"],
            userDefaults: userDefaults,
            uniqueString: uniqueString,
            logLevel: 0,
            autoStart: false)

        // Register hooks.
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

        await kit.registerObserver(entityName: "Person", operation: .insert) { _ in
            await tracker.recordInsert()
        }

        await kit.registerObserver(entityName: "Person", operation: .update) { _ in
            await tracker.recordUpdate()
        }

        await kit.registerObserver(entityName: "Person", operation: .delete) { _ in
            await tracker.recordDelete()
        }

        // App1 creates data
        let person = TestModelBuilder.createPerson(name: "Alice", age: 30, in: context1)
        try context1.save()

        // Manually trigger sync.
        try await kit.transactionProcessor.processNewTransactions(
            from: ["App1", "App2"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "App2",
            cleanBeforeTimestamp: nil)

        // Verify the insert hook ran.
        let counts1 = await tracker.getCounts()
        #expect(counts1.insert >= 1)

        // App1 updates the data.
        person.setValue(31, forKey: "age")
        try context1.save()

        // Sync again.
        try await kit.transactionProcessor.processNewTransactions(
            from: ["App1", "App2"],
            after: Date(timeIntervalSinceNow: -10),
            mergeInto: [context2],
            currentAuthor: "App2",
            cleanBeforeTimestamp: nil)

        // Verify the update hook ran.
        let counts2 = await tracker.getCounts()
        #expect(counts2.update >= 1)

        // App1 deletes the data.
        context1.delete(person)
        try context1.save()

        // Sync again.
        try await kit.transactionProcessor.processNewTransactions(
            from: ["App1", "App2"],
            after: Date(timeIntervalSinceNow: -10),
            mergeInto: [context2],
            currentAuthor: "App2",
            cleanBeforeTimestamp: nil)

        // Verify the delete hook ran.
        let counts3 = await tracker.getCounts()
        #expect(counts3.delete >= 1)
    }

    @Test("Manual cleaner integration test")
    func manualCleanerIntegration() async throws {
        let container = TestModelBuilder.createContainer(author: "App1")
        let context = container.viewContext

        // Seed some data.
        TestModelBuilder.createPerson(name: "Alice", age: 30, in: context)
        try context.save()

        // Create Kit
        let userDefaults = TestModelBuilder.createTestUserDefaults()
        let uniqueString = "TestKit.ManualCleaner.\(UUID().uuidString)."

        // Persist the timestamp.
        userDefaults.set(Date(), forKey: uniqueString + "App1")

        let kit = PersistentHistoryTrackingKit(
            container: container,
            contexts: [context],
            currentAuthor: "App1",
            allAuthors: ["App1"],
            userDefaults: userDefaults,
            uniqueString: uniqueString,
            logLevel: 0,
            autoStart: false)

        // Build the cleaner.
        let cleaner = kit.cleanerBuilder()

        // Run cleanup.
        await cleaner.clean()

        // Data should still exist.
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Person")
        let results = try context.fetch(fetchRequest)
        #expect(results.count == 1)
    }

    @Test("Batch operation sync")
    func batchOperationSync() async throws {
        let container = TestModelBuilder.createContainer(author: "App1")
        let context1 = container.viewContext
        let context2 = container.newBackgroundContext()

        context1.transactionAuthor = "App1"
        context2.transactionAuthor = "App2"

        // App1 creates a batch of data.
        for i in 0 ..< 10 {
            TestModelBuilder.createPerson(name: "Person\(i)", age: Int32(20 + i), in: context1)
        }
        try context1.save()

        // Create the kit (App2 view).
        let userDefaults = TestModelBuilder.createTestUserDefaults()
        let uniqueString = "TestKit.BatchOperation.\(UUID().uuidString)."

        let kit = PersistentHistoryTrackingKit(
            container: container,
            contexts: [context2],
            currentAuthor: "App2",
            allAuthors: ["App1", "App2"],
            userDefaults: userDefaults,
            uniqueString: uniqueString,
            logLevel: 0,
            autoStart: false)

        // Manually trigger sync.
        try await kit.transactionProcessor.processNewTransactions(
            from: ["App1", "App2"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "App2",
            cleanBeforeTimestamp: nil)

        // Ensure all data synchronized.
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Person")
        let results = try context2.fetch(fetchRequest)
        #expect(results.count == 10)
    }

    @Test("Multi-context sync")
    func multiContextSync() async throws {
        let container = TestModelBuilder.createContainer(author: "App1")
        let context1 = container.viewContext
        let context2 = container.newBackgroundContext()
        let context3 = container.newBackgroundContext()

        context1.transactionAuthor = "App1"
        context2.transactionAuthor = "App2"
        context3.transactionAuthor = "App2"

        // App1 creates data
        TestModelBuilder.createPerson(name: "Alice", age: 30, in: context1)
        try context1.save()

        // Create the kit (App2 view) and merge into both contexts.
        let userDefaults = TestModelBuilder.createTestUserDefaults()
        let uniqueString = "TestKit.MultiContext.\(UUID().uuidString)."

        let kit = PersistentHistoryTrackingKit(
            container: container,
            contexts: [context2, context3],
            currentAuthor: "App2",
            allAuthors: ["App1", "App2"],
            userDefaults: userDefaults,
            uniqueString: uniqueString,
            logLevel: 0,
            autoStart: false)

        // Manually trigger sync.
        try await kit.transactionProcessor.processNewTransactions(
            from: ["App1", "App2"],
            after: nil,
            mergeInto: [context2, context3],
            currentAuthor: "App2",
            cleanBeforeTimestamp: nil)

        // Ensure both contexts contain the data.
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Person")
        let results2 = try context2.fetch(fetchRequest)
        let results3 = try context3.fetch(fetchRequest)

        #expect(results2.count == 1)
        #expect(results3.count == 1)
    }
}
