//
//  TransactionTimestampManagerProtocol.swift
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

/// Protocol for managing timestamp saving and retrieval
public protocol TransactionTimestampManagerProtocol {
  /// Get the timestamp safe for deletion from the given author list
  ///
  /// If exclude is provided, only authors in (authors - batchAuthors) will be checked for
  /// timestamp validation.
  /// Cleaner will use this timestamp to instruct Core Data to delete transactions before this
  /// timestamp.
  /// - Returns: The date safe for deletion.
  /// When nil, at least one required author has not recorded a timestamp yet.
  func getLastCommonTransactionTimestamp(in authors: [String], exclude batchAuthors: [String])
    -> Date?
  /// Update the last update date for the specified author
  /// Last update means the program corresponding to that author (app, app extension) has completed Transaction merge work at that timestamp
  func updateLastHistoryTransactionTimestamp(for author: String, to newDate: Date?)
  /// Get the last update date for the specified author
  /// - Parameter author: author is the string name for each app or app extension. Should match NSManagedObjectContext's transactionAuthor
  /// - Returns: The last update date of that author. Returns nil if the author has no update date yet
  func getLastHistoryTransactionTimestamp(for author: String) -> Date?
}
