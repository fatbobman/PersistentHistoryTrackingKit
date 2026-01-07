//
//  HookRegistryActorTests.swift
//  PersistentHistoryTrackingKitTests
//
//  Created by Claude on 2025-01-06
//

import CoreData
import Testing
@testable import PersistentHistoryTrackingKit

@Suite("HookRegistryActor Tests", .serialized)
struct HookRegistryActorTests {

    @Test("Register and trigger hook")
    func registerAndTriggerHook() async throws {
        let registry = HookRegistryActor()

        actor Tracker {
            var triggered = false
            func setTriggered() { triggered = true }
            func isTriggered() -> Bool { triggered }
        }

        let tracker = Tracker()

        let callback: HookCallback = { context in
            await tracker.setTriggered()
            #expect(context.entityName == "Person")
            #expect(context.operation == .insert)
        }

        // Register the hook.
        await registry.registerObserver(entityName: "Person", operation: .insert, callback: callback)

        // Create a test context.
        let context = HookContext(
            entityName: "Person",
            operation: .insert,
            objectID: NSManagedObjectID(),
            objectIDURL: URL(string: "x-coredata://test")!,
            tombstone: nil,
            timestamp: Date(),
            author: "TestAuthor"
        )

        // Trigger the hook.
        await registry.triggerObserver(context: context)

        #expect(await tracker.isTriggered() == true)
    }

    @Test("Remove hook")
    func removeHook() async throws {
        let registry = HookRegistryActor()

        actor Tracker {
            var triggered = false
            func setTriggered() { triggered = true }
            func isTriggered() -> Bool { triggered }
        }

        let tracker = Tracker()

        let callback: HookCallback = { _ in
            await tracker.setTriggered()
        }

        // Register the hook.
        await registry.registerObserver(entityName: "Person", operation: .insert, callback: callback)

        // Remove the hook.
        await registry.removeObserver(entityName: "Person", operation: .insert)

        // Create a test context.
        let context = HookContext(
            entityName: "Person",
            operation: .insert,
            objectID: NSManagedObjectID(),
            objectIDURL: URL(string: "x-coredata://test")!,
            tombstone: nil,
            timestamp: Date(),
            author: "TestAuthor"
        )

        // Triggering should now be a no-op.
        await registry.triggerObserver(context: context)

        #expect(await tracker.isTriggered() == false)
    }

    @Test("Multiple hooks firing concurrently")
    func multipleHooksConcurrent() async throws {
        let registry = HookRegistryActor()

        actor Counter {
            var count = 0
            func increment() { count += 1 }
            func get() -> Int { count }
        }

        let counter = Counter()

        // Register hooks for multiple operations.
        for operation in [HookOperation.insert, .update, .delete] {
            let callback: HookCallback = { _ in
                await counter.increment()
            }
            await registry.registerObserver(entityName: "Person", operation: operation, callback: callback)
        }

        // Trigger each hook concurrently.
        await withTaskGroup(of: Void.self) { group in
            for operation in [HookOperation.insert, .update, .delete] {
                group.addTask {
                    let context = HookContext(
                        entityName: "Person",
                        operation: operation,
                        objectID: NSManagedObjectID(),
                        objectIDURL: URL(string: "x-coredata://test")!,
                        tombstone: nil,
                        timestamp: Date(),
                        author: "TestAuthor"
                    )
                    await registry.triggerObserver(context: context)
                }
            }
        }

        let finalCount = await counter.get()
        #expect(finalCount == 3)
    }

    @Test("Hooks for different entities do not interfere")
    func differentEntityHooks() async throws {
        let registry = HookRegistryActor()

        actor Tracker {
            var personTriggered = false
            var itemTriggered = false
            func setPersonTriggered() { personTriggered = true }
            func setItemTriggered() { itemTriggered = true }
            func getState() -> (person: Bool, item: Bool) { (personTriggered, itemTriggered) }
        }

        let tracker = Tracker()

        let personCallback: HookCallback = { _ in
            await tracker.setPersonTriggered()
        }
        let itemCallback: HookCallback = { _ in
            await tracker.setItemTriggered()
        }

        // Register hooks for different entities.
        _ = await registry.registerObserver(entityName: "Person", operation: .insert, callback: personCallback)
        _ = await registry.registerObserver(entityName: "Item", operation: .insert, callback: itemCallback)

        // Trigger the Person hook.
        let personContext = HookContext(
            entityName: "Person",
            operation: .insert,
            objectID: NSManagedObjectID(),
            objectIDURL: URL(string: "x-coredata://test")!,
            tombstone: nil,
            timestamp: Date(),
            author: "TestAuthor"
        )
        await registry.triggerObserver(context: personContext)

        let state = await tracker.getState()
        #expect(state.person == true)
        #expect(state.item == false)
    }

