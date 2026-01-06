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
    @Test("删除对象时 Observer Hook 收到墓碑数据")
    func tombstoneInObserverHook() async throws {
        let container = TestModelBuilder.createContainer(
            author: "App1",
            testName: "tombstoneInObserverHook")
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

        // 用于收集墓碑数据
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

        // 注册删除 Hook
        await hookRegistry.registerObserver(entityName: "Person", operation: .delete) { context in
            await collector.add(context.tombstone)
        }

        // 创建数据
        let bgContext = container.newBackgroundContext()
        bgContext.transactionAuthor = "App1"

        var personObjectID: NSManagedObjectID?

        try await bgContext.perform {
            let person = TestModelBuilder.createPerson(name: "TombstoneTest", age: 99, in: bgContext)
            try bgContext.save()
            personObjectID = person.objectID
        }

        // 删除数据
        try await bgContext.perform {
            if let objectID = personObjectID,
               let person = try? bgContext.existingObject(with: objectID)
            {
                bgContext.delete(person)
                try bgContext.save()
            }
        }

        // 处理事务
        let context2 = container.newBackgroundContext()
        _ = try await processor.processNewTransactions(
            from: ["App1"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "App2")

        // 验证墓碑数据
        let tombstones = await collector.getTombstones()
        let deletedNames = await collector.getDeletedNames()

        #expect(tombstones.count >= 1)
        #expect(deletedNames.contains("TombstoneTest"))

        // 验证墓碑包含 name 属性（因为我们设置了 preservesValueInHistoryOnDeletion）
        if let tombstone = tombstones.first {
            #expect(tombstone.attributes["name"] == "TombstoneTest")
            #expect(tombstone.deletedDate != nil)
        }
    }

    @Test("墓碑包含 preservesValueInHistoryOnDeletion 标记的属性")
    func tombstoneContainsPreservedAttributes() async throws {
        let container = TestModelBuilder.createContainer(
            author: "App1",
            testName: "tombstoneContainsPreservedAttributes")
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

        // 创建并删除数据
        let bgContext = container.newBackgroundContext()
        bgContext.transactionAuthor = "App1"

        let testUUID = UUID()

        try await bgContext.perform {
            let person = NSEntityDescription.insertNewObject(forEntityName: "Person", into: bgContext)
            person.setValue("PreservedName", forKey: "name")
            person.setValue(Int32(42), forKey: "age")
            person.setValue(testUUID, forKey: "id")
            try bgContext.save()

            // 立即删除
            bgContext.delete(person)
            try bgContext.save()
        }

        // 处理事务
        let context2 = container.newBackgroundContext()
        _ = try await processor.processNewTransactions(
            from: ["App1"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "App2")

        // 验证墓碑属性
        let attributes = await collector.get()

        // name 和 id 设置了 preservesValueInHistoryOnDeletion = true
        #expect(attributes["name"] == "PreservedName")
        #expect(attributes["id"] != nil) // UUID 应该被保留

        // age 没有设置 preservesValueInHistoryOnDeletion，可能不在墓碑中
        // 注意：这取决于 Core Data 的具体行为
    }

    @Test("插入和更新操作没有墓碑")
    func noTombstoneForInsertAndUpdate() async throws {
        let container = TestModelBuilder.createContainer(
            author: "App1",
            testName: "noTombstoneForInsertAndUpdate")
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

        // 创建数据（insert）
        let bgContext = container.newBackgroundContext()
        bgContext.transactionAuthor = "App1"

        var personObjectID: NSManagedObjectID?

        try await bgContext.perform {
            let person = TestModelBuilder.createPerson(name: "NoTombstone", age: 20, in: bgContext)
            try bgContext.save()
            personObjectID = person.objectID
        }

        // 更新数据（update）
        try await bgContext.perform {
            if let objectID = personObjectID,
               let person = try? bgContext.existingObject(with: objectID)
            {
                person.setValue("UpdatedName", forKey: "name")
                try bgContext.save()
            }
        }

        // 处理事务
        let context2 = container.newBackgroundContext()
        _ = try await processor.processNewTransactions(
            from: ["App1"],
            after: nil,
            mergeInto: [context2],
            currentAuthor: "App2")

        // 验证：插入和更新操作没有墓碑
        let insertTombstone = await tracker.getInsert()
        let updateTombstone = await tracker.getUpdate()

        #expect(insertTombstone == nil)
        #expect(updateTombstone == nil)
    }
}

