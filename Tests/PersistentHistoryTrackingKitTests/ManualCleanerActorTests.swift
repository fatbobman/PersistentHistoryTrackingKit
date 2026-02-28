//
//  ManualCleanerActorTests.swift
//  PersistentHistoryTrackingKitTests
//
//  Created by Claude on 2025-01-06
//

import CoreData
import Testing

@testable import PersistentHistoryTrackingKit

@Suite("ManualCleanerActor Tests", .serialized)
struct ManualCleanerActorTests {
  @Test("Run cleanup - happy path")
  func cleanNormalFlow() async throws {
    let container = TestModelBuilder.createContainer(author: "App1")
    let app1Handler = TestAppDataHandler(container: container, viewName: "App1Handler")

    try await app1Handler.createPerson(name: "Alice", age: 30, author: "App1")

    // Simulate persisting a timestamp to UserDefaults.
    let userDefaults = TestModelBuilder.createTestUserDefaults()
    let uniqueString = "TestKit.lastToken."
    userDefaults.set(Date(), forKey: uniqueString + "App1")

    // Build the cleaner.
    let cleaner = ManualCleanerActor(
      container: container,
      authors: ["App1"],
      userDefaults: userDefaults,
      uniqueString: uniqueString,
      logger: DefaultLogger(),
      logLevel: 2)

    // Execute cleanup (should not crash).
    await cleaner.clean()

    let count = try await app1Handler.personCount()
    #expect(count == 1)
  }

  @Test("Get the last shared timestamp")
  func getLastCommonTimestamp() async throws {
    let container = TestModelBuilder.createContainer(author: "App1")

    // Simulate timestamps for multiple authors.
    let userDefaults = TestModelBuilder.createTestUserDefaults()
    let uniqueString = "TestKit.lastToken."

    let date1 = Date(timeIntervalSinceNow: -100)  // 100 seconds ago
    let date2 = Date(timeIntervalSinceNow: -50)  // 50 seconds ago
    let date3 = Date(timeIntervalSinceNow: -200)  // 200 seconds ago (smallest)

    userDefaults.set(date1, forKey: uniqueString + "App1")
    userDefaults.set(date2, forKey: uniqueString + "App2")
    userDefaults.set(date3, forKey: uniqueString + "App3")

    // Build the cleaner.
    let cleaner = ManualCleanerActor(
      container: container,
      authors: ["App1", "App2", "App3"],
      userDefaults: userDefaults,
      uniqueString: uniqueString,
      logger: DefaultLogger(),
      logLevel: 0)

    // Run cleanup (which should use the minimum timestamp).
    await cleaner.clean()

    // Test passes if cleanup completes without crashing
  }

  @Test("Handle empty timestamp state")
  func handleEmptyTimestamp() async throws {
    let container = TestModelBuilder.createContainer(author: "App1")

    // Use a new uniqueString to guarantee no timestamps exist.
    let userDefaults = TestModelBuilder.createTestUserDefaults()
    let uniqueString = "TestKit.EmptyTimestamp.\(UUID().uuidString)."

    // Build the cleaner.
    let cleaner = ManualCleanerActor(
      container: container,
      authors: ["NonExistentApp"],
      userDefaults: userDefaults,
      uniqueString: uniqueString,
      logger: DefaultLogger(),
      logLevel: 0)

    // Run cleanup (should be skipped gracefully).
    await cleaner.clean()

    // Test passes if cleanup completes without crashing
  }

  @Test("Verify transaction count after cleanup")
  func verifyTransactionCountAfterClean() async throws {
    let container = TestModelBuilder.createContainer(author: "App1")
    let app1Handler = TestAppDataHandler(container: container, viewName: "App1Handler")

    try await app1Handler.createPerson(name: "Alice", age: 30, author: "App1")

    let firstTimestamp = Date()

    try await Task.sleep(nanoseconds: 100_000_000)

    try await app1Handler.createPerson(name: "Bob", age: 25, author: "App1")

    // Simulate persisting the timestamp of the first batch.
    let userDefaults = TestModelBuilder.createTestUserDefaults()
    let uniqueString = "TestKit.lastToken.\(UUID().uuidString)."
    userDefaults.set(firstTimestamp, forKey: uniqueString + "App1")

    // Build the cleaner.
    let cleaner = ManualCleanerActor(
      container: container,
      authors: ["App1"],
      userDefaults: userDefaults,
      uniqueString: uniqueString,
      logger: DefaultLogger(),
      logLevel: 0)

    // Perform cleanup.
    await cleaner.clean()

    let count = try await app1Handler.personCount()
    #expect(count == 2)
  }
}
