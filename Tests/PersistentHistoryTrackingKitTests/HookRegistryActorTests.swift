//
//  HookRegistryActorTests.swift
//  PersistentHistoryTrackingKitTests
//
//  Created by Claude on 2025-01-06
//

import CoreData
import Testing

@testable import PersistentHistoryTrackingKit

@Suite("HookRegistryActor Tests")
struct HookRegistryActorTests {
  @Test("Register and trigger hook")
  func registerAndTriggerHook() async throws {
    let harness = makeHarness(testName: "registerAndTriggerHook")
    let recorder = HookContextRecorder()

    await harness.registry.registerObserver(
      entityName: "Person",
      operation: .insert
    ) { contexts in
      await recorder.record(contexts)
    }

    let objectIDURL = try await harness.createPersonAndProcess(name: "Alice")

    let receivedContexts = await recorder.flattened()
    #expect(receivedContexts.count == 1)
    #expect(receivedContexts.first?.entityName == "Person")
    #expect(receivedContexts.first?.operation == .insert)
    #expect(receivedContexts.first?.author == "App1")
    #expect(receivedContexts.first?.objectIDURL == objectIDURL)
  }

  @Test("Remove hook")
  func removeHook() async throws {
    let harness = makeHarness(testName: "removeHook")
    let tracker = BoolTracker()

    await harness.registry.registerObserver(
      entityName: "Person",
      operation: .insert
    ) { _ in
      await tracker.mark()
    }

    await harness.registry.removeObserver(entityName: "Person", operation: .insert)
    _ = try await harness.createPersonAndProcess(name: "Alice")

    #expect(await tracker.value() == false)
  }

  @Test("Hooks for different entities do not interfere")
  func differentEntityHooks() async throws {
    let harness = makeHarness(testName: "differentEntityHooks")
    let tracker = EntityTriggerTracker()

    await harness.registry.registerObserver(
      entityName: "Person",
      operation: .insert
    ) { _ in
      await tracker.markPerson()
    }

    await harness.registry.registerObserver(
      entityName: "Item",
      operation: .insert
    ) { _ in
      await tracker.markItem()
    }

    _ = try await harness.createPersonAndProcess(name: "Alice")
    let stateAfterPerson = await tracker.state()
    #expect(stateAfterPerson.person == true)
    #expect(stateAfterPerson.item == false)

    let afterPersonInsert = try await makeIncrementalAfterDate()
    _ = try await harness.createItemAndProcess(title: "Notebook", after: afterPersonInsert)
    let finalState = await tracker.state()
    #expect(finalState.person == true)
    #expect(finalState.item == true)
  }

  @Test("Register hook returns UUID")
  func registerHookReturnsUUID() async throws {
    let harness = makeHarness(testName: "registerHookReturnsUUID")

    let hookId = await harness.registry.registerObserver(
      entityName: "Person",
      operation: .insert
    ) { _ in }

    #expect(hookId != UUID())
  }

  @Test("Remove hook by UUID")
  func removeHookByUUID() async throws {
    let harness = makeHarness(testName: "removeHookByUUID")
    let tracker = BoolTracker()

    let hookId = await harness.registry.registerObserver(
      entityName: "Person",
      operation: .insert
    ) { _ in
      await tracker.mark()
    }

    let removed = await harness.registry.removeObserver(id: hookId)
    #expect(removed == true)

    _ = try await harness.createPersonAndProcess(name: "Alice")
    #expect(await tracker.value() == false)
  }

  @Test("Remove nonexistent UUID returns false")
  func removeNonexistentUUID() async throws {
    let harness = makeHarness(testName: "removeNonexistentUUID")

    let removed = await harness.registry.removeObserver(id: UUID())

    #expect(removed == false)
  }

  @Test("Remove specific hook from multiple hooks")
  func removeSpecificHookFromMultiple() async throws {
    let harness = makeHarness(testName: "removeSpecificHookFromMultiple")
    let counter = Counter()

    let hookId1 = await harness.registry.registerObserver(
      entityName: "Person",
      operation: .insert
    ) { _ in
      await counter.increment()
    }

    let hookId2 = await harness.registry.registerObserver(
      entityName: "Person",
      operation: .insert
    ) { _ in
      await counter.increment()
    }

    let hookId3 = await harness.registry.registerObserver(
      entityName: "Person",
      operation: .insert
    ) { _ in
      await counter.increment()
    }

    #expect(await harness.registry.removeObserver(id: hookId2) == true)

    _ = try await harness.createPersonAndProcess(name: "Alice")

    #expect(await counter.value() == 2)
    #expect(await harness.registry.removeObserver(id: hookId1) == true)
    #expect(await harness.registry.removeObserver(id: hookId3) == true)
    #expect(await harness.registry.removeObserver(id: hookId2) == false)
  }

  @Test("Remove all hooks for entity and operation")
  func removeAllHooksForEntityOperation() async throws {
    let harness = makeHarness(testName: "removeAllHooksForEntityOperation")
    let counter = Counter()

    _ = await harness.registry.registerObserver(
      entityName: "Person",
      operation: .insert
    ) { _ in
      await counter.increment()
    }

    _ = await harness.registry.registerObserver(
      entityName: "Person",
      operation: .insert
    ) { _ in
      await counter.increment()
    }

    _ = await harness.registry.registerObserver(
      entityName: "Person",
      operation: .insert
    ) { _ in
      await counter.increment()
    }

    _ = await harness.registry.registerObserver(
      entityName: "Person",
      operation: .update
    ) { _ in
      await counter.increment()
    }

    await harness.registry.removeObserver(entityName: "Person", operation: .insert)

    _ = try await harness.createPersonAndProcess(name: "Alice")
    #expect(await counter.value() == 0)

    let afterInsert = try await makeIncrementalAfterDate()
    try await harness.updatePersonAndProcess(
      matchName: "Alice",
      newAge: 31,
      after: afterInsert)
    #expect(await counter.value() == 1)
  }

