//
//  ObserverHookGroupingTests.swift
//  PersistentHistoryTrackingKitTests
//
//  Created by Claude on 2025-01-08
//

import CoreData
import Testing

@testable import PersistentHistoryTrackingKit

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

    let handler = TestAppDataHandler(container: container, viewName: "App1Handler")
    try await handler.createPeople(count: 5, author: "App1")

    // Process the transactions
    _ = try await processor.processNewTransactions(
      from: ["App1"],
      after: nil,
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

    let handler = TestAppDataHandler(container: container, viewName: "App1Handler")
    try await handler.createPeople(
      [("ToDelete0", 30), ("ToDelete1", 31), ("ToDelete2", 32)],
      author: "App1")
    try await handler.deletePeople(
      named: ["ToDelete0", "ToDelete1", "ToDelete2"],
      author: "App1")

    // Process the transactions
    _ = try await processor.processNewTransactions(
      from: ["App1"],
      after: nil,
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

    let handler = TestAppDataHandler(container: container, viewName: "App1Handler")
    try await handler.createPeopleAndItems(
      people: [("Person0", 20), ("Person1", 21), ("Person2", 22)],
      items: ["Item0", "Item1"],
      author: "App1")

    // Process the transactions
    _ = try await processor.processNewTransactions(
      from: ["App1"],
      after: nil,
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

    let handler = TestAppDataHandler(container: container, viewName: "App1Handler")
    try await handler.createPeople(
      [("Seed1", 20), ("Seed2", 21)],
      author: "Seeder")
    try await handler.updatePeopleAndCreatePeople(
      updates: [
        PersonUpdate(matchName: "Seed1", newName: "UpdatedPerson1"),
        PersonUpdate(matchName: "Seed2", newName: "UpdatedPerson2"),
      ],
      newPeople: [("InsertedPerson1", 22), ("InsertedPerson2", 23)],
      author: "App1")

    // Process the transactions
    _ = try await processor.processNewTransactions(
      from: ["App1"],
      after: nil,
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

    let handler = TestAppDataHandler(container: container, viewName: "App1Handler")
    try await handler.createPeople([("Person1", 20), ("Person2", 21)], author: "App1")
    try await handler.createPeople(
      [("Person3", 22), ("Person4", 23), ("Person5", 24)],
      author: "App1")

    // Process the transactions
    _ = try await processor.processNewTransactions(
      from: ["App1"],
      after: nil,
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

    let handler = TestAppDataHandler(container: container, viewName: "App1Handler")
    let historyReader = TestAppDataHandler(container: container, viewName: "HistoryReader")

    try await handler.createPerson(name: "PersonToDelete", age: 40, author: "Seeder")
    try await handler.deletePeopleAndCreateEntities(
      deleteNames: ["PersonToDelete"],
      newPeople: [("InsertedFirst", 25)],
      newItems: ["InsertedItem"],
      author: "App1")

    _ = try await processor.processNewTransactions(
      from: ["App1"],
      after: nil,
      currentAuthor: "App2")

    let order = await tracker.getOrder()
    let expectedOrder = try await historyReader.historyOrderedKeys(for: "App1")
    #expect(order == expectedOrder, "Hook trigger order should match change discovery order")
  }
}
