//
//  ObserverHookGroupingTests.swift
//  PersistentHistoryTrackingKitTests
//
//  Created by Claude on 2025-01-08
//

import CoreData
@testable import PersistentHistoryTrackingKit
import Testing

@Suite("Observer Hook Grouping Tests", .serialized)
struct ObserverHookGroupingTests {
    @Test("Multiple inserts in same transaction are grouped into single hook trigger")
    func multipleInsertsGrouped() async throws {
        let container = TestModelBuilder.createContainer(
            author: "App1",
            testName: "multipleInsertsGrouped")
        let hookRegistry = HookRegistryActor()
        let timestampManager = TransactionTimestampManager(
            userDefaults: TestModelBuilder.createTestUserDefaults(),
            maximumDuration: 604_800)
        let processor = TransactionProcessorActor(
            container: container,
            hookRegistry: hookRegistry,
            cleanStrategy: .none,
            timestampManager: timestampManager)

        // Track hook invocations
        actor HookTracker {
            var triggerCount = 0
            var receivedContexts: [[HookContext]] = []

            func recordTrigger(contexts: [HookContext]) {
                triggerCount += 1
                receivedContexts.append(contexts)
            }

            func getTriggerCount() -> Int { triggerCount }
            func getReceivedContexts() -> [[HookContext]] { receivedContexts }
        }

        let tracker = HookTracker()

        // Register Observer Hook for Person.insert
        await hookRegistry.registerObserver(entityName: "Person", operation: .insert) { contexts in
            await tracker.recordTrigger(contexts: contexts)
        }

        // Create multiple Person objects in a single transaction
        let bgContext = container.newBackgroundContext()
        bgContext.transactionAuthor = "App1"

        try await bgContext.perform {
            // Create 5 Person objects in the same transaction
            for i in 0 ..< 5 {
                TestModelBuilder.createPerson(name: "Person\(i)", age: Int32(20 + i), in: bgContext)
            }
            try bgContext.save() // Single save = single transaction
        }

        // Process the transactions
        let context2 = container.newBackgroundContext()
        _ = try await processor.processNewTransactions(
            from: ["App1"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "App2")

        // Verify hook was triggered only once
        let triggerCount = await tracker.getTriggerCount()
        #expect(triggerCount == 1, "Hook should be triggered exactly once for grouped changes")

        // Verify the contexts array contains all 5 Person objects
        let receivedContexts = await tracker.getReceivedContexts()
        #expect(receivedContexts.count == 1, "Should receive one array of contexts")
        #expect(receivedContexts.first?.count == 5, "Should receive 5 contexts in the array")

        // Verify all contexts are for Person.insert
        if let contexts = receivedContexts.first {
            for context in contexts {
                #expect(context.entityName == "Person")
                #expect(context.operation == .insert)
            }
        }
    }

    @Test("Multiple deletes in same transaction are grouped into single hook trigger")
    func multipleDeletesGrouped() async throws {
        let container = TestModelBuilder.createContainer(
            author: "App1",
            testName: "multipleDeletesGrouped")
        let hookRegistry = HookRegistryActor()
        let timestampManager = TransactionTimestampManager(
            userDefaults: TestModelBuilder.createTestUserDefaults(),
            maximumDuration: 604_800)
        let processor = TransactionProcessorActor(
            container: container,
            hookRegistry: hookRegistry,
            cleanStrategy: .none,
            timestampManager: timestampManager)

        // Track hook invocations
        actor HookTracker {
            var triggerCount = 0
            var receivedContexts: [[HookContext]] = []

            func recordTrigger(contexts: [HookContext]) {
                triggerCount += 1
                receivedContexts.append(contexts)
            }

            func getTriggerCount() -> Int { triggerCount }
            func getReceivedContexts() -> [[HookContext]] { receivedContexts }
        }

        let tracker = HookTracker()

        // Register Observer Hook for Person.delete
        await hookRegistry.registerObserver(entityName: "Person", operation: .delete) { contexts in
            await tracker.recordTrigger(contexts: contexts)
        }

        // Create and then delete multiple Person objects in a single transaction
        let bgContext = container.newBackgroundContext()
        bgContext.transactionAuthor = "App1"

        try await bgContext.perform {
            // Create 3 Person objects
            var personsToDelete: [NSManagedObject] = []
            for i in 0 ..< 3 {
                let person = TestModelBuilder.createPerson(
                    name: "ToDelete\(i)",
                    age: Int32(30 + i),
                    in: bgContext)
                personsToDelete.append(person)
            }
            try bgContext.save() // First save: creates the objects

            // Delete all 3 in a single transaction
            for person in personsToDelete {
                bgContext.delete(person)
            }
            try bgContext.save() // Second save: deletes all objects in one transaction
        }

        // Process the transactions
        let context2 = container.newBackgroundContext()
        _ = try await processor.processNewTransactions(
            from: ["App1"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "App2")

        // Verify hook was triggered only once for the delete transaction
        let triggerCount = await tracker.getTriggerCount()
        #expect(triggerCount == 1, "Hook should be triggered exactly once for grouped deletes")

        // Verify the contexts array contains all 3 deleted Person objects
        let receivedContexts = await tracker.getReceivedContexts()
        #expect(receivedContexts.count == 1, "Should receive one array of contexts")
        #expect(receivedContexts.first?.count == 3, "Should receive 3 contexts in the array")

        // Verify all contexts are for Person.delete and have tombstones
        if let contexts = receivedContexts.first {
            for context in contexts {
                #expect(context.entityName == "Person")
                #expect(context.operation == .delete)
                #expect(context.tombstone != nil, "Delete operations should have tombstone data")
            }
        }
    }

    @Test("Different entities in same transaction trigger separate hooks")
    func differentEntitiesTriggerSeparateHooks() async throws {
        let container = TestModelBuilder.createContainer(
            author: "App1",
            testName: "differentEntitiesTriggerSeparateHooks")
        let hookRegistry = HookRegistryActor()
        let timestampManager = TransactionTimestampManager(
            userDefaults: TestModelBuilder.createTestUserDefaults(),
            maximumDuration: 604_800)
        let processor = TransactionProcessorActor(
            container: container,
            hookRegistry: hookRegistry,
            cleanStrategy: .none,
            timestampManager: timestampManager)

        // Track hook invocations for each entity
        actor HookTracker {
            var personTriggerCount = 0
            var itemTriggerCount = 0
            var personContexts: [[HookContext]] = []
            var itemContexts: [[HookContext]] = []

            func recordPersonTrigger(contexts: [HookContext]) {
                personTriggerCount += 1
                personContexts.append(contexts)
            }

            func recordItemTrigger(contexts: [HookContext]) {
                itemTriggerCount += 1
                itemContexts.append(contexts)
            }

            func getPersonTriggerCount() -> Int { personTriggerCount }
            func getItemTriggerCount() -> Int { itemTriggerCount }
            func getPersonContexts() -> [[HookContext]] { personContexts }
            func getItemContexts() -> [[HookContext]] { itemContexts }
        }

        let tracker = HookTracker()

        // Register hooks for both entities
        await hookRegistry.registerObserver(entityName: "Person", operation: .insert) { contexts in
            await tracker.recordPersonTrigger(contexts: contexts)
        }

        await hookRegistry.registerObserver(entityName: "Item", operation: .insert) { contexts in
            await tracker.recordItemTrigger(contexts: contexts)
        }

        // Create multiple Person and Item objects in a single transaction
        let bgContext = container.newBackgroundContext()
        bgContext.transactionAuthor = "App1"

        try await bgContext.perform {
            // Create 3 Person objects
            for i in 0 ..< 3 {
                TestModelBuilder.createPerson(name: "Person\(i)", age: Int32(20 + i), in: bgContext)
            }

            // Create 2 Item objects
            for i in 0 ..< 2 {
                TestModelBuilder.createItem(title: "Item\(i)", in: bgContext)
            }

            try bgContext.save() // Single save = single transaction
        }

        // Process the transactions
        let context2 = container.newBackgroundContext()
        _ = try await processor.processNewTransactions(
            from: ["App1"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "App2")

        // Verify Person hook was triggered once with 3 contexts
        let personTriggerCount = await tracker.getPersonTriggerCount()
        #expect(personTriggerCount == 1, "Person hook should be triggered once")
        let personContexts = await tracker.getPersonContexts()
        #expect(personContexts.first?.count == 3, "Person hook should receive 3 contexts")

        // Verify Item hook was triggered once with 2 contexts
        let itemTriggerCount = await tracker.getItemTriggerCount()
        #expect(itemTriggerCount == 1, "Item hook should be triggered once")
        let itemContexts = await tracker.getItemContexts()
        #expect(itemContexts.first?.count == 2, "Item hook should receive 2 contexts")
    }

    @Test("Different operations in same transaction trigger separate hooks")
    func differentOperationsTriggerSeparateHooks() async throws {
        let container = TestModelBuilder.createContainer(
            author: "App1",
            testName: "differentOperationsTriggerSeparateHooks")
        let hookRegistry = HookRegistryActor()
        let timestampManager = TransactionTimestampManager(
            userDefaults: TestModelBuilder.createTestUserDefaults(),
            maximumDuration: 604_800)
        let processor = TransactionProcessorActor(
            container: container,
            hookRegistry: hookRegistry,
            cleanStrategy: .none,
            timestampManager: timestampManager)

        // Track hook invocations for each operation
        actor HookTracker {
            var insertTriggerCount = 0
            var updateTriggerCount = 0
            var insertContexts: [[HookContext]] = []
            var updateContexts: [[HookContext]] = []

            func recordInsertTrigger(contexts: [HookContext]) {
                insertTriggerCount += 1
                insertContexts.append(contexts)
            }

            func recordUpdateTrigger(contexts: [HookContext]) {
                updateTriggerCount += 1
                updateContexts.append(contexts)
            }

            func getInsertTriggerCount() -> Int { insertTriggerCount }
            func getUpdateTriggerCount() -> Int { updateTriggerCount }
            func getInsertContexts() -> [[HookContext]] { insertContexts }
            func getUpdateContexts() -> [[HookContext]] { updateContexts }
        }

        let tracker = HookTracker()

        // Register hooks for both operations
        await hookRegistry.registerObserver(entityName: "Person", operation: .insert) { contexts in
            await tracker.recordInsertTrigger(contexts: contexts)
        }

        await hookRegistry.registerObserver(entityName: "Person", operation: .update) { contexts in
            await tracker.recordUpdateTrigger(contexts: contexts)
        }

        // Create and update Person objects in a single transaction
        let bgContext = container.newBackgroundContext()

        // Seed existing data with a different author so it does not affect expectations.
        bgContext.transactionAuthor = "Seeder"
        try await bgContext.perform {
            TestModelBuilder.createPerson(name: "Seed1", age: 20, in: bgContext)
            TestModelBuilder.createPerson(name: "Seed2", age: 21, in: bgContext)
            try bgContext.save()
        }

        // Perform mixed operations in a single transaction for App1.
        bgContext.transactionAuthor = "App1"
        try await bgContext.perform {
            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Person")
            let existingPersons = try bgContext.fetch(fetchRequest)
            precondition(existingPersons.count >= 2, "Need at least two persons to update")

            existingPersons[0].setValue("UpdatedPerson1", forKey: "name")
            existingPersons[1].setValue("UpdatedPerson2", forKey: "name")

            TestModelBuilder.createPerson(name: "InsertedPerson1", age: 22, in: bgContext)
            TestModelBuilder.createPerson(name: "InsertedPerson2", age: 23, in: bgContext)

            try bgContext.save() // Single save combines updates and inserts
        }

        // Process the transactions
        let context2 = container.newBackgroundContext()
        _ = try await processor.processNewTransactions(
            from: ["App1"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "App2")

        // Verify insert hook was triggered once with 2 contexts
        let insertTriggerCount = await tracker.getInsertTriggerCount()
        #expect(insertTriggerCount == 1, "Insert hook should be triggered once")
        let insertContexts = await tracker.getInsertContexts()
        #expect(insertContexts.first?.count == 2, "Insert hook should receive 2 contexts")

        // Verify update hook was triggered once with 2 contexts
        let updateTriggerCount = await tracker.getUpdateTriggerCount()
        #expect(updateTriggerCount == 1, "Update hook should be triggered once")
        let updateContexts = await tracker.getUpdateContexts()
        #expect(updateContexts.first?.count == 2, "Update hook should receive 2 contexts")
    }

    @Test("Changes across multiple transactions trigger separate hooks")
    func multipleTransactionsTriggerSeparateHooks() async throws {
        let container = TestModelBuilder.createContainer(
            author: "App1",
            testName: "multipleTransactionsTriggerSeparateHooks")
        let hookRegistry = HookRegistryActor()
        let timestampManager = TransactionTimestampManager(
            userDefaults: TestModelBuilder.createTestUserDefaults(),
            maximumDuration: 604_800)
        let processor = TransactionProcessorActor(
            container: container,
            hookRegistry: hookRegistry,
            cleanStrategy: .none,
            timestampManager: timestampManager)

        // Track hook invocations
        actor HookTracker {
            var triggerCount = 0
            var receivedContexts: [[HookContext]] = []

            func recordTrigger(contexts: [HookContext]) {
                triggerCount += 1
                receivedContexts.append(contexts)
            }

            func getTriggerCount() -> Int { triggerCount }
            func getReceivedContexts() -> [[HookContext]] { receivedContexts }
        }

        let tracker = HookTracker()

        // Register Observer Hook for Person.insert
        await hookRegistry.registerObserver(entityName: "Person", operation: .insert) { contexts in
            await tracker.recordTrigger(contexts: contexts)
        }

        // Create Person objects in separate transactions
        let bgContext = container.newBackgroundContext()
        bgContext.transactionAuthor = "App1"

        try await bgContext.perform {
            // First transaction: create 2 Person objects
            TestModelBuilder.createPerson(name: "Person1", age: 20, in: bgContext)
            TestModelBuilder.createPerson(name: "Person2", age: 21, in: bgContext)
            try bgContext.save() // First transaction

            // Second transaction: create 3 Person objects
            TestModelBuilder.createPerson(name: "Person3", age: 22, in: bgContext)
            TestModelBuilder.createPerson(name: "Person4", age: 23, in: bgContext)
            TestModelBuilder.createPerson(name: "Person5", age: 24, in: bgContext)
            try bgContext.save() // Second transaction
        }

        // Process the transactions
        let context2 = container.newBackgroundContext()
        _ = try await processor.processNewTransactions(
            from: ["App1"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "App2")

        // Verify hook was triggered twice (once per transaction)
        let triggerCount = await tracker.getTriggerCount()
        #expect(triggerCount == 2, "Hook should be triggered once per transaction")

        // Verify first trigger has 2 contexts, second has 3 contexts
        let receivedContexts = await tracker.getReceivedContexts()
        #expect(receivedContexts.count == 2, "Should receive contexts from 2 transactions")
        #expect(receivedContexts[0].count == 2, "First transaction should have 2 contexts")
        #expect(receivedContexts[1].count == 3, "Second transaction should have 3 contexts")
    }

    @Test("Observer hook trigger order matches change order")
    func observerHookTriggerOrderMatchesChangeOrder() async throws {
        let container = TestModelBuilder.createContainer(
            author: "App1",
            testName: "observerHookTriggerOrderMatchesChangeOrder")
        let hookRegistry = HookRegistryActor()
        let timestampManager = TransactionTimestampManager(
            userDefaults: TestModelBuilder.createTestUserDefaults(),
            maximumDuration: 604_800)
        let processor = TransactionProcessorActor(
            container: container,
            hookRegistry: hookRegistry,
            cleanStrategy: .none,
            timestampManager: timestampManager)

        actor HookOrderTracker {
            var order: [String] = []

            func record(entityName: String, operation: HookOperation) {
                order.append("\(entityName).\(operation.rawValue)")
            }

            func getOrder() -> [String] { order }
        }

        let tracker = HookOrderTracker()

        await hookRegistry.registerObserver(entityName: "Person", operation: .insert) { contexts in
            guard let context = contexts.first else { return }
            await tracker.record(entityName: context.entityName, operation: context.operation)
        }

        await hookRegistry.registerObserver(entityName: "Person", operation: .delete) { contexts in
            guard let context = contexts.first else { return }
            await tracker.record(entityName: context.entityName, operation: context.operation)
        }

        await hookRegistry.registerObserver(entityName: "Item", operation: .insert) { contexts in
            guard let context = contexts.first else { return }
            await tracker.record(entityName: context.entityName, operation: context.operation)
        }

        let bgContext = container.newBackgroundContext()

        // Seed a person to delete using a different author.
        bgContext.transactionAuthor = "Seeder"
        try await bgContext.perform {
            TestModelBuilder.createPerson(name: "PersonToDelete", age: 40, in: bgContext)
            try bgContext.save()
        }

        // Create insert/delete/insert operations in a single App1 transaction.
        bgContext.transactionAuthor = "App1"
        try await bgContext.perform {
            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Person")
            guard let personToDelete = try bgContext.fetch(fetchRequest).first else {
                preconditionFailure("Missing person to delete")
            }

            TestModelBuilder.createPerson(name: "InsertedFirst", age: 25, in: bgContext)
            bgContext.delete(personToDelete)
            TestModelBuilder.createItem(title: "InsertedItem", in: bgContext)

            try bgContext.save()
        }

        let context2 = container.newBackgroundContext()
        _ = try await processor.processNewTransactions(
            from: ["App1"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "App2")

        func fetchExpectedOrder() async throws -> [String] {
            let historyContext = container.newBackgroundContext()
            return try await historyContext.perform {
                let request = NSPersistentHistoryChangeRequest.fetchHistory(
                    after: nil as NSPersistentHistoryToken?)
                let fetchRequest = NSPersistentHistoryTransaction.fetchRequest!
                fetchRequest.predicate = NSPredicate(format: "author == %@", "App1")
                request.fetchRequest = fetchRequest

                guard
                    let result = try historyContext.execute(request) as? NSPersistentHistoryResult,
                    var transactions = result.result as? [NSPersistentHistoryTransaction]
                else {
                    return []
                }

                transactions.sort { $0.timestamp < $1.timestamp }

                guard
                    let lastTransaction = transactions.last,
                    let changes = lastTransaction.changes
                else {
                    return []
                }

                var seenKeys = Set<String>()
                var orderedKeys: [String] = []

                for change in changes {
                    let entityName = change.changedObjectID.entity.name ?? "Unknown"
                    let operation: HookOperation = switch change.changeType {
                        case .insert:
                            .insert
                        case .update:
                            .update
                        case .delete:
                            .delete
                        @unknown default:
                            .update
                    }
                    let key = "\(entityName).\(operation.rawValue)"
                    if !seenKeys.contains(key) {
                        seenKeys.insert(key)
                        orderedKeys.append(key)
                    }
                }

                return orderedKeys
            }
        }

        let order = await tracker.getOrder()
        let expectedOrder = try await fetchExpectedOrder()
        #expect(order == expectedOrder, "Hook trigger order should match change discovery order")
    }
}
