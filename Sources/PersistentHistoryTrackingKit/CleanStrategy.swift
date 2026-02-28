//
//  CleanStrategy.swift
//
//
//  Created by Yang Xu on 2022/2/14
//  Copyright © 2022 Yang Xu. All rights reserved.
//
//  Follow me on Twitter: @fatbobman
//  My Blog: https://www.fatbobman.com
//  微信公共号: 肘子的Swift记事本
//

public import Foundation

/// Transaction cleanup strategies.
///
/// Choose `.none` if you only merge transactions and do not want automatic cleanup.
/// `.byNotification` cleans after a specified number of notifications (default is `.byNotification(0)`).
/// `.byDuration` enforces a minimum number of seconds between two cleanup runs.
public enum TransactionCleanStrategy: Sendable {
  case none
  case byDuration(seconds: TimeInterval)
  case byNotification(times: Int)
}

/// Cleanup policy protocol.
protocol TransactionPurgePolicy: Sendable {
  /// Decide whether cleanup is allowed each time a notification arrives.
  mutating func allowedToClean() -> Bool
  init(strategy: TransactionCleanStrategy)
}

/// Disabled strategy. When selected, the Kit never performs automatic cleanup.
/// Use when you want total manual control and rely on manually triggered cleaners.
/// Combine with the Kit's manual cleaner helper when needed.
struct TransactionCleanStrategyNone: TransactionPurgePolicy, Sendable {
  func allowedToClean() -> Bool {
    false
  }

  init(strategy: TransactionCleanStrategy = .none) {}
}

/// Cleanup strategy driven by a time interval.
/// Enforces a minimum interval (in seconds) between two cleanup runs.
struct TransactionCleanStrategyByDuration: TransactionPurgePolicy, Sendable {
  private var lastCleanTimestamp: Date?
  private let duration: TimeInterval

  mutating func allowedToClean() -> Bool {
    if (lastCleanTimestamp ?? .distantPast).advanced(by: duration) < Date() {
      lastCleanTimestamp = Date()
      return true
    } else {
      return false
    }
  }

  init(strategy: TransactionCleanStrategy) {
    if case .byDuration(let seconds) = strategy {
      self.duration = seconds
    } else {
      fatalError("Transaction clean strategy should be byDuration")
    }
  }
}

/// Cleanup strategy driven by notification count.
///
/// Runs cleanup every N notifications. For example, `times = 1` means run every time, while `times = 3` runs every third notification.
struct TransactionCleanStrategyByNotification: TransactionPurgePolicy, Sendable {
  private var count: Int
  private let times: Int
  init(strategy: TransactionCleanStrategy) {
    if case .byNotification(times: let times) = strategy {
      self.times = max(1, times)
      self.count = 0
    } else {
      fatalError("Transaction clean strategy should be byNotification")
    }
  }

  mutating func allowedToClean() -> Bool {
    count += 1
    if count >= times {
      count = 0
      return true
    } else {
      return false
    }
  }
}
