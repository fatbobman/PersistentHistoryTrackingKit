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
/// This implementation uses UserDefaults to save the last update date for each author and returns the date safe for deletion.
/// To prevent incomplete data in AppGroup scenarios where some apps are never enabled or implemented,
/// a threshold date mechanism is set up that returns the threshold as the safe deletion date when conditions are met
public struct TransactionTimestampManager: @unchecked Sendable, TransactionTimestampManagerProtocol
{
  /// UserDefaults instance for saving. For AppGroup, should use an instance available to all members, e.g., UserDefaults(suiteName: Settings.AppGroup.groupID)
  private let userDefaults: UserDefaults
  /// Maximum duration transactions can be kept (seconds). If all author timestamps cannot be retrieved within this time,
  /// returns the date calculated by subtracting this duration from current time: Date().addingTimeInterval(-1 * abs(maximumDuration))
  private let maximumDuration: TimeInterval
  /// Prefix for timestamp keys saved in UserDefaults
  private let uniqueString: String

  public func getLastCommonTransactionTimestamp(
    in authors: [String], exclude batchAuthors: [String] = []
  ) -> Date? {
    let shouldCheckAuthors = Set(authors).subtracting(batchAuthors)
    let lastTimestamps =
      shouldCheckAuthors
      .compactMap { author in
        getLastHistoryTransactionTimestamp(for: author)
      }
    // If no author has recorded a timestamp, return nil
    let lastTimestamp = lastTimestamps.min() ?? Date().addingTimeInterval(-1 * abs(maximumDuration))
    return lastTimestamp
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
  ///   - maximumDuration: Maximum duration transactions can be kept (seconds). If all author timestamps cannot be retrieved within this time,
  ///   returns Date().addingTimeInterval(-1 * abs(maximumDuration)). Default is 604,800 seconds (7 days).
  ///   - uniqueString: Prefix for timestamp keys saved in UserDefaults. Default is "PersistentHistoryTrackingKit.lastToken."
  init(
    userDefaults: UserDefaults,
    maximumDuration: TimeInterval = 60 * 60 * 24 * 7,  // 7 days
    uniqueString: String = "PersistentHistoryTrackingKit.lastToken."
  ) {
    self.userDefaults = userDefaults
    self.maximumDuration = maximumDuration
    self.uniqueString = uniqueString
  }
}
