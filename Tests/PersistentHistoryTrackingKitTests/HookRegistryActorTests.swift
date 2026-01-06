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
        await registry.registerObserver(entityName: "Person", operation: .insert, callback: personCallback)
        await registry.registerObserver(entityName: "Item", operation: .insert, callback: itemCallback)

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
}
