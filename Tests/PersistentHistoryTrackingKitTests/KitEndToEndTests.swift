//
//  KitEndToEndTests.swift
//  PersistentHistoryTrackingKitTests
//
//  Created by Claude on 2025-01-06
//

import CoreData
import Testing

@testable import PersistentHistoryTrackingKit

/// V2 kit end-to-end scenarios that simulate real usage.
@Suite("Kit End-to-End Tests", .serialized)
struct KitEndToEndTests {
  @Test("Kit auto sync - start/stop")
  func kitAutoSyncStartStop() async throws {
    let container = TestModelBuilder.createContainer(author: "App1")
    let context1 = container.newBackgroundContext()
    let context2 = container.newBackgroundContext()
    let app1Handler = TestAppDataHandler(
      container: container,
      context: context1,
      viewName: "App1Handler")
    let app2Handler = TestAppDataHandler(
      container: container,
      context: context2,
      viewName: "App2Handler")

    // Create the kit from App2's perspective (manual start).
    let userDefaults = TestModelBuilder.createTestUserDefaults()
    let uniqueString = "TestKit.AutoSync.\(UUID().uuidString)."

    let kit = PersistentHistoryTrackingKit(
      container: container,
      contexts: [context2],
      currentAuthor: "App2",
      allAuthors: ["App1", "App2"],
      userDefaults: userDefaults,
      uniqueString: uniqueString,
      logLevel: 0,
      autoStart: false,  // manual control
    )

    try await app1Handler.createPerson(name: "Bob", age: 25, author: "App1")

    // Manual sync (exercise start/stop behavior).
    kit.start()
    try await Task.sleep(nanoseconds: 100_000_000)  // Wait for the task to start.
    kit.stop()

    let count = try await app2Handler.personCount()
    #expect(count >= 1)
  }

  @Test("Kit manual cleaner via cleanerBuilder")
  func kitManualCleaner() async throws {
    let container = TestModelBuilder.createContainer(author: "App1")
    let context1 = container.newBackgroundContext()
    let context2 = container.newBackgroundContext()
    let app1Handler = TestAppDataHandler(
      container: container,
      context: context1,
      viewName: "App1Handler")
    let app2Handler = TestAppDataHandler(
      container: container,
      context: context2,
      viewName: "App2Handler")

    let userDefaults = TestModelBuilder.createTestUserDefaults()
    let uniqueString = "TestKit.ManualClean.\(UUID().uuidString)."

    // Create the kit (without automatic cleanup).
    let kit = PersistentHistoryTrackingKit(
      container: container,
      contexts: [context2],
      currentAuthor: "App2",
      allAuthors: ["App1", "App2"],
      userDefaults: userDefaults,
      cleanStrategy: .none,
      uniqueString: uniqueString,
      logLevel: 0,
      autoStart: false)

    // Create manual cleaner
    let cleaner = kit.cleanerBuilder()

    try await app1Handler.createPerson(name: "David", age: 40, author: "App1")

    // Manual sync
    try await kit.transactionProcessor.processNewTransactions(
      from: ["App1", "App2"],
      after: nil,
      currentAuthor: "App2")

    let count = try await app2Handler.personCount()
    #expect(count == 1)

    // Manually run cleanup (just verify it succeeds).
    await cleaner.clean()
  }

  @Test("Kit multi-context synchronization")
  func kitMultiContextSync() async throws {
    let container = TestModelBuilder.createContainer(author: "App1")
    let context1 = container.newBackgroundContext()
    let context2 = container.newBackgroundContext()
    let context3 = container.newBackgroundContext()
    let app1Handler = TestAppDataHandler(
      container: container,
      context: context1,
      viewName: "App1Handler")
    let app2Handler = TestAppDataHandler(
      container: container,
      context: context2,
      viewName: "App2Handler")
    let app3Handler = TestAppDataHandler(
      container: container,
      context: context3,
      viewName: "App3Handler")

    let userDefaults = TestModelBuilder.createTestUserDefaults()
    let uniqueString = "TestKit.MultiContext.\(UUID().uuidString)."

    // Kit merges into both context2 and context3.
    let kit = PersistentHistoryTrackingKit(
      container: container,
      contexts: [context2, context3],
      currentAuthor: "App3",
      allAuthors: ["App1", "App2", "App3"],
      userDefaults: userDefaults,
      uniqueString: uniqueString,
      logLevel: 0,
      autoStart: false)

    try await app1Handler.createPerson(name: "Eve", age: 28, author: "App1")

    // Manual sync
    try await kit.transactionProcessor.processNewTransactions(
      from: ["App1", "App2", "App3"],
      after: nil,
      currentAuthor: "App3")

    #expect(try await app2Handler.personCount() == 1)
    #expect(try await app3Handler.personCount() == 1)
  }

  // TODO: Timestamp persistence tests depend on automated timestamp management.
  // See the TODO comment around PersistentHistoryTrackingKit.swift:248-268.
  //
  // @Test("Kit timestamp persistence")
  // func kitTimestampPersistence() async throws {
  //     // ... test code ...
  // }