    // MARK: - UUID-based Hook Management Tests

    @Test("Register hook returns UUID")
    func registerHookReturnsUUID() async throws {
        let registry = HookRegistryActor()

        let callback: HookCallback = { _ in }

        let hookId = await registry.registerObserver(
            entityName: "Person",
            operation: .insert,
            callback: callback
        )

        #expect(hookId != UUID()) // Should be a valid UUID
    }

    @Test("Remove hook by UUID")
    func removeHookByUUID() async throws {
        let registry = HookRegistryActor()

        actor Tracker {
            var triggered = false
            func setTriggered() { triggered = true }
            func isTriggered() -> Bool { triggered }
        }

        let tracker = Tracker()

        let callback: HookCallback = { _ in
            await tracker.setTriggered()
        }

        // Register and get UUID
        let hookId = await registry.registerObserver(
            entityName: "Person",
            operation: .insert,
            callback: callback
        )

        // Remove by UUID
        let removed = await registry.removeObserver(id: hookId)
        #expect(removed == true)

        // Trigger should not execute
        let context = HookContext(
            entityName: "Person",
            operation: .insert,
            objectID: NSManagedObjectID(),
            objectIDURL: URL(string: "x-coredata://test")!,
            tombstone: nil,
            timestamp: Date(),
            author: "TestAuthor"
        )
        await registry.triggerObserver(context: context)

        #expect(await tracker.isTriggered() == false)
    }

    @Test("Remove nonexistent UUID returns false")
    func removeNonexistentUUID() async throws {
        let registry = HookRegistryActor()

        let fakeId = UUID()
        let removed = await registry.removeObserver(id: fakeId)

        #expect(removed == false)
    }

    @Test("Remove specific hook from multiple hooks")
    func removeSpecificHookFromMultiple() async throws {
        let registry = HookRegistryActor()

        actor Counter {
            var count = 0
            func increment() { count += 1 }
            func get() -> Int { count }
        }

        let counter = Counter()

        // Register 3 hooks for the same entity + operation
        let hookId1 = await registry.registerObserver(
            entityName: "Person",
            operation: .insert
        ) { _ in
            await counter.increment()
        }

        let hookId2 = await registry.registerObserver(
            entityName: "Person",
            operation: .insert
        ) { _ in
            await counter.increment()
        }

        let hookId3 = await registry.registerObserver(
            entityName: "Person",
            operation: .insert
        ) { _ in
            await counter.increment()
        }

        // Remove only the middle hook
        let removed = await registry.removeObserver(id: hookId2)
        #expect(removed == true)

        // Trigger - should execute 2 hooks (1 and 3)
        let context = HookContext(
            entityName: "Person",
            operation: .insert,
            objectID: NSManagedObjectID(),
            objectIDURL: URL(string: "x-coredata://test")!,
            tombstone: nil,
            timestamp: Date(),
            author: "TestAuthor"
        )
        await registry.triggerObserver(context: context)

        let finalCount = await counter.get()
        #expect(finalCount == 2)

        // Verify we can still remove the remaining hooks
        #expect(await registry.removeObserver(id: hookId1) == true)
        #expect(await registry.removeObserver(id: hookId3) == true)

        // Removing already-removed hook returns false
        #expect(await registry.removeObserver(id: hookId2) == false)
    }

