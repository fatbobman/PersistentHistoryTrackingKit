//
//  TransactionMergeBehaviorTests.swift
//  PersistentHistoryTrackingKitTests
//
//  Created by Codex on 2026-07-07.
//

import CoreData
import Foundation
import Testing

@testable import PersistentHistoryTrackingKit

@Suite("TransactionMergeBehavior Tests")
struct TransactionMergeBehaviorTests {
  #if swift(>=6.2)
    @Test("Automatic merge behavior keeps the default merge")
    func automaticMergeBehaviorKeepsDefaultMerge() async throws {
      let container = TestModelBuilder.createContainer(
        author: "App1",
        testName: "automaticMergeBehaviorKeepsDefaultMerge")
      let app1Context = container.newBackgroundContext()
      let app2Context = container.newBackgroundContext()
      app2Context.retainsRegisteredObjects = true

      let app1Handler = TestAppDataHandler(
        container: container,
        context: app1Context,
        viewName: "App1Handler")
      let app2Handler = TestAppDataHandler(
        container: container,
        context: app2Context,
        viewName: "App2Handler")

      let kit = PersistentHistoryTrackingKit(
        container: container,
        contexts: [app2Context],
        currentAuthor: "App2",
        allAuthors: ["App1", "App2"],
        userDefaults: TestModelBuilder.createTestUserDefaults(),
        mergeBehavior: .automatic,
        logLevel: 0,
        autoStart: false)

      let idURL = try await app1Handler.createPerson(name: "Alice", age: 30, author: "App1")
      let initialSummary = try await app2Handler.loadPersonSummary(for: idURL)
      #expect(initialSummary?.1 == 30)

      try await app1Handler.updatePeople(
        [PersonUpdate(matchName: "Alice", newAge: 31)],
        author: "App1")

      let staleSummary = await app2Handler.registeredPersonSummary(for: idURL)
      #expect(staleSummary?.1 == 30)

      let processedCount = try await kit.transactionProcessor
        .processNewTransactionsWithTimestampManagement(
          from: ["App1", "App2"],
          after: nil,
          currentAuthor: "App2")

      #expect(processedCount >= 1)

      let mergedSummary = await app2Handler.registeredPersonSummary(for: idURL)
      #expect(mergedSummary?.1 == 31)
    }

    @Test("Disabled merge behavior observes and timestamps without merging")
    func disabledMergeBehaviorObservesAndTimestampsWithoutMerging() async throws {
      let container = TestModelBuilder.createContainer(
        author: "App1",
        testName: "disabledMergeBehaviorObservesAndTimestampsWithoutMerging")
      let app1Context = container.newBackgroundContext()
      let app2Context = container.newBackgroundContext()
      app2Context.retainsRegisteredObjects = true

      let app1Handler = TestAppDataHandler(
        container: container,
        context: app1Context,
        viewName: "App1Handler")
      let app2Handler = TestAppDataHandler(
        container: container,
        context: app2Context,
        viewName: "App2Handler")

      let userDefaults = TestModelBuilder.createTestUserDefaults()
      let kit = PersistentHistoryTrackingKit(
        container: container,
        contexts: [app2Context],
        currentAuthor: "App2",
        allAuthors: ["App1", "App2"],
        userDefaults: userDefaults,
        mergeBehavior: .disabled,
        logLevel: 0,
        autoStart: false)

      actor HookTracker {
        private var observerCount = 0
        private var mergeCount = 0

        func recordObserver(_ contexts: [HookContext]) {
          observerCount += contexts.count
        }

        func recordMerge() {
          mergeCount += 1
        }

        func counts() -> (observer: Int, merge: Int) {
          (observerCount, mergeCount)
        }
      }

      let tracker = HookTracker()

      await kit.registerObserver(entityName: "Person", operation: .update) { contexts in
        await tracker.recordObserver(contexts)
      }

      await kit.registerMergeHook { _ in
        await tracker.recordMerge()
        return .goOn
      }

      let idURL = try await app1Handler.createPerson(name: "Alice", age: 30, author: "App1")
      let initialSummary = try await app2Handler.loadPersonSummary(for: idURL)
      #expect(initialSummary?.1 == 30)

      try await app1Handler.updatePeople(
        [PersonUpdate(matchName: "Alice", newAge: 31)],
        author: "App1")

      let processedCount = try await kit.transactionProcessor
        .processNewTransactionsWithTimestampManagement(
          from: ["App1", "App2"],
          after: nil,
          currentAuthor: "App2")

      #expect(processedCount >= 1)

      let counts = await tracker.counts()
      #expect(counts.observer >= 1)
      #expect(counts.merge == 0)

      let timestampResult = await kit.transactionProcessor.testGetLastTransactionTimestamp(
        for: "App2")
      #expect(timestampResult.hasTimestamp == true)

      let unmergedSummary = await app2Handler.registeredPersonSummary(for: idURL)
      #expect(unmergedSummary?.1 == 30)
    }
  #endif

