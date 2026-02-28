//
//  CleanStrategyTests.swift
//  PersistentHistoryTrackingKitTests
//
//  Created by Codex on 2026-02-28.
//

import CoreData
import Testing

@testable import PersistentHistoryTrackingKit

@Suite("Clean Strategy Tests", .serialized)
struct CleanStrategyTests {
  @Test("None strategy disables automatic cleanup")
  func noneStrategyDisablesAutomaticCleanup() async throws {
    let container = TestModelBuilder.createContainer(
      author: "App1",
      testName: "noneStrategyDisablesAutomaticCleanup")
    let context1 = container.viewContext
    context1.transactionAuthor = "App1"

    TestModelBuilder.createPerson(name: "Alice", age: 30, in: context1)
    try context1.save()

    try await Task.sleep(nanoseconds: 100_000_000)

    TestModelBuilder.createPerson(name: "Bob", age: 31, in: context1)
    try context1.save()

    let processor = makeProcessor(container: container, cleanStrategy: .none)
    let mergeContext = container.newBackgroundContext()
    mergeContext.transactionAuthor = "App2"

    _ = try await processor.processNewTransactionsWithTimestampManagement(
      from: ["App1", "App2"],
      after: nil,
      mergeInto: [mergeContext],
      currentAuthor: "App2")

    let remainingCount = try await processor.testTransactionCount(
      from: ["App1", "App2"],
      after: nil)

    #expect(remainingCount == 2)
  }

  @Test("Duration strategy throttles cleanup across notifications")
  func durationStrategyThrottlesCleanup() async throws {
    let container = TestModelBuilder.createContainer(
      author: "App1",
      testName: "durationStrategyThrottlesCleanup")
    let userDefaults = TestModelBuilder.createTestUserDefaults()
    let context1 = container.viewContext
    context1.transactionAuthor = "App1"

    TestModelBuilder.createPerson(name: "Alice", age: 30, in: context1)
    try context1.save()

    try await Task.sleep(nanoseconds: 100_000_000)

    TestModelBuilder.createPerson(name: "Bob", age: 31, in: context1)
    try context1.save()

    let processor = makeProcessor(
      container: container,
      userDefaults: userDefaults,
      cleanStrategy: .byDuration(seconds: 60 * 60))
    let mergeContext = container.newBackgroundContext()
    mergeContext.transactionAuthor = "App2"

    userDefaults.set(Date(), forKey: "PersistentHistoryTrackingKit.lastToken.App1")

    _ = try await processor.processNewTransactionsWithTimestampManagement(
      from: ["App1", "App2"],
      after: nil,
      mergeInto: [mergeContext],
      currentAuthor: "App2")

    let countAfterFirstProcess = try await processor.testTransactionCount(
      from: ["App1", "App2"],
      after: nil)
    #expect(countAfterFirstProcess == 1)

    let lastTimestampResult = await processor.testGetLastTransactionTimestamp(for: "App2")
    let lastTimestamp = try #require(lastTimestampResult.timestamp)

    try await Task.sleep(nanoseconds: 100_000_000)

    TestModelBuilder.createPerson(name: "Charlie", age: 32, in: context1)
    try context1.save()

    _ = try await processor.processNewTransactionsWithTimestampManagement(
      from: ["App1", "App2"],
      after: lastTimestamp,
      mergeInto: [mergeContext],
      currentAuthor: "App2")

    let countAfterSecondProcess = try await processor.testTransactionCount(
      from: ["App1", "App2"],
      after: nil)
    #expect(countAfterSecondProcess == 2)
  }

