//
//  CleanStrategyTests.swift
//  PersistentHistoryTrackingKitTests
//
//  Created by Codex on 2026-02-28.
//

import CoreData
import Testing

@testable import PersistentHistoryTrackingKit

@Suite("Clean Strategy Tests")
struct CleanStrategyTests {
  @Test("None strategy disables automatic cleanup")
  func noneStrategyDisablesAutomaticCleanup() async throws {
    let container = TestModelBuilder.createContainer(
      author: "App1",
      testName: "noneStrategyDisablesAutomaticCleanup")
    let writer = TestAppDataHandler(container: container, viewName: "Writer")

    try await writer.createPerson(name: "Alice", age: 30, author: "App1")

    try await Task.sleep(nanoseconds: 100_000_000)

    try await writer.createPerson(name: "Bob", age: 31, author: "App1")

    let processor = makeProcessor(container: container, cleanStrategy: .none)

    _ = try await processor.processNewTransactionsWithTimestampManagement(
      from: ["App1", "App2"],
      after: nil,
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
    let writer = TestAppDataHandler(container: container, viewName: "Writer")

    try await writer.createPerson(name: "Alice", age: 30, author: "App1")

    try await Task.sleep(nanoseconds: 100_000_000)

    try await writer.createPerson(name: "Bob", age: 31, author: "App1")

    let processor = makeProcessor(
      container: container,
      userDefaults: userDefaults,
      cleanStrategy: .byDuration(seconds: 60 * 60))

    userDefaults.set(Date(), forKey: "PersistentHistoryTrackingKit.lastToken.App1")

    _ = try await processor.processNewTransactionsWithTimestampManagement(
      from: ["App1", "App2"],
      after: nil,
      currentAuthor: "App2")

    let countAfterFirstProcess = try await processor.testTransactionCount(
      from: ["App1", "App2"],
      after: nil)
    #expect(countAfterFirstProcess == 1)

    let lastTimestampResult = await processor.testGetLastTransactionTimestamp(for: "App2")
    let lastTimestamp = try #require(lastTimestampResult.timestamp)

    try await Task.sleep(nanoseconds: 100_000_000)

    try await writer.createPerson(name: "Charlie", age: 32, author: "App1")

    _ = try await processor.processNewTransactionsWithTimestampManagement(
      from: ["App1", "App2"],
      after: lastTimestamp,
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
    let writer = TestAppDataHandler(container: container, viewName: "Writer")

    try await writer.createPerson(name: "Alice", age: 30, author: "App1")

    try await Task.sleep(nanoseconds: 100_000_000)

    try await writer.createPerson(name: "Bob", age: 31, author: "App1")

    let processor = makeProcessor(
      container: container,
      userDefaults: userDefaults,
      cleanStrategy: .byNotification(times: 2))

    userDefaults.set(Date(), forKey: "PersistentHistoryTrackingKit.lastToken.App1")

    _ = try await processor.processNewTransactionsWithTimestampManagement(
      from: ["App1", "App2"],
      after: nil,
      currentAuthor: "App2")

    let countAfterFirstProcess = try await processor.testTransactionCount(
      from: ["App1", "App2"],
      after: nil)
    #expect(countAfterFirstProcess == 2)

    let lastTimestampResult = await processor.testGetLastTransactionTimestamp(for: "App2")
    let lastTimestamp = try #require(lastTimestampResult.timestamp)

    try await Task.sleep(nanoseconds: 100_000_000)

    try await writer.createPerson(name: "Charlie", age: 32, author: "App1")

    _ = try await processor.processNewTransactionsWithTimestampManagement(
      from: ["App1", "App2"],
      after: lastTimestamp,
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
    let writer = TestAppDataHandler(container: container, viewName: "Writer")

    try await writer.createPerson(name: "Alice", age: 30, author: "App1")

    try await Task.sleep(nanoseconds: 100_000_000)

    try await writer.createPerson(name: "Bob", age: 31, author: "App1")

    let processor = makeProcessor(
      container: container,
      cleanStrategy: .byDuration(seconds: 60 * 60))

    _ = try await processor.processNewTransactionsWithTimestampManagement(
      from: ["App1", "App2", "App3"],
      after: nil,
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
    let writer = TestAppDataHandler(container: container, viewName: "Writer")

    try await writer.createPerson(name: "Alice", age: 30, author: "App1")

    try await Task.sleep(nanoseconds: 100_000_000)

    try await writer.createPerson(name: "Bob", age: 31, author: "App1")

    let processor = makeProcessor(
      container: container,
      userDefaults: userDefaults,
      cleanStrategy: .byDuration(seconds: 60 * 60))

    userDefaults.set(Date(), forKey: "PersistentHistoryTrackingKit.lastToken.App1")

    _ = try await processor.processNewTransactionsWithTimestampManagement(
      from: ["App1", "App2", "BatchProcessor"],
      after: nil,
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
      contexts: [container.newBackgroundContext()],
      hookRegistry: hookRegistry,
      cleanStrategy: cleanStrategy,
      timestampManager: timestampManager)
  }
}