  @Test("Disabled merge behavior still runs automatic cleanup")
  func disabledMergeBehaviorStillRunsAutomaticCleanup() async throws {
    let container = TestModelBuilder.createContainer(
      author: "App1",
      testName: "disabledMergeBehaviorStillRunsAutomaticCleanup")
    let userDefaults = TestModelBuilder.createTestUserDefaults()
    let writer = TestAppDataHandler(container: container, viewName: "Writer")

    try await writer.createPerson(name: "Alice", age: 30, author: "App1")
    try await Task.sleep(nanoseconds: 100_000_000)
    try await writer.createPerson(name: "Bob", age: 31, author: "App1")

    let timestampManager = TransactionTimestampManager(
      userDefaults: userDefaults,
      maximumDuration: 604_800)
    let processor = TransactionProcessorActor(
      container: container,
      contexts: [container.newBackgroundContext()],
      hookRegistry: HookRegistryActor(),
      cleanStrategy: .byDuration(seconds: 60 * 60),
      timestampManager: timestampManager,
      mergeBehavior: .disabled,
      logLevel: 0)

    userDefaults.set(Date(), forKey: "PersistentHistoryTrackingKit.lastToken.App1")

    _ = try await processor.processNewTransactionsWithTimestampManagement(
      from: ["App1", "App2"],
      after: nil,
      currentAuthor: "App2")

    let remainingCount = try await processor.testTransactionCount(
      from: ["App1", "App2"],
      after: nil)

    #expect(remainingCount == 1)
  }

  @Test("Disabled merge behavior emits notice when registering a merge hook")
  func disabledMergeBehaviorEmitsNoticeWhenRegisteringMergeHook() async throws {
    let container = TestModelBuilder.createContainer(
      author: "App1",
      testName: "disabledMergeBehaviorEmitsNoticeWhenRegisteringMergeHook")
    let logger = RecordingLogger()

    let kit = PersistentHistoryTrackingKit(
      container: container,
      currentAuthor: "App2",
      allAuthors: ["App1", "App2"],
      userDefaults: TestModelBuilder.createTestUserDefaults(),
      mergeBehavior: .disabled,
      logger: logger,
      logLevel: 1,
      autoStart: false)

    _ = await kit.registerMergeHook { _ in .goOn }

    let entries = logger.snapshot()
    #expect(
      entries.contains { entry in
        entry.type == .notice
          && entry.message.contains("mergeBehavior is .disabled")
      })
  }
}

private final class RecordingLogger: PersistentHistoryTrackingKitLoggerProtocol, @unchecked Sendable
{
  private let lock = NSLock()
  private var entries: [(type: PersistentHistoryTrackingKitLogType, message: String)] = []

  func log(type: PersistentHistoryTrackingKitLogType, message: String) {
    lock.lock()
    entries.append((type, message))
    lock.unlock()
  }

  func snapshot() -> [(type: PersistentHistoryTrackingKitLogType, message: String)] {
    lock.lock()
    defer { lock.unlock() }
    return entries
  }
}
