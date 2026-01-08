//
//  HookTypes.swift
//  PersistentHistoryTrackingKit
//
//  Created by Claude on 2025-01-06
//  Copyright © 2025 Yang Xu. All rights reserved.
//

import CoreData
import Foundation

// MARK: - Transaction Info

/// Transaction information containing timestamp, author, and change details
public struct TransactionInfo: Sendable, Codable {
    public let timestamp: Date
    public let author: String
    public let changes: [ChangeInfo]

    public init(timestamp: Date, author: String, changes: [ChangeInfo]) {
        self.timestamp = timestamp
        self.author = author
        self.changes = changes
    }

    public struct ChangeInfo: Sendable, Codable {
        public let objectID: URL
        public let entityName: String
        public let changeType: ChangeType

        public init(objectID: URL, entityName: String, changeType: ChangeType) {
            self.objectID = objectID
            self.entityName = entityName
            self.changeType = changeType
        }

        public enum ChangeType: Int, Codable, Sendable {
            case insert = 0
            case update = 1
            case delete = 2
        }
    }
}

// MARK: - Hook Context

/// Hook context passed to registered callback functions
public struct HookContext: Sendable {
    public let entityName: String
    public let operation: HookOperation
    public let objectID: NSManagedObjectID
    public let objectIDURL: URL
    public let tombstone: Tombstone?
    public let timestamp: Date
    public let author: String

    public init(
        entityName: String,
        operation: HookOperation,
        objectID: NSManagedObjectID,
        objectIDURL: URL,
        tombstone: Tombstone?,
        timestamp: Date,
        author: String)
    {
        self.entityName = entityName
        self.operation = operation
        self.objectID = objectID
        self.objectIDURL = objectIDURL
        self.tombstone = tombstone
        self.timestamp = timestamp
        self.author = author
    }
}

// MARK: - Tombstone

/// Tombstone information recording unique data of deleted objects
public struct Tombstone: Sendable, Codable {
    public let attributes: [String: String]
    public let deletedDate: Date?

    public init(attributes: [String: String], deletedDate: Date? = nil) {
        self.attributes = attributes
        self.deletedDate = deletedDate ?? Date()
    }
}

// MARK: - Hook Operation

/// Operation types for Hook monitoring
public enum HookOperation: String, Sendable {
    case insert
    case update
    case delete
}

// MARK: - Hook Callback

/// Observer Hook callback function type (for notification/monitoring, does not modify data)
/// - Note: Receives an array of contexts grouped by transaction, entity, and operation.
///         All contexts in the array share the same transaction, entity name, and operation type.
public typealias HookCallback = @Sendable ([HookContext]) async -> Void

// MARK: - Merge Hook

/// Execution result of Merge Hook
public enum MergeHookResult: Sendable {
    /// Continue to the next hook in the pipeline
    case goOn
    /// Finish, skipping all remaining hooks (including default merge)
    case finish
}

/// Merge Hook input parameter container
/// - Note: Uses @unchecked Sendable to wrap non-Sendable Core Data types,
///         ensuring safe usage within TransactionProcessorActor
public struct MergeHookInput: @unchecked Sendable {
    public let transactions: [NSPersistentHistoryTransaction]
    public let contexts: [NSManagedObjectContext]

    public init(
        transactions: [NSPersistentHistoryTransaction],
        contexts: [NSManagedObjectContext])
    {
        self.transactions = transactions
        self.contexts = contexts
    }
}

/// Merge Hook callback function type (for custom merge logic, may modify data)
///
/// - Note: This callback executes within TransactionProcessorActor, and the pipeline runs serially
/// in registration order.
///
/// - Warning: If performing async operations in the hook, **you must use `await` to wait for
/// completion**,
///            otherwise pipeline order cannot be guaranteed.
///
/// ## ✅ Correct Usage
/// ```swift
/// await processor.registerMergeHook { input in
///     for context in input.contexts {
///         await context.perform {  // ✅ Has await
///             // Operations...
///         }
///     }
///     return .goOn
/// }
/// ```
///
/// ## ❌ Incorrect Usage (breaks pipeline seriality)
/// ```swift
/// await processor.registerMergeHook { input in
///     context.perform {  // ❌ No await, async execution without waiting
///         // Operations...
///     }
///     return .goOn  // Returns immediately, perform may still be executing
/// }
///
/// await processor.registerMergeHook { input in
///     Task {  // ❌ Launches independent Task, no waiting
///         await someOperation()
///     }
///     return .goOn
/// }
/// ```
public typealias MergeHookCallback = @Sendable (MergeHookInput) async throws -> MergeHookResult
