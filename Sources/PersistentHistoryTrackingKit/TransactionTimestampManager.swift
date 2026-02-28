//
//  TransactionTimestampManager.swift
//
//
//  Created by Yang Xu on 2022/2/10
//  Copyright © 2022 Yang Xu. All rights reserved.
//
//  Follow me on Twitter: @fatbobman
//  My Blog: https://www.fatbobman.com
//  微信公共号: 肘子的Swift记事本
//

public import Foundation

/// Timestamp manager for Transaction merge updates per author.
/// This implementation uses UserDefaults to save the last update date for each author and
/// returns a cleanup checkpoint only when every required author has recorded a timestamp.
public struct TransactionTimestampManager: @unchecked Sendable, TransactionTimestampManagerProtocol
{
  /// UserDefaults instance for saving. For AppGroup, should use an instance available to all members, e.g., UserDefaults(suiteName: Settings.AppGroup.groupID)
  private let userDefaults: UserDefaults
  /// Prefix for timestamp keys saved in UserDefaults
  private let uniqueString: String

  public func getLastCommonTransactionTimestamp(
    in authors: [String], exclude batchAuthors: [String] = []
  ) -> Date? {
    let requiredAuthors = Set(authors).subtracting(batchAuthors)
    guard !requiredAuthors.isEmpty else { return nil }

    var lastTimestamps: [Date] = []
    lastTimestamps.reserveCapacity(requiredAuthors.count)

    for author in requiredAuthors {
      guard let timestamp = getLastHistoryTransactionTimestamp(for: author) else {
        return nil
      }
      lastTimestamps.append(timestamp)
    }

    return lastTimestamps.min()
  }

  public func updateLastHistoryTransactionTimestamp(for author: String, to newDate: Date?) {
    let key = uniqueString + author
    userDefaults.set(newDate, forKey: key)
  }

  /// Get the last update date for the specified author
  /// - Parameter author: author is the string name for each app or app extension. Should match NSManagedObjectContext's transactionAuthor
  /// - Returns: The last update date of that author. Returns nil if the author has no update date yet
  public func getLastHistoryTransactionTimestamp(for author: String) -> Date? {
    let key = uniqueString + author
    return userDefaults.value(forKey: key) as? Date
  }

  /// Create a timestamp manager for Transaction merge updates per author.
  /// - Parameters:
  ///   - userDefaults: UserDefaults instance for saving.
  ///   For AppGroup, should use an instance available to all members, e.g., UserDefaults(suiteName: Settings.AppGroup.groupID)
  ///   - maximumDuration: Reserved for future cleanup readiness policies. Default is 604,800 seconds (7 days).
  ///   - uniqueString: Prefix for timestamp keys saved in UserDefaults. Default is "PersistentHistoryTrackingKit.lastToken."
  init(
    userDefaults: UserDefaults,
    maximumDuration: TimeInterval = 60 * 60 * 24 * 7,  // 7 days
    uniqueString: String = "PersistentHistoryTrackingKit.lastToken."
  ) {
    self.userDefaults = userDefaults
    self.uniqueString = uniqueString
    _ = maximumDuration
  }
}
