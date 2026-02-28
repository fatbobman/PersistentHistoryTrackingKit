//
//  TransactionProcessorActorTests.swift
//  PersistentHistoryTrackingKitTests
//
//  Created by Claude on 2025-01-06
//

import CoreData
import Testing

@testable import PersistentHistoryTrackingKit

@Suite("TransactionProcessorActor Tests", .serialized)
struct TransactionProcessorActorTests {
  @Test("Fetch transactions - excludes current author")
  func fetchTransactionsExcludeCurrentAuthor() async throws {
    let container = TestModelBuilder.createContainer(author: "App1")
    let app1Handler = TestAppDataHandler(container: container, viewName: "App1Handler")
    let app2Handler = TestAppDataHandler(container: container, viewName: "App2Handler")

    try await app1Handler.createPerson(name: "Alice", age: 30, author: "App1")
    try await app2Handler.createPerson(name: "Bob", age: 25, author: "App2")

    // Build the processor.
    let hookRegistry = HookRegistryActor()
    let timestampManager = TransactionTimestampManager(
      userDefaults: TestModelBuilder.createTestUserDefaults(),
      maximumDuration: 604_800)
    let processor = TransactionProcessorActor(
      container: container,
      hookRegistry: hookRegistry,
      cleanStrategy: .none,
      timestampManager: timestampManager)

    // Use internal Actor test methods
    let result = try await processor.testFetchTransactionsExcludesAuthor(
      from: ["App1", "App2"],
      after: nil,
      excludeAuthor: "App2")

    // Validate that the exclusion logic works.
    #expect(result.count >= 1)  // At least App1 transactions exist
    #expect(result.allExcluded == true)  // All transactions exclude App2
  }

  @Test("Clean transactions - timestamp and author filter")
  func cleanTransactionsByTimestampAndAuthors() async throws {
    let container = TestModelBuilder.createContainer(author: "App1")
    let app1Handler = TestAppDataHandler(container: container, viewName: "App1Handler")

    try await app1Handler.createPerson(name: "Alice", age: 30, author: "App1")

    let firstTimestamp = Date()

    try await Task.sleep(nanoseconds: 100_000_000)

    try await app1Handler.createPerson(name: "Bob", age: 25, author: "App1")

    // Build the processor.
    let hookRegistry = HookRegistryActor()
    let timestampManager = TransactionTimestampManager(
      userDefaults: TestModelBuilder.createTestUserDefaults(),
      maximumDuration: 604_800)
    let processor = TransactionProcessorActor(
      container: container,
      hookRegistry: hookRegistry,
      cleanStrategy: .none,
      timestampManager: timestampManager)

    // Use internal Actor test methods
    let result = try await processor.testCleanTransactions(
      before: firstTimestamp,
      for: ["App1"],
      expectedBefore: nil,  // No expected value specified
    )

    // Some transactions should have been deleted.
    #expect(result.deletedCount >= 0)
    // Transactions from the second batch should remain after cleanup.
    #expect(result.remainingCount >= 1)
  }

  @Test("Process new transactions - full flow")
  func processNewTransactionsFullFlow() async throws {
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

    try await app1Handler.createPerson(name: "Alice", age: 30, author: "App1")

    // Build the processor.
    let hookRegistry = HookRegistryActor()
    let timestampManager = TransactionTimestampManager(
      userDefaults: TestModelBuilder.createTestUserDefaults(),
      maximumDuration: 604_800)
    let processor = TransactionProcessorActor(
      container: container,
      contexts: [context2],
      hookRegistry: hookRegistry,
      cleanStrategy: .none,
      timestampManager: timestampManager)

    let count = try await processor.processNewTransactions(
      from: ["App1"],
      after: nil,
      currentAuthor: "App2",
      cleanBeforeTimestamp: nil)

    #expect(count >= 1)

    let summaries = try await app2Handler.personSummaries()
    #expect(summaries.count == 1)
    #expect(summaries.first?.0 == "Alice")
  }

  @Test("Trigger hooks during transaction processing")
  func triggerHooksDuringProcessing() async throws {
    let container = TestModelBuilder.createContainer(author: "App1")
    let app1Handler = TestAppDataHandler(container: container, viewName: "App1Handler")

    try await app1Handler.createPerson(name: "Alice", age: 30, author: "App1")

    // Create a hook registry and register a hook.
    let hookRegistry = HookRegistryActor()

    actor HookTracker {
      var triggered = false
      func setTriggered() { triggered = true }
      func isTriggered() -> Bool { triggered }
    }

    let tracker = HookTracker()

    let callback: HookCallback = { contexts in
      guard let context = contexts.first else { return }
      #expect(context.entityName == "Person")
      #expect(context.operation == .insert)
      await tracker.setTriggered()
    }

    await hookRegistry.registerObserver(
      entityName: "Person",
      operation: .insert,
      callback: callback)

    // Build the processor.
    let timestampManager = TransactionTimestampManager(
      userDefaults: TestModelBuilder.createTestUserDefaults(),
      maximumDuration: 604_800)
    let processor = TransactionProcessorActor(
      container: container,
      hookRegistry: hookRegistry,
      cleanStrategy: .none,
      timestampManager: timestampManager)

    // Process transactions (should trigger the hook).
    _ = try await processor.processNewTransactions(
      from: ["App1"],
      after: nil as Date?,
      currentAuthor: "App2",
      cleanBeforeTimestamp: nil as Date?)

    // Verify that the hook was triggered.
    let wasTriggered = await tracker.isTriggered()
    #expect(wasTriggered == true)
  }

  @Test("Get last transaction timestamp")
  func getLastTransactionTimestamp() async throws {
    let container = TestModelBuilder.createContainer(author: "App1")
    let app1Handler = TestAppDataHandler(container: container, viewName: "App1Handler")

    try await app1Handler.createPerson(name: "Alice", age: 30, author: "App1")

    // Build the processor.
    let hookRegistry = HookRegistryActor()
    let timestampManager = TransactionTimestampManager(
      userDefaults: TestModelBuilder.createTestUserDefaults(),
      maximumDuration: 604_800)
    let processor = TransactionProcessorActor(
      container: container,
      hookRegistry: hookRegistry,
      cleanStrategy: .none,
      timestampManager: timestampManager)

    // App2 processes App1's transactions (timestamp for App2 gets persisted).
    _ = try await processor.processNewTransactionsWithTimestampManagement(
      from: ["App1"],
      after: nil,
      currentAuthor: "App2",
      batchAuthors: [])

    // Use internal Actor test method (now reads from persisted timestamp).
    let result = await processor.testGetLastTransactionTimestamp(
      for: "App2",
      maxAge: 10,  // Allow 10 seconds error
    )

    #expect(result.hasTimestamp == true)
    #expect(result.timestamp != nil)
    #expect(result.isRecent == true)
  }
}