    @Test("Remove all hooks for entity+operation")
    func removeAllHooksForEntityOperation() async throws {
        let registry = HookRegistryActor()

        actor Counter {
            var count = 0
            func increment() { count += 1 }
            func get() -> Int { count }
        }

        let counter = Counter()

        // Register 3 hooks for Person.insert
        _ = await registry.registerObserver(
            entityName: "Person",
            operation: .insert
        ) { _ in await counter.increment() }

        _ = await registry.registerObserver(
            entityName: "Person",
            operation: .insert
        ) { _ in await counter.increment() }

        _ = await registry.registerObserver(
            entityName: "Person",
            operation: .insert
        ) { _ in await counter.increment() }

        // Register 1 hook for Person.update (should not be affected)
        _ = await registry.registerObserver(
            entityName: "Person",
            operation: .update
        ) { _ in await counter.increment() }

        // Remove all Person.insert hooks
        await registry.removeObserver(entityName: "Person", operation: .insert)

        // Trigger Person.insert - should not execute any hooks
        let insertContext = HookContext(
            entityName: "Person",
            operation: .insert,
            objectID: NSManagedObjectID(),
            objectIDURL: URL(string: "x-coredata://test")!,
            tombstone: nil,
            timestamp: Date(),
            author: "TestAuthor"
        )
        await registry.triggerObserver(context: insertContext)

        #expect(await counter.get() == 0)

        // Trigger Person.update - should still execute
        let updateContext = HookContext(
            entityName: "Person",
            operation: .update,
            objectID: NSManagedObjectID(),
            objectIDURL: URL(string: "x-coredata://test")!,
            tombstone: nil,
            timestamp: Date(),
            author: "TestAuthor"
        )
        await registry.triggerObserver(context: updateContext)

        #expect(await counter.get() == 1)
    }

    @Test("Multiple hooks execute in registration order")
    func multipleHooksExecutionOrder() async throws {
        let registry = HookRegistryActor()

        actor OrderTracker {
            var order: [Int] = []
            func append(_ value: Int) { order.append(value) }
            func get() -> [Int] { order }
        }

        let tracker = OrderTracker()

        // Register 3 hooks in specific order
        _ = await registry.registerObserver(
            entityName: "Person",
            operation: .insert
        ) { _ in
            await tracker.append(1)
        }

        _ = await registry.registerObserver(
            entityName: "Person",
            operation: .insert
        ) { _ in
            await tracker.append(2)
        }

        _ = await registry.registerObserver(
            entityName: "Person",
            operation: .insert
        ) { _ in
            await tracker.append(3)
        }

        // Trigger
        let context = HookContext(
            entityName: "Person",
            operation: .insert,
            objectID: NSManagedObjectID(),
            objectIDURL: URL(string: "x-coredata://test")!,
            tombstone: nil,
            timestamp: Date(),
            author: "TestAuthor"
        )
        await registry.triggerObserver(context: context)

        let executionOrder = await tracker.get()
        #expect(executionOrder == [1, 2, 3])
    }

    @Test("Remove all observers clears all hooks and UUIDs")
    func removeAllObserversClearsEverything() async throws {
        let registry = HookRegistryActor()

        actor Counter {
            var count = 0
            func increment() { count += 1 }
            func get() -> Int { count }
        }

        let counter = Counter()

        // Register hooks for multiple entities and operations
        let id1 = await registry.registerObserver(
            entityName: "Person",
            operation: .insert
        ) { _ in await counter.increment() }

        let id2 = await registry.registerObserver(
            entityName: "Person",
            operation: .update
        ) { _ in await counter.increment() }

        let id3 = await registry.registerObserver(
            entityName: "Item",
            operation: .insert
        ) { _ in await counter.increment() }

        // Remove all
        await registry.removeAllObservers()

        // Trigger all - none should execute
        for (entity, operation) in [("Person", HookOperation.insert), ("Person", .update), ("Item", .insert)] {
            let context = HookContext(
                entityName: entity,
                operation: operation,
                objectID: NSManagedObjectID(),
                objectIDURL: URL(string: "x-coredata://test")!,
                tombstone: nil,
                timestamp: Date(),
                author: "TestAuthor"
            )
            await registry.triggerObserver(context: context)
        }

        #expect(await counter.get() == 0)

        // Verify UUIDs are also cleaned up - removing should return false
        #expect(await registry.removeObserver(id: id1) == false)
        #expect(await registry.removeObserver(id: id2) == false)
        #expect(await registry.removeObserver(id: id3) == false)
    }
}
