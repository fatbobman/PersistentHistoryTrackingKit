//
//  IntegrationTests.swift
//  PersistentHistoryTrackingKitTests
//
//  Created by Claude on 2025-01-06
//

import CoreData
import Testing

@testable import PersistentHistoryTrackingKit

@Suite("PersistentHistoryTrackingKit V2 Integration Tests", .serialized)
struct IntegrationTests {
  @Test("Two apps perform a simple sync")
  func simpleTwoAppSync() async throws {
    let container = TestModelBuilder.createContainer(author: "App1")
    let app1Context = container.newBackgroundContext()
    let app2Context = container.newBackgroundContext()
    let app1Handler = TestAppDataHandler(
      container: container,
      context: app1Context,
      viewName: "App1Handler")
    let app2Handler = TestAppDataHandler(
      container: container,
      context: app2Context,
      viewName: "App2Handler")

    try await app1Handler.createPerson(name: "Alice", age: 30, author: "App1")

    let userDefaults = TestModelBuilder.createTestUserDefaults()
    let uniqueString = "TestKit.SimpleTwoApp.\(UUID().uuidString)."
    let kit = PersistentHistoryTrackingKit(
      container: container,
      contexts: [app2Context],
      currentAuthor: "App2",
      allAuthors: ["App1", "App2"],
      userDefaults: userDefaults,
      uniqueString: uniqueString,
      logLevel: 0,
      autoStart: false)

    try await kit.transactionProcessor.processNewTransactions(
      from: ["App1", "App2"],
      after: nil,
      currentAuthor: "App2",
      cleanBeforeTimestamp: nil)

    let summaries = try await app2Handler.personSummaries()
    #expect(summaries.count == 1)
    #expect(summaries.first?.0 == "Alice")
  }

  @Test("Hook trigger integration test")
  func hookTriggerIntegration() async throws {
    let container = TestModelBuilder.createContainer(author: "App1")
    let app1Context = container.newBackgroundContext()
    let app2Context = container.newBackgroundContext()
    let app1Handler = TestAppDataHandler(
      container: container,
      context: app1Context,
      viewName: "App1Handler")

    let userDefaults = TestModelBuilder.createTestUserDefaults()
    let uniqueString = "TestKit.HookTrigger.\(UUID().uuidString)."
    let kit = PersistentHistoryTrackingKit(
      container: container,
      contexts: [app2Context],
      currentAuthor: "App2",
      allAuthors: ["App1", "App2"],
      userDefaults: userDefaults,
      uniqueString: uniqueString,
      logLevel: 0,
      autoStart: false)

    actor HookTracker {
      var insertCount = 0
      var updateCount = 0
      var deleteCount = 0

      func recordInsert() { insertCount += 1 }
      func recordUpdate() { updateCount += 1 }
      func recordDelete() { deleteCount += 1 }

      func getCounts() -> (insert: Int, update: Int, delete: Int) {
        (insertCount, updateCount, deleteCount)
      }
    }

    let tracker = HookTracker()

    await kit.registerObserver(entityName: "Person", operation: .insert) { _ in
      await tracker.recordInsert()
    }
    await kit.registerObserver(entityName: "Person", operation: .update) { _ in
      await tracker.recordUpdate()
    }
    await kit.registerObserver(entityName: "Person", operation: .delete) { _ in
      await tracker.recordDelete()
    }

    try await app1Handler.createPerson(name: "Alice", age: 30, author: "App1")
    try await kit.transactionProcessor.processNewTransactions(
      from: ["App1", "App2"],
      after: nil,
      currentAuthor: "App2",
      cleanBeforeTimestamp: nil)
    let counts1 = await tracker.getCounts()
    #expect(counts1.insert >= 1)

    try await app1Handler.updatePeople(
      [PersonUpdate(matchName: "Alice", newAge: 31)],
      author: "App1")
    try await kit.transactionProcessor.processNewTransactions(
      from: ["App1", "App2"],
      after: Date(timeIntervalSinceNow: -10),
      currentAuthor: "App2",
      cleanBeforeTimestamp: nil)
    let counts2 = await tracker.getCounts()
    #expect(counts2.update >= 1)

    try await app1Handler.deletePeople(named: ["Alice"], author: "App1")
    try await kit.transactionProcessor.processNewTransactions(
      from: ["App1", "App2"],
      after: Date(timeIntervalSinceNow: -10),
      currentAuthor: "App2",
      cleanBeforeTimestamp: nil)
    let counts3 = await tracker.getCounts()
    #expect(counts3.delete >= 1)
  }

