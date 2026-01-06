//
//  TombstoneTests.swift
//  PersistentHistoryTrackingKitTests
//
//  Created by Claude on 2025-01-06
//

import CoreData
import Testing

@testable import PersistentHistoryTrackingKit

@Suite("Tombstone Tests", .serialized)
struct TombstoneTests {
    @Test("Observer Hook sees tombstone when deleting objects")
    func tombstoneInObserverHook() async throws {
        let container = TestModelBuilder.createContainer(
            author: "App1",
            testName: "tombstoneInObserverHook")
        let hookRegistry = HookRegistryActor()
        let timestampManager = TransactionTimestampManager(
            userDefaults: TestModelBuilder.createTestUserDefaults(),
            maximumDuration: 604800
        )
        let processor = TransactionProcessorActor(
            container: container,
            hookRegistry: hookRegistry,
            cleanStrategy: .none,
            timestampManager: timestampManager)

        // For collecting tombstone data
        actor TombstoneCollector {
            var tombstones: [Tombstone] = []
            var deletedNames: [String] = []

            func add(_ tombstone: Tombstone?) {
                if let t = tombstone {
                    tombstones.append(t)
                    if let name = t.attributes["name"] {
                        deletedNames.append(name)
                    }
                }
            }

            func getTombstones() -> [Tombstone] { tombstones }
            func getDeletedNames() -> [String] { deletedNames }
        }

        let collector = TombstoneCollector()

        // Register delete Hook
        await hookRegistry.registerObserver(entityName: "Person", operation: .delete) { context in
            await collector.add(context.tombstone)
        }

        // Create, save and delete data (in the same actor-isolated closure)
        let bgContext = container.newBackgroundContext()
        bgContext.transactionAuthor = "App1"

        try await bgContext.perform {
            let person = TestModelBuilder.createPerson(name: "TombstoneTest", age: 99, in: bgContext)
            try bgContext.save()

            // Delete the newly created object
            bgContext.delete(person)
            try bgContext.save()
        }

        // Process the transactions.
        let context2 = container.newBackgroundContext()
        _ = try await processor.processNewTransactions(
            from: ["App1"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "App2")

        // Validate the tombstone data.
        let tombstones = await collector.getTombstones()
        let deletedNames = await collector.getDeletedNames()

        #expect(tombstones.count >= 1)
        #expect(deletedNames.contains("TombstoneTest"))

        // Ensure the tombstone includes the `name` attribute (because preservesValueInHistoryOnDeletion is enabled).
        if let tombstone = tombstones.first {
            #expect(tombstone.attributes["name"] == "TombstoneTest")
            #expect(tombstone.deletedDate != nil)
        }
    }

    @Test("Tombstone includes attributes flagged with preservesValueInHistoryOnDeletion")
    func tombstoneContainsPreservedAttributes() async throws {
        let container = TestModelBuilder.createContainer(
            author: "App1",
            testName: "tombstoneContainsPreservedAttributes")
        let hookRegistry = HookRegistryActor()
        let timestampManager = TransactionTimestampManager(
            userDefaults: TestModelBuilder.createTestUserDefaults(),
            maximumDuration: 604800
        )
        let processor = TransactionProcessorActor(
            container: container,
            hookRegistry: hookRegistry,
            cleanStrategy: .none,
            timestampManager: timestampManager)

        actor AttributeCollector {
            var attributes: [String: String] = [:]

            func set(_ attrs: [String: String]) {
                attributes = attrs
            }

            func get() -> [String: String] { attributes }
        }

        let collector = AttributeCollector()

        await hookRegistry.registerObserver(entityName: "Person", operation: .delete) { context in
            if let tombstone = context.tombstone {
                await collector.set(tombstone.attributes)
            }
        }

        // Create and immediately delete data.
        let bgContext = container.newBackgroundContext()
        bgContext.transactionAuthor = "App1"

        let testUUID = UUID()

        try await bgContext.perform {
            let person = NSEntityDescription.insertNewObject(forEntityName: "Person", into: bgContext)
            person.setValue("PreservedName", forKey: "name")
            person.setValue(Int32(42), forKey: "age")
            person.setValue(testUUID, forKey: "id")
            try bgContext.save()

            // Delete immediately.
            bgContext.delete(person)
            try bgContext.save()
        }

        // Process the transactions.
        let context2 = container.newBackgroundContext()
        _ = try await processor.processNewTransactions(
            from: ["App1"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "App2")

        // Validate the tombstone attributes.
        let attributes = await collector.get()

        // Both name and id have preservesValueInHistoryOnDeletion = true.
        #expect(attributes["name"] == "PreservedName")
        #expect(attributes["id"] != nil) // UUID should be preserved

        // The age attribute is not preserved, so Core Data may omit it.
    }

    @Test("Insert and update operations produce no tombstones")
    func noTombstoneForInsertAndUpdate() async throws {
        let container = TestModelBuilder.createContainer(
            author: "App1",
            testName: "noTombstoneForInsertAndUpdate")
        let hookRegistry = HookRegistryActor()
        let timestampManager = TransactionTimestampManager(
            userDefaults: TestModelBuilder.createTestUserDefaults(),
            maximumDuration: 604800
        )
        let processor = TransactionProcessorActor(
            container: container,
            hookRegistry: hookRegistry,
            cleanStrategy: .none,
            timestampManager: timestampManager)

        actor TombstoneTracker {
            var insertTombstone: Tombstone?
            var updateTombstone: Tombstone?

            func setInsert(_ t: Tombstone?) { insertTombstone = t }
            func setUpdate(_ t: Tombstone?) { updateTombstone = t }
            func getInsert() -> Tombstone? { insertTombstone }
            func getUpdate() -> Tombstone? { updateTombstone }
        }

        let tracker = TombstoneTracker()

        await hookRegistry.registerObserver(entityName: "Person", operation: .insert) { context in
            await tracker.setInsert(context.tombstone)
        }

        await hookRegistry.registerObserver(entityName: "Person", operation: .update) { context in
            await tracker.setUpdate(context.tombstone)
        }

        // Create and update data (in the same actor-isolated closure)
        let bgContext = container.newBackgroundContext()
        bgContext.transactionAuthor = "App1"

        try await bgContext.perform {
            // Create data (insert)
            let person = TestModelBuilder.createPerson(name: "NoTombstone", age: 20, in: bgContext)
            try bgContext.save()

            // Update data (update)
            person.setValue("UpdatedName", forKey: "name")
            try bgContext.save()
        }

        // Process the transactions.
        let context2 = container.newBackgroundContext()
        _ = try await processor.processNewTransactions(
            from: ["App1"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "App2")

        // Verify that insert and update operations do not have tombstones.
        let insertTombstone = await tracker.getInsert()
        let updateTombstone = await tracker.getUpdate()

        #expect(insertTombstone == nil)
        #expect(updateTombstone == nil)
    }
}