  @Test("Notification strategy cleans on the configured notification count")
  func notificationStrategyCleansOnConfiguredCount() async throws {
    let container = TestModelBuilder.createContainer(
      author: "App1",
      testName: "notificationStrategyCleansOnConfiguredCount")
    let userDefaults = TestModelBuilder.createTestUserDefaults()
    let context1 = container.viewContext
    context1.transactionAuthor = "App1"

    TestModelBuilder.createPerson(name: "Alice", age: 30, in: context1)
    try context1.save()

    try await Task.sleep(nanoseconds: 100_000_000)

    TestModelBuilder.createPerson(name: "Bob", age: 31, in: context1)
    try context1.save()

    let processor = makeProcessor(
      container: container,
      userDefaults: userDefaults,
      cleanStrategy: .byNotification(times: 2))
    let mergeContext = container.newBackgroundContext()
    mergeContext.transactionAuthor = "App2"

    userDefaults.set(Date(), forKey: "PersistentHistoryTrackingKit.lastToken.App1")

    _ = try await processor.processNewTransactionsWithTimestampManagement(
      from: ["App1", "App2"],
      after: nil,
      mergeInto: [mergeContext],
      currentAuthor: "App2")

    let countAfterFirstProcess = try await processor.testTransactionCount(
      from: ["App1", "App2"],
      after: nil)
    #expect(countAfterFirstProcess == 2)

    let lastTimestampResult = await processor.testGetLastTransactionTimestamp(for: "App2")
    let lastTimestamp = try #require(lastTimestampResult.timestamp)

    try await Task.sleep(nanoseconds: 100_000_000)

    TestModelBuilder.createPerson(name: "Charlie", age: 32, in: context1)
    try context1.save()

    _ = try await processor.processNewTransactionsWithTimestampManagement(
      from: ["App1", "App2"],
      after: lastTimestamp,
      mergeInto: [mergeContext],
      currentAuthor: "App2")

    let countAfterSecondProcess = try await processor.testTransactionCount(
      from: ["App1", "App2"],
      after: nil)
    #expect(countAfterSecondProcess == 1)
  }

  @Test("Automatic cleanup waits for missing author timestamps")
  func automaticCleanupWaitsForMissingAuthorTimestamps() async throws {
    let container = TestModelBuilder.createContainer(
      author: "App1",
      testName: "automaticCleanupWaitsForMissingAuthorTimestamps")
    let context1 = container.viewContext
    context1.transactionAuthor = "App1"

    TestModelBuilder.createPerson(name: "Alice", age: 30, in: context1)
    try context1.save()

    try await Task.sleep(nanoseconds: 100_000_000)

    TestModelBuilder.createPerson(name: "Bob", age: 31, in: context1)
    try context1.save()

    let processor = makeProcessor(
      container: container,
      cleanStrategy: .byDuration(seconds: 60 * 60))
    let mergeContext = container.newBackgroundContext()
    mergeContext.transactionAuthor = "App2"

    _ = try await processor.processNewTransactionsWithTimestampManagement(
      from: ["App1", "App2", "App3"],
      after: nil,
      mergeInto: [mergeContext],
      currentAuthor: "App2")

    let remainingCount = try await processor.testTransactionCount(
      from: ["App1", "App2", "App3"],
      after: nil)

    #expect(remainingCount == 2)
  }

  @Test("Batch authors do not block cleanup readiness")
  func batchAuthorsDoNotBlockCleanupReadiness() async throws {
    let container = TestModelBuilder.createContainer(
      author: "App1",
      testName: "batchAuthorsDoNotBlockCleanupReadiness")
    let userDefaults = TestModelBuilder.createTestUserDefaults()
    let context1 = container.viewContext
    context1.transactionAuthor = "App1"

    TestModelBuilder.createPerson(name: "Alice", age: 30, in: context1)
    try context1.save()

    try await Task.sleep(nanoseconds: 100_000_000)

    TestModelBuilder.createPerson(name: "Bob", age: 31, in: context1)
    try context1.save()

    let processor = makeProcessor(
      container: container,
      userDefaults: userDefaults,
      cleanStrategy: .byDuration(seconds: 60 * 60))
    let mergeContext = container.newBackgroundContext()
    mergeContext.transactionAuthor = "App2"

    userDefaults.set(Date(), forKey: "PersistentHistoryTrackingKit.lastToken.App1")

    _ = try await processor.processNewTransactionsWithTimestampManagement(
      from: ["App1", "App2", "BatchProcessor"],
      after: nil,
      mergeInto: [mergeContext],
      currentAuthor: "App2",
      batchAuthors: ["BatchProcessor"])

    let remainingCount = try await processor.testTransactionCount(
      from: ["App1", "App2", "BatchProcessor"],
      after: nil)

    #expect(remainingCount == 1)
  }

  private func makeProcessor(
    container: NSPersistentContainer,
    userDefaults: UserDefaults = TestModelBuilder.createTestUserDefaults(),
    cleanStrategy: TransactionCleanStrategy
  ) -> TransactionProcessorActor {
    let hookRegistry = HookRegistryActor()
    let timestampManager = TransactionTimestampManager(
      userDefaults: userDefaults,
      maximumDuration: 604_800)
    return TransactionProcessorActor(
      container: container,
      hookRegistry: hookRegistry,
      cleanStrategy: cleanStrategy,
      timestampManager: timestampManager)
  }
}
