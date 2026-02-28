//
//  TombstoneTests.swift
//  PersistentHistoryTrackingKitTests
//
//  Created by Claude on 2025-01-06
//

import CoreData
import Testing

@testable import PersistentHistoryTrackingKit

@Suite("Tombstone Tests")
struct TombstoneTests {
  @Test("Observer Hook sees tombstone when deleting objects")
  func tombstoneInObserverHook() async throws {
    let container = TestModelBuilder.createContainer(
      author: "App1",
      testName: "tombstoneInObserverHook")
    let hookRegistry = HookRegistryActor()
    let timestampManager = TransactionTimestampManager(
      userDefaults: TestModelBuilder.createTestUserDefaults(),
      maximumDuration: 604_800)
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
    await hookRegistry.registerObserver(entityName: "Person", operation: .delete) { contexts in
      for context in contexts {
        await collector.add(context.tombstone)
      }
    }

    let handler = TestAppDataHandler(container: container, viewName: "App1Handler")
    try await handler.createPerson(name: "TombstoneTest", age: 99, author: "App1")
    try await handler.deletePeople(named: ["TombstoneTest"], author: "App1")

    // Process the transactions.
    _ = try await processor.processNewTransactions(
      from: ["App1"],
      after: nil,
      currentAuthor: "App2")

    // Validate the tombstone data.
    let tombstones = await collector.getTombstones()
    let deletedNames = await collector.getDeletedNames()

    #expect(tombstones.count >= 1)
    #expect(deletedNames.contains("TombstoneTest"))

    // Ensure the tombstone includes the `name` attribute (because
    // preservesValueInHistoryOnDeletion is enabled).
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
      maximumDuration: 604_800)
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

    await hookRegistry.registerObserver(entityName: "Person", operation: .delete) { contexts in
      if let context = contexts.first, let tombstone = context.tombstone {
        await collector.set(tombstone.attributes)
      }
    }

    let testUUID = UUID()
    let handler = TestAppDataHandler(container: container, viewName: "App1Handler")
    try await handler.createPerson(
      name: "PreservedName",
      age: 42,
      author: "App1",
      id: testUUID)
    try await handler.deletePeople(named: ["PreservedName"], author: "App1")

    // Process the transactions.
    _ = try await processor.processNewTransactions(
      from: ["App1"],
      after: nil,
      currentAuthor: "App2")

    // Validate the tombstone attributes.
    let attributes = await collector.get()

    // Both name and id have preservesValueInHistoryOnDeletion = true.
    #expect(attributes["name"] == "PreservedName")
    #expect(attributes["id"] != nil)  // UUID should be preserved

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
      maximumDuration: 604_800)
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

    await hookRegistry.registerObserver(entityName: "Person", operation: .insert) { contexts in
      if let context = contexts.first {
        await tracker.setInsert(context.tombstone)
      }
    }

    await hookRegistry.registerObserver(entityName: "Person", operation: .update) { contexts in
      if let context = contexts.first {
        await tracker.setUpdate(context.tombstone)
      }
    }

    let handler = TestAppDataHandler(container: container, viewName: "App1Handler")
    try await handler.createPerson(name: "NoTombstone", age: 20, author: "App1")
    try await handler.updatePeople(
      [PersonUpdate(matchName: "NoTombstone", newName: "UpdatedName")],
      author: "App1")

    // Process the transactions.
    _ = try await processor.processNewTransactions(
      from: ["App1"],
      after: nil,
      currentAuthor: "App2")

    // Verify that insert and update operations do not have tombstones.
    let insertTombstone = await tracker.getInsert()
    let updateTombstone = await tracker.getUpdate()

    #expect(insertTombstone == nil)
    #expect(updateTombstone == nil)
  }
}