  @Test("Manual cleaner integration test")
  func manualCleanerIntegration() async throws {
    let container = TestModelBuilder.createContainer(author: "App1")
    let app1Context = container.newBackgroundContext()
    let app1Handler = TestAppDataHandler(
      container: container,
      context: app1Context,
      viewName: "App1Handler")

    try await app1Handler.createPerson(name: "Alice", age: 30, author: "App1")

    let userDefaults = TestModelBuilder.createTestUserDefaults()
    let uniqueString = "TestKit.ManualCleaner.\(UUID().uuidString)."
    userDefaults.set(Date(), forKey: uniqueString + "App1")

    let kit = PersistentHistoryTrackingKit(
      container: container,
      contexts: [app1Context],
      currentAuthor: "App1",
      allAuthors: ["App1"],
      userDefaults: userDefaults,
      uniqueString: uniqueString,
      logLevel: 0,
      autoStart: false)

    let cleaner = kit.cleanerBuilder()
    await cleaner.clean()

    let count = try await app1Handler.personCount()
    #expect(count == 1)
  }

  @Test("Batch operation sync")
  func batchOperationSync() async throws {
    let container = TestModelBuilder.createContainer(author: "App1")
    let app1Context = container.newBackgroundContext()
    let app2Context = container.newBackgroundContext()
    let app1Handler = TestAppDataHandler(
      container: container,
      context: app1Context,
      viewName: "App1Handler")
    let app2Handler = TestAppDataHandler(
      container: container,
      context: app2Context,
      viewName: "App2Handler")

    try await app1Handler.createPeople(count: 10, author: "App1")

    let userDefaults = TestModelBuilder.createTestUserDefaults()
    let uniqueString = "TestKit.BatchOperation.\(UUID().uuidString)."
    let kit = PersistentHistoryTrackingKit(
      container: container,
      contexts: [app2Context],
      currentAuthor: "App2",
      allAuthors: ["App1", "App2"],
      userDefaults: userDefaults,
      uniqueString: uniqueString,
      logLevel: 0,
      autoStart: false)

    try await kit.transactionProcessor.processNewTransactions(
      from: ["App1", "App2"],
      after: nil,
      currentAuthor: "App2",
      cleanBeforeTimestamp: nil)

    let count = try await app2Handler.personCount()
    #expect(count == 10)
  }

  @Test("Multi-context sync")
  func multiContextSync() async throws {
    let container = TestModelBuilder.createContainer(author: "App1")
    let app1Context = container.newBackgroundContext()
    let app2Context = container.newBackgroundContext()
    let app3Context = container.newBackgroundContext()
    let app1Handler = TestAppDataHandler(
      container: container,
      context: app1Context,
      viewName: "App1Handler")
    let app2Handler = TestAppDataHandler(
      container: container,
      context: app2Context,
      viewName: "App2Handler")
    let app3Handler = TestAppDataHandler(
      container: container,
      context: app3Context,
      viewName: "App3Handler")

    try await app1Handler.createPerson(name: "Alice", age: 30, author: "App1")

    let userDefaults = TestModelBuilder.createTestUserDefaults()
    let uniqueString = "TestKit.MultiContext.\(UUID().uuidString)."
    let kit = PersistentHistoryTrackingKit(
      container: container,
      contexts: [app2Context, app3Context],
      currentAuthor: "App2",
      allAuthors: ["App1", "App2"],
      userDefaults: userDefaults,
      uniqueString: uniqueString,
      logLevel: 0,
      autoStart: false)

    try await kit.transactionProcessor.processNewTransactions(
      from: ["App1", "App2"],
      after: nil,
      currentAuthor: "App2",
      cleanBeforeTimestamp: nil)

    let app2Count = try await app2Handler.personCount()
    let app3Count = try await app3Handler.personCount()

    #expect(app2Count == 1)
    #expect(app3Count == 1)
  }
}
