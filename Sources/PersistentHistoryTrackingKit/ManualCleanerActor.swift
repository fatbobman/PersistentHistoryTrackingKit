//
//  ManualCleanerActor.swift
//  PersistentHistoryTrackingKit
//
//  Created by Claude on 2025-01-06
//  Copyright © 2025 Yang Xu. All rights reserved.
//

import CoreData
public import CoreDataEvolution
import Foundation

/// Manual cleaner actor for triggering transaction cleanup on demand.
///
/// Usage example:
/// ```swift
/// let kit = PersistentHistoryTrackingKit(...)
/// let cleaner = kit.cleanerBuilder()
///
/// // Whenever cleanup is needed (for example, when the app goes to background)
/// Task {
///     await cleaner.clean()
/// }
/// ```
@NSModelActor(disableGenerateInit: true)
public actor ManualCleanerActor {
  private let authors: [String]
  private let logger: PersistentHistoryTrackingKitLoggerProtocol
  private let logLevel: Int
  private let userDefaults: UserDefaults
  private let uniqueString: String

  public init(
    container: NSPersistentContainer,
    authors: [String],
    userDefaults: UserDefaults,
    uniqueString: String,
    logger: PersistentHistoryTrackingKitLoggerProtocol,
    logLevel: Int
  ) {
    self.authors = authors
    self.logger = logger
    self.logLevel = logLevel
    self.userDefaults = userDefaults
    self.uniqueString = uniqueString

    // Manually initialize the properties normally provided by @NSModelActor.
    let context = container.newBackgroundContext()
    modelExecutor = NSModelObjectContextExecutor(context: context)
    modelContainer = container
  }

  /// Execute the cleanup task.
  ///
  /// Cleanup flow:
  /// 1. Read the latest timestamp for each author.
  /// 2. Find the minimum timestamp (the last shared checkpoint).
  /// 3. Delete history before that timestamp.
  public func clean() {
    do {
      // 1. Get the shared (minimum) timestamp across all authors.
      guard let cleanTimestamp = getLastCommonTimestamp() else {
        log(.info, level: 2, "No common timestamp found, skipping clean")
        return
      }

      // 2. Perform cleanup.
      let deletedCount = try cleanTransactions(before: cleanTimestamp, for: authors)
      log(.info, level: 2, "Cleaned \(deletedCount) transactions before \(cleanTimestamp)")
    } catch {
      log(.error, level: 1, "Clean error: \(error.localizedDescription)")
    }
  }

  /// Retrieve the minimum timestamp across all authors.
  private func getLastCommonTimestamp() -> Date? {
    let timestamps = authors.compactMap { author -> Date? in
      let key = uniqueString + author
      return userDefaults.object(forKey: key) as? Date
    }

    // Return nil if no timestamps are recorded.
    guard !timestamps.isEmpty else { return nil }

    // Return the minimum timestamp (shared point).
    return timestamps.min()
  }

  /// Delete transactions that occurred before the provided timestamp.
  /// - Parameters:
  ///   - timestamp: Remove records before this timestamp.
  ///   - authors: Limit cleanup to these authors.
  /// - Returns: Number of transactions removed.
  @discardableResult
  private func cleanTransactions(before timestamp: Date, for authors: [String]) throws -> Int {
    let deleteRequest = NSPersistentHistoryChangeRequest.deleteHistory(before: timestamp)

    // Configure fetchRequest to target the specified authors.
    if !authors.isEmpty {
      if let fetchRequest = NSPersistentHistoryTransaction.fetchRequest {
        let predicates = authors.map { author in
          NSPredicate(
            format: "%K = %@",
            #keyPath(NSPersistentHistoryTransaction.author),
            author)
        }
        fetchRequest
          .predicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
        deleteRequest.fetchRequest = fetchRequest
      }
    }

    // Execute the delete request.
    let result = try modelContext.execute(deleteRequest) as? NSPersistentHistoryResult
    let deletedCount = (result?.result as? Int) ?? 0

    return deletedCount
  }

  /// Write to the logger according to the configured log level.
  private func log(_ type: PersistentHistoryTrackingKitLogType, level: Int, _ message: String) {
    guard level <= logLevel else { return }
    logger.log(type: type, message: message)
  }
}
