//
//  TransactionProcessorActor+Testing.swift
//  PersistentHistoryTrackingKit
//
//  Created by Claude on 2025-01-06
//  Copyright © 2025 Yang Xu. All rights reserved.
//

@preconcurrency import CoreData
import Foundation

#if DEBUG
    /// Testing helpers executed inside the actor to avoid passing NSPersistentHistoryTransaction
    /// across actor boundaries.
    extension TransactionProcessorActor {
        /// Verify that `fetchTransactions` correctly excludes a given author.
        /// - Parameters:
        ///   - authors: Authors to fetch.
        ///   - date: Starting timestamp.
        ///   - excludeAuthor: Author to exclude.
        /// - Returns: (transaction count, whether every transaction excludes the target author)
        func testFetchTransactionsExcludesAuthor(
            from authors: [String],
            after date: Date?,
            excludeAuthor: String?) throws -> (count: Int, allExcluded: Bool)
        {
            let transactions = try fetchTransactions(
                from: authors,
                after: date,
                excludeAuthor: excludeAuthor)

            // Ensure no transaction matches the excluded author.
            let allExcluded: Bool = if let excludeAuthor {
                transactions.allSatisfy { $0.author != excludeAuthor }
            } else {
                true
            }

            return (transactions.count, allExcluded)
        }

        /// Test the deletion results of `cleanTransactions`.
        /// - Parameters:
        ///   - timestamp: Delete transactions before this timestamp.
        ///   - authors: Authors to clean.
        ///   - expectedBefore: Optional expected count before cleanup (validation aid).
        /// - Returns: (deleted count, remaining count)
        func testCleanTransactions(
            before timestamp: Date,
            for authors: [String],
            expectedBefore: Int?) throws -> (deletedCount: Int, remainingCount: Int)
        {
            // Count transactions before cleanup.
            let beforeTransactions = try fetchTransactions(from: authors, after: nil)
            let beforeCount = beforeTransactions.count

            // Validate against the provided expectation when set.
            if let expected = expectedBefore {
                guard beforeCount == expected else {
                    throw TestError.unexpectedCount(expected: expected, actual: beforeCount)
                }
            }

            // Perform cleanup.
            let deletedCount = try cleanTransactions(before: timestamp, for: authors)

            // Count the remaining transactions.
            let afterTransactions = try fetchTransactions(from: authors, after: nil)
            let remainingCount = afterTransactions.count

            return (deletedCount, remainingCount)
        }

        /// Test the full `processNewTransactions` flow.
        /// - Parameters:
        ///   - authors: Authors whose transactions should be processed.
        ///   - lastTimestamp: Last processed timestamp.
        ///   - contexts: Target contexts.
        ///   - currentAuthor: Current author.
        ///   - cleanBeforeTimestamp: Cleanup cutoff timestamp.
        ///   - expectedEntityName: Expected entity name for validation.
        /// - Returns: (transaction count, first transaction author, first change entity name)
        func testProcessNewTransactions(
            from authors: [String],
            after lastTimestamp: Date?,
            mergeInto contexts: [NSManagedObjectContext],
            currentAuthor: String?,
            cleanBeforeTimestamp: Date?,
            expectedEntityName: String?) async throws -> (
            count: Int,
            firstAuthor: String?,
            firstEntityName: String?)
        {
            // Fetch transactions before running the workflow.
            let transactions = try fetchTransactions(
                from: authors,
                after: lastTimestamp,
                excludeAuthor: currentAuthor)

            let firstAuthor = transactions.first?.author
            let firstEntityName = transactions.first?.changes?.first?.changedObjectID.entity.name

            // Validate the entity name when an expectation is provided.
            if let expected = expectedEntityName, let actual = firstEntityName {
                guard actual == expected else {
                    throw TestError.unexpectedEntityName(expected: expected, actual: actual)
                }
            }

            // Execute the complete processing pipeline.
            let count = try await processNewTransactions(
                from: authors,
                after: lastTimestamp,
                mergeInto: contexts,
                currentAuthor: currentAuthor,
                cleanBeforeTimestamp: cleanBeforeTimestamp)

            return (count, firstAuthor, firstEntityName)
        }

        /// Test helper for `getLastTransactionTimestamp`.
        /// - Parameter author: Author name.
        /// - Returns: (timestamp exists, timestamp value, is timestamp within allowed age)
        func testGetLastTransactionTimestamp(
            for author: String,
            maxAge: TimeInterval = 10, // Default tolerance: 10 seconds.
        ) -> (hasTimestamp: Bool, timestamp: Date?, isRecent: Bool) {
            let timestamp = getLastTransactionTimestamp(for: author)
            let hasTimestamp = timestamp != nil

            // Ensure the timestamp is within the acceptable range (not older than `maxAge` seconds
            // and not later than now).
            let isRecent: Bool
            if let timestamp {
                let now = Date()
                let earliestValid = now.addingTimeInterval(-maxAge)
                isRecent = timestamp >= earliestValid && timestamp <= now.addingTimeInterval(1)
            } else {
                isRecent = false
            }

            return (hasTimestamp, timestamp, isRecent)
        }

        /// Verify that hooks are triggered as expected.
        /// - Parameters:
        ///   - authors: Authors to process.
        ///   - contexts: Contexts to merge into.
        ///   - expectedEntityName: Expected entity name for the hook.
        ///   - expectedOperation: Expected operation type.
        /// - Returns: (transaction count, first change entity name, first change operation)
        func testHookTrigger(
            from authors: [String],
            after date: Date?,
            mergeInto contexts: [NSManagedObjectContext],
            currentAuthor: String?,
            expectedEntityName: String,
            expectedOperation: HookOperation) async throws -> (
            count: Int,
            entityName: String?,
            operation: HookOperation?)
        {
            let transactions = try fetchTransactions(
                from: authors,
                after: date,
                excludeAuthor: currentAuthor)

            let firstChange = transactions.first?.changes?.first
            let entityName = firstChange?.changedObjectID.entity.name
            let operation = firstChange.map { convertToHookOperation($0.changeType) }

            // Validate entity name and operation type.
            if let entityName, entityName != expectedEntityName {
                throw TestError.unexpectedEntityName(
                    expected: expectedEntityName,
                    actual: entityName)
            }

            if let operation, operation != expectedOperation {
                throw TestError.unexpectedOperation(expected: expectedOperation, actual: operation)
            }

            // Process transactions, which should trigger the hook.
            let count = try await processNewTransactions(
                from: authors,
                after: date,
                mergeInto: contexts,
                currentAuthor: currentAuthor,
                cleanBeforeTimestamp: nil)

            return (count, entityName, operation)
        }
    }

    // MARK: - Test Errors

    enum TestError: Error, CustomStringConvertible {
        case unexpectedCount(expected: Int, actual: Int)
        case unexpectedEntityName(expected: String, actual: String)
        case unexpectedOperation(expected: HookOperation, actual: HookOperation)

        var description: String {
            switch self {
                case let .unexpectedCount(expected, actual):
                    "Expected count \(expected), got \(actual)"
                case let .unexpectedEntityName(expected, actual):
                    "Expected entity '\(expected)', got '\(actual)'"
                case let .unexpectedOperation(expected, actual):
                    "Expected operation \(expected), got \(actual)"
            }
        }
    }
#endif
