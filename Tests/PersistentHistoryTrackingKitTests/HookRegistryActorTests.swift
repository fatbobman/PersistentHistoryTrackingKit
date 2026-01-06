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

    @Test("注册和触发 Hook")
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

        // 注册 Hook
        await registry.registerObserver(entityName: "Person", operation: .insert, callback: callback)

        // 创建测试 Context
        let context = HookContext(
            entityName: "Person",
            operation: .insert,
            objectID: NSManagedObjectID(),
            objectIDURL: URL(string: "x-coredata://test")!,
            tombstone: nil,
            timestamp: Date(),
            author: "TestAuthor"
        )

        // 触发 Hook
        await registry.triggerObserver(context: context)

        #expect(await tracker.isTriggered() == true)
    }

    @Test("移除 Hook")
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

        // 注册 Hook
        await registry.registerObserver(entityName: "Person", operation: .insert, callback: callback)

        // 移除 Hook
        await registry.removeObserver(entityName: "Person", operation: .insert)

        // 创建测试 Context
        let context = HookContext(
            entityName: "Person",
            operation: .insert,
            objectID: NSManagedObjectID(),
            objectIDURL: URL(string: "x-coredata://test")!,
            tombstone: nil,
            timestamp: Date(),
            author: "TestAuthor"
        )

        // 触发 Hook（应该不会触发）
        await registry.triggerObserver(context: context)

        #expect(await tracker.isTriggered() == false)
    }

    @Test("多个 Hook 并发触发")
    func multipleHooksConcurrent() async throws {
        let registry = HookRegistryActor()

        actor Counter {
            var count = 0
            func increment() { count += 1 }
            func get() -> Int { count }
        }

        let counter = Counter()

        // 注册多个 Hook
        for operation in [HookOperation.insert, .update, .delete] {
            let callback: HookCallback = { _ in
                await counter.increment()
            }
            await registry.registerObserver(entityName: "Person", operation: operation, callback: callback)
        }

        // 并发触发多个 Hook
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

    @Test("不同 Entity 的 Hook 互不干扰")
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

        // 注册不同 Entity 的 Hook
        await registry.registerObserver(entityName: "Person", operation: .insert, callback: personCallback)
        await registry.registerObserver(entityName: "Item", operation: .insert, callback: itemCallback)

        // 触发 Person Hook
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