  @Test("Multiple hooks execute in registration order")
  func multipleHooksExecutionOrder() async throws {
    let harness = makeHarness(testName: "multipleHooksExecutionOrder")
    let tracker = OrderTracker()

    _ = await harness.registry.registerObserver(
      entityName: "Person",
      operation: .insert
    ) { _ in
      await tracker.append(1)
    }

    _ = await harness.registry.registerObserver(
      entityName: "Person",
      operation: .insert
    ) { _ in
      await tracker.append(2)
    }

    _ = await harness.registry.registerObserver(
      entityName: "Person",
      operation: .insert
    ) { _ in
      await tracker.append(3)
    }

    _ = try await harness.createPersonAndProcess(name: "Alice")

    #expect(await tracker.values() == [1, 2, 3])
  }

  @Test("Remove all observers clears all hooks and UUIDs")
  func removeAllObserversClearsEverything() async throws {
    let harness = makeHarness(testName: "removeAllObserversClearsEverything")
    let counter = Counter()

    let id1 = await harness.registry.registerObserver(
      entityName: "Person",
      operation: .insert
    ) { _ in
      await counter.increment()
    }

    let id2 = await harness.registry.registerObserver(
      entityName: "Person",
      operation: .update
    ) { _ in
      await counter.increment()
    }

    let id3 = await harness.registry.registerObserver(
      entityName: "Item",
      operation: .insert
    ) { _ in
      await counter.increment()
    }

    await harness.registry.removeAllObservers()

    _ = try await harness.createPersonAndProcess(name: "Alice")
    let afterInsert = try await makeIncrementalAfterDate()
    try await harness.updatePersonAndProcess(
      matchName: "Alice",
      newAge: 31,
      after: afterInsert)
    let afterUpdate = try await makeIncrementalAfterDate()
    _ = try await harness.createItemAndProcess(title: "Notebook", after: afterUpdate)

    #expect(await counter.value() == 0)
    #expect(await harness.registry.removeObserver(id: id1) == false)
    #expect(await harness.registry.removeObserver(id: id2) == false)
    #expect(await harness.registry.removeObserver(id: id3) == false)
  }
}

private extension HookRegistryActorTests {
  func makeHarness(testName: String) -> HookTestHarness {
    let container = TestModelBuilder.createContainer(
      author: "App1",
      testName: testName)
    let registry = HookRegistryActor()
    let timestampManager = TransactionTimestampManager(
      userDefaults: TestModelBuilder.createTestUserDefaults(),
      maximumDuration: 604_800)
    let processor = TransactionProcessorActor(
      container: container,
      hookRegistry: registry,
      cleanStrategy: .none,
      timestampManager: timestampManager)
    let writer = TestAppDataHandler(container: container, viewName: "Writer")

    return HookTestHarness(
      registry: registry,
      processor: processor,
      writer: writer)
  }
}

private struct HookTestHarness {
  let registry: HookRegistryActor
  let processor: TransactionProcessorActor
  let writer: TestAppDataHandler

  @discardableResult
  func createPersonAndProcess(
    name: String,
    age: Int32 = 30,
    author: String = "App1",
    after: Date? = nil
  ) async throws -> URL {
    let objectIDURL = try await writer.createPerson(name: name, age: age, author: author)
    _ = try await processor.processNewTransactions(
      from: ["App1", "App2"],
      after: after,
      currentAuthor: "App2")
    return objectIDURL
  }

  @discardableResult
  func createItemAndProcess(
    title: String,
    author: String = "App1",
    after: Date? = nil
  ) async throws -> URL {
    let objectIDURL = try await writer.createItem(title: title, author: author)
    _ = try await processor.processNewTransactions(
      from: ["App1", "App2"],
      after: after,
      currentAuthor: "App2")
    return objectIDURL
  }

  func updatePersonAndProcess(
    matchName: String,
    newAge: Int32,
    author: String = "App1",
    after: Date? = nil
  ) async throws {
    try await writer.updatePeople(
      [PersonUpdate(matchName: matchName, newAge: newAge)],
      author: author)
    _ = try await processor.processNewTransactions(
      from: ["App1", "App2"],
      after: after,
      currentAuthor: "App2")
  }
}

private actor HookContextRecorder {
  private var contexts: [HookContext] = []

  func record(_ contexts: [HookContext]) {
    self.contexts.append(contentsOf: contexts)
  }

  func flattened() -> [HookContext] {
    contexts
  }
}

private actor BoolTracker {
  private var marked = false

  func mark() {
    marked = true
  }

  func value() -> Bool {
    marked
  }
}

private actor Counter {
  private var count = 0

  func increment() {
    count += 1
  }

  func value() -> Int {
    count
  }
}

private actor OrderTracker {
  private var order: [Int] = []

  func append(_ value: Int) {
    order.append(value)
  }

  func values() -> [Int] {
    order
  }
}

private actor EntityTriggerTracker {
  private var person = false
  private var item = false

  func markPerson() {
    person = true
  }

  func markItem() {
    item = true
  }

  func state() -> (person: Bool, item: Bool) {
    (person, item)
  }
}

private func makeIncrementalAfterDate() async throws -> Date {
  let checkpoint = Date()
  try await Task.sleep(nanoseconds: 100_000_000)
  return checkpoint
}