  @Test("Kit registers an observer hook")
  func kitRegisterObserverHook() async throws {
    let container = TestModelBuilder.createContainer(author: "App1")
    let context1 = container.newBackgroundContext()
    let context2 = container.newBackgroundContext()
    let app1Handler = TestAppDataHandler(
      container: container,
      context: context1,
      viewName: "App1Handler")

    let userDefaults = TestModelBuilder.createTestUserDefaults()
    let uniqueString = "TestKit.ObserverHook.\(UUID().uuidString)."

    let kit = PersistentHistoryTrackingKit(
      container: container,
      contexts: [context2],
      currentAuthor: "App2",
      allAuthors: ["App1", "App2"],
      userDefaults: userDefaults,
      uniqueString: uniqueString,
      logLevel: 0,
      autoStart: false)

    // Track if the hook was triggered (using a Sendable actor).
    actor HookTracker {
      var triggered = false
      var entityName: String?
      var operation: HookOperation?

      func setTriggered(entityName: String, operation: HookOperation) {
        triggered = true
        self.entityName = entityName
        self.operation = operation
      }
    }

    let tracker = HookTracker()

    // Register Observer Hook
    await kit.registerObserver(entityName: "Person", operation: .insert) { contexts in
      guard let context = contexts.first else { return }
      await tracker.setTriggered(entityName: context.entityName, operation: context.operation)
    }

    try await app1Handler.createPerson(name: "Henry", age: 50, author: "App1")

    // Manual sync
    try await kit.transactionProcessor.processNewTransactions(
      from: ["App1", "App2"],
      after: nil,
      currentAuthor: "App2")

    // Wait for the hook to fire.
    try await Task.sleep(nanoseconds: 100_000_000)

    // Verify Hook was triggered
    let triggered = await tracker.triggered
    let entityName = await tracker.entityName
    let operation = await tracker.operation

    #expect(triggered == true)
    #expect(entityName == "Person")
    #expect(operation == .insert)
  }

  @Test("Kit registers a merge hook")
  func kitRegisterMergeHook() async throws {
    let container = TestModelBuilder.createContainer(author: "App1")
    let context1 = container.newBackgroundContext()
    let context2 = container.newBackgroundContext()
    let app1Handler = TestAppDataHandler(
      container: container,
      context: context1,
      viewName: "App1Handler")

    let userDefaults = TestModelBuilder.createTestUserDefaults()
    let uniqueString = "TestKit.MergeHook.\(UUID().uuidString)."

    let kit = PersistentHistoryTrackingKit(
      container: container,
      contexts: [context2],
      currentAuthor: "App2",
      allAuthors: ["App1", "App2"],
      userDefaults: userDefaults,
      uniqueString: uniqueString,
      logLevel: 0,
      autoStart: false)

    // Track if the merge hook was called (Sendable actor).
    actor MergeHookTracker {
      var called = false
      var transactionCount = 0
      var contextCount = 0

      func markCalled(transactionCount: Int, contextCount: Int) {
        called = true
        self.transactionCount = transactionCount
        self.contextCount = contextCount
      }
    }

    let tracker = MergeHookTracker()

    // Register the merge hook.
    await kit.registerMergeHook { input in
      await tracker.markCalled(
        transactionCount: input.transactions.count,
        contextCount: input.contexts.count)
      return .goOn
    }

    try await app1Handler.createPerson(name: "Iris", age: 27, author: "App1")

    // Manual sync
    try await kit.transactionProcessor.processNewTransactions(
      from: ["App1", "App2"],
      after: nil,
      currentAuthor: "App2")

    // Verify that the merge hook ran.
    let (called, transactionCount, contextCount) = await (
      tracker.called,
      tracker.transactionCount,
      tracker.contextCount
    )
    #expect(called == true)
    #expect(transactionCount >= 1)
    #expect(contextCount == 1)
  }

  @Test("Two apps use the kit (V2)")
  func twoAppsWithKit() async throws {
    let container = TestModelBuilder.createContainer(author: "App1")
    let context1 = container.newBackgroundContext()
    let context2 = container.newBackgroundContext()
    let app1Handler = TestAppDataHandler(
      container: container,
      context: context1,
      viewName: "App1Handler")
    let app2Handler = TestAppDataHandler(
      container: container,
      context: context2,
      viewName: "App2Handler")

    // App1 creates a kit.
    let userDefaults = TestModelBuilder.createTestUserDefaults()
    let uniqueString1 = "TestKit.TwoApp1.\(UUID().uuidString)."

    let kit1 = PersistentHistoryTrackingKit(
      container: container,
      contexts: [context1],
      currentAuthor: "App1",
      allAuthors: ["App1", "App2", "App3"],
      userDefaults: userDefaults,
      cleanStrategy: .none,
      uniqueString: uniqueString1,
      logLevel: 0,
      autoStart: false)

    // App2 creates a kit.
    let uniqueString2 = "TestKit.TwoApp2.\(UUID().uuidString)."

    let kit2 = PersistentHistoryTrackingKit(
      container: container,
      contexts: [context2],
      currentAuthor: "App2",
      allAuthors: ["App1", "App2", "App3"],
      userDefaults: userDefaults,
      cleanStrategy: .none,
      uniqueString: uniqueString2,
      logLevel: 0,
      autoStart: false)

    let context3 = container.newBackgroundContext()
    let app3Handler = TestAppDataHandler(
      container: container,
      context: context3,
      viewName: "App3Handler")

    try await app3Handler.createPerson(name: "Jack", age: 55, author: "App3")

    // App1 and App2 both sync the changes.
    try await kit1.transactionProcessor.processNewTransactions(
      from: ["App1", "App2", "App3"],
      after: nil as Date?,
      currentAuthor: "App1",
      cleanBeforeTimestamp: nil as Date?)

    try await kit2.transactionProcessor.processNewTransactions(
      from: ["App1", "App2", "App3"],
      after: nil as Date?,
      currentAuthor: "App2",
      cleanBeforeTimestamp: nil as Date?)

    let app1Names = try await app1Handler.personNames()
    let app2Names = try await app2Handler.personNames()
    #expect(app1Names == ["Jack"])
    #expect(app2Names == ["Jack"])
  }
}
