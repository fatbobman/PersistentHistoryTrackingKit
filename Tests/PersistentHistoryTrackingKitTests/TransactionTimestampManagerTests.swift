//
//  TransactionTimestampManagerTests.swift
//  PersistentHistoryTrackingKitTests
//
//  Created by Codex on 2026-02-28.
//

import Foundation
import Testing

@testable import PersistentHistoryTrackingKit

@Suite("TransactionTimestampManager Tests")
struct TransactionTimestampManagerTests {
  @Test("Returns nil when a required author is missing a timestamp")
  func returnsNilWhenRequiredAuthorIsMissingTimestamp() {
    let userDefaults = TestModelBuilder.createTestUserDefaults()
    let manager = TransactionTimestampManager(
      userDefaults: userDefaults,
      maximumDuration: 604_800)

    userDefaults.set(Date(), forKey: "PersistentHistoryTrackingKit.lastToken.App1")

    let timestamp = manager.getLastCommonTransactionTimestamp(in: ["App1", "App2"])

    #expect(timestamp == nil)
  }

  @Test("Returns the minimum timestamp when all required authors are present")
  func returnsMinimumTimestampWhenAllRequiredAuthorsArePresent() {
    let userDefaults = TestModelBuilder.createTestUserDefaults()
    let manager = TransactionTimestampManager(
      userDefaults: userDefaults,
      maximumDuration: 604_800)

    let older = Date(timeIntervalSinceNow: -120)
    let newer = Date(timeIntervalSinceNow: -60)

    userDefaults.set(older, forKey: "PersistentHistoryTrackingKit.lastToken.App1")
    userDefaults.set(newer, forKey: "PersistentHistoryTrackingKit.lastToken.App2")

    let timestamp = manager.getLastCommonTransactionTimestamp(in: ["App1", "App2"])

    #expect(timestamp == older)
  }

  @Test("Batch authors are excluded from readiness checks")
  func batchAuthorsAreExcludedFromReadinessChecks() {
    let userDefaults = TestModelBuilder.createTestUserDefaults()
    let manager = TransactionTimestampManager(
      userDefaults: userDefaults,
      maximumDuration: 604_800)

    let app1Timestamp = Date(timeIntervalSinceNow: -120)
    let app2Timestamp = Date(timeIntervalSinceNow: -60)

    userDefaults.set(app1Timestamp, forKey: "PersistentHistoryTrackingKit.lastToken.App1")
    userDefaults.set(app2Timestamp, forKey: "PersistentHistoryTrackingKit.lastToken.App2")

    let timestamp = manager.getLastCommonTransactionTimestamp(
      in: ["App1", "App2", "BatchProcessor"],
      exclude: ["BatchProcessor"])

    #expect(timestamp == app1Timestamp)
  }
}
