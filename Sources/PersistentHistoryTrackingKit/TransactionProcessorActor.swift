//
//  TransactionProcessorActor.swift
//  PersistentHistoryTrackingKit
//
//  Created by Claude on 2025-01-06
//  Copyright © 2025 Yang Xu. All rights reserved.
//

@preconcurrency import CoreData
import CoreDataEvolution
import Foundation

/// Transaction processor responsible for fetch, merge, hook, and clean steps.
@NSModelActor(disableGenerateInit: true)
public actor TransactionProcessorActor {
    private let hookRegistry: HookRegistryActor

    /// Cleanup policy managed inside the actor (thread-safe).
    private var cleanStrategy: TransactionPurgePolicy

    /// Timestamp manager.
    private let timestampManager: TransactionTimestampManager

    // MARK: - Merge Hooks (managed inside the same actor to avoid passing non-Sendable types)

    private struct MergeHookItem {
        let id: UUID
        let callback: MergeHookCallback
    }

    private var mergeHooks: [MergeHookItem] = []

    public init(
        container: NSPersistentContainer,
        hookRegistry: HookRegistryActor,
        cleanStrategy: TransactionCleanStrategy,
        timestampManager: consuming TransactionTimestampManager)
    {
        self.hookRegistry = hookRegistry
        self.timestampManager = timestampManager

        // Initialize the cleanup strategy configuration.
        switch cleanStrategy {
            case .none:
                self.cleanStrategy = TransactionCleanStrategyNone()
            case .byDuration:
                self.cleanStrategy = TransactionCleanStrategyByDuration(strategy: cleanStrategy)
            case .byNotification:
                self.cleanStrategy = TransactionCleanStrategyByNotification(strategy: cleanStrategy)
        }

        // Manually initialize the properties that @NSModelActor usually synthesizes.
        let context = container.newBackgroundContext()
        modelExecutor = NSModelObjectContextExecutor(context: context)
        modelContainer = container
    }

    // MARK: - Merge Hook Registration

    /// Register a Merge Hook (pipeline style, allowing custom merge logic).
    /// - Parameters:
    ///   - before: Optional hook ID to insert before; appends to the end if nil.
    ///   - callback: Callback executed within the same actor.
    /// - Returns: The UUID of the hook for later removal.
    @discardableResult
    public func registerMergeHook(
        before hookId: UUID? = nil,
        callback: @escaping MergeHookCallback) -> UUID
    {
        let newId = UUID()
        let newItem = MergeHookItem(id: newId, callback: callback)

        if let beforeId = hookId,
           let index = mergeHooks.firstIndex(where: { $0.id == beforeId })
        {
            mergeHooks.insert(newItem, at: index)
        } else {
            mergeHooks.append(newItem)
        }

        return newId
    }

    /// Remove a specific Merge Hook.
    /// - Parameter hookId: The hook UUID.
    /// - Returns: Whether the hook was removed.
    @discardableResult
    public func removeMergeHook(id hookId: UUID) -> Bool {
        let initialCount = mergeHooks.count
        mergeHooks.removeAll { $0.id == hookId }
        return mergeHooks.count < initialCount
    }

    /// Remove all registered Merge Hooks.
    public func removeAllMergeHooks() {
        mergeHooks.removeAll()
    }

    /// Main entry point for processing new transactions.
    /// - Parameters:
    ///   - authors: Authors whose transactions need to be merged.
    ///   - lastTimestamp: The last processed timestamp.
    ///   - contexts: Target contexts for merging.
    ///   - currentAuthor: Current author (used to exclude self-authored transactions).
    ///   - cleanBeforeTimestamp: Optional timestamp; history before this will be cleaned.
    /// - Returns: Number of transactions processed.
    @discardableResult
    public func processNewTransactions(
        from authors: [String],
        after lastTimestamp: Date?,
        mergeInto contexts: [NSManagedObjectContext],
        currentAuthor: String? = nil,
        cleanBeforeTimestamp: Date? = nil) async throws -> Int
    {
        // 1. Fetch (exclude the current author).
        let transactions = try fetchTransactions(
            from: authors,
            after: lastTimestamp,
            excludeAuthor: currentAuthor)
        guard !transactions.isEmpty else { return 0 }

        // 2. Trigger Observer Hooks (read-only, no data mutations).
        await triggerObserverHooks(for: transactions)

        // 3. Trigger Merge Hooks (pipeline, may mutate data).
        // Runs within the same actor to avoid cross-actor non-Sendable transfers.
        try await triggerMergeHooks(transactions: transactions, contexts: contexts)

        // 4. Run cleanup when a timestamp is provided.
        if let cleanTimestamp = cleanBeforeTimestamp {
            _ = try cleanTransactions(before: cleanTimestamp, for: authors)
        }

        return transactions.count
    }

    /// Process new transactions while automatically managing timestamps (internal helper).
    /// - Parameters:
    ///   - authors: Authors whose transactions need to be merged.
    ///   - lastTimestamp: The last processed timestamp.
    ///   - contexts: Target contexts for merging.
    ///   - currentAuthor: Current author (excluded from fetch and used to update timestamp).
    ///   - batchAuthors: Authors participating in batch work (excluded from cleanup calculation).
    /// - Returns: Number of transactions processed.
    @discardableResult
    func processNewTransactionsWithTimestampManagement(
        from authors: [String],
        after lastTimestamp: Date?,
        mergeInto contexts: [NSManagedObjectContext],
        currentAuthor: String,
        batchAuthors: [String] = []) async throws -> Int
    {
        // 1. Fetch (exclude the current author).
        let transactions = try fetchTransactions(
            from: authors,
            after: lastTimestamp,
            excludeAuthor: currentAuthor)
        guard !transactions.isEmpty else { return 0 }

        // 2. Trigger Observer Hooks (read-only).
        await triggerObserverHooks(for: transactions)

        // 3. Trigger Merge Hooks (pipeline that may mutate data).
        try await triggerMergeHooks(transactions: transactions, contexts: contexts)

        // 4. Update the timestamp for the current author.
        if let newTimestamp = transactions.last?.timestamp {
            timestampManager.updateLastHistoryTransactionTimestamp(
                for: currentAuthor,
                to: newTimestamp)
        }

        // 5. Compute and execute cleanup.
        if let cleanTimestamp = timestampManager.getLastCommonTransactionTimestamp(
            in: authors,
            exclude: batchAuthors)
        {
            _ = try cleanTransactions(before: cleanTimestamp, for: authors)
        }

        return transactions.count
    }

    // MARK: - Fetch

    /// Fetch transactions for the specified authors after the timestamp (excluding the current author).
    /// - Parameters:
    ///   - authors: List of authors.
    ///   - date: Starting timestamp.
    ///   - excludeAuthor: Author to exclude (typically the caller/ current author).
    /// - Returns: A list of transactions.
    /// - Note: This method must be called inside the actor; tests should use the dedicated extensions.
    func fetchTransactions(
        from authors: [String],
        after date: Date?,
        excludeAuthor: String? = nil) throws -> [NSPersistentHistoryTransaction]
    {
        let historyChangeRequest = NSPersistentHistoryChangeRequest
            .fetchHistory(after: date ?? .distantPast)

        // Configure fetchRequest and skip the current author.
        if let fetchRequest = NSPersistentHistoryTransaction.fetchRequest {
            let predicates = authors.compactMap { author -> NSPredicate? in
                // Skip the author if it matches the exclude target.
                if let exclude = excludeAuthor, author == exclude {
                    return nil
                }
                return NSPredicate(
                    format: "%K = %@",
                    #keyPath(NSPersistentHistoryTransaction.author),
                    author)
            }

            if !predicates.isEmpty {
                fetchRequest
                    .predicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
                historyChangeRequest.fetchRequest = fetchRequest
            }
        }

        // Execute the fetch request.
        let result = try modelContext.execute(historyChangeRequest) as? NSPersistentHistoryResult
        return result?.result as? [NSPersistentHistoryTransaction] ?? []
    }

    // MARK: - Merge

    /// Merge transactions into the provided contexts.
    /// - Parameters:
    ///   - transactions: Transactions to merge.
    ///   - contexts: Target contexts.
    /// - Note: Leverages Core Data APIs that handle thread-safety and async dispatch.
    private func mergeTransactions(
        _ transactions: [NSPersistentHistoryTransaction],
        into contexts: [NSManagedObjectContext]) async throws
    {
        // Use the standard Core Data API to merge all transactions into each context.
        // NSManagedObjectContext.mergeChanges automatically handles coordination.
        for transaction in transactions {
            let userInfo = transaction.objectIDNotification().userInfo ?? [:]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: userInfo, into: contexts)
        }
    }

    // MARK: - Observer Hook

    /// Trigger Observer Hooks for the given transactions (read-only notifications).
    /// - Parameter transactions: Transactions to inspect.
    private func triggerObserverHooks(for transactions: [NSPersistentHistoryTransaction]) async {
        for transaction in transactions {
            guard let changes = transaction.changes else { continue }

            for change in changes {
                let entityName = change.changedObjectID.entity.name ?? "Unknown"

                // Extract tombstone data (only delete operations provide tombstones).
                let tombstone = extractTombstone(from: change, timestamp: transaction.timestamp)

                let context = HookContext(
                    entityName: entityName,
                    operation: convertToHookOperation(change.changeType),
                    objectID: change.changedObjectID,
                    objectIDURL: change.changedObjectID.uriRepresentation(),
                    tombstone: tombstone,
                    timestamp: transaction.timestamp,
                    author: transaction.author ?? "Unknown")

                await hookRegistry.triggerObserver(context: context)
            }
        }
    }

    /// Extract tombstone data from an NSPersistentHistoryChange.
    /// - Parameters:
    ///   - change: History change record.
    ///   - timestamp: Transaction timestamp.
    /// - Returns: Tombstone data (non-nil only for delete operations).
    private func extractTombstone(
        from change: NSPersistentHistoryChange,
        timestamp: Date) -> Tombstone?
    {
        // Only delete operations produce tombstones.
        guard change.changeType == .delete else { return nil }

        // Grab Core Data's tombstone dictionary.
        guard let rawTombstone = change.tombstone else { return nil }

        // Convert [AnyHashable: Any] to [String: String].
        var attributes: [String: String] = [:]
        for (key, value) in rawTombstone {
            // Convert the key into a String.
            let keyString: String = if let stringKey = key as? String {
                stringKey
            } else {
                String(describing: key)
            }

            // Convert values into string representations when possible.
            if let stringValue = value as? String {
                attributes[keyString] = stringValue
            } else if let urlValue = value as? URL {
                attributes[keyString] = urlValue.absoluteString
            } else if let uuidValue = value as? UUID {
                attributes[keyString] = uuidValue.uuidString
            } else if let dateValue = value as? Date {
                attributes[keyString] = ISO8601DateFormatter().string(from: dateValue)
            } else if let numberValue = value as? NSNumber {
                attributes[keyString] = numberValue.stringValue
            } else {
                // Fallback to `description` for any other type.
                attributes[keyString] = String(describing: value)
            }
        }

        return Tombstone(attributes: attributes, deletedDate: timestamp)
    }

    func convertToHookOperation(_ changeType: NSPersistentHistoryChangeType) -> HookOperation {
        switch changeType {
            case .insert:
                return .insert
            case .update:
                return .update
            case .delete:
                return .delete
            @unknown default:
                return .update
        }
    }

    // MARK: - Merge Hook

    /// Run the Merge Hook pipeline.
    /// - Parameters:
    ///   - transactions: Transactions flowing through the pipeline.
    ///   - contexts: Target contexts.
    /// - Note: All operations execute inside the same actor, so there are no concurrency concerns.
    private func triggerMergeHooks(
        transactions: [NSPersistentHistoryTransaction],
        contexts: [NSManagedObjectContext]) async throws
    {
        let input = MergeHookInput(transactions: transactions, contexts: contexts)

        // Execute each merge hook sequentially.
        for item in mergeHooks {
            let result = try await item.callback(input)
            if result == .finish {
                return // A hook handled the work; skip the default merge.
            }
        }

        // All hooks returned .goOn (or none were registered), so perform the default merge.
        try await mergeTransactions(transactions, into: contexts)
    }

    // MARK: - Clean

    /// Delete transactions before the specified timestamp.
    /// - Parameters:
    ///   - timestamp: Remove history before this timestamp.
    ///   - authors: Limit cleanup to these authors (nil removes all authors).
    /// - Returns: Number of deleted transactions.
    @discardableResult
    public func cleanTransactions(before timestamp: Date, for authors: [String]?) throws -> Int {
        let deleteRequest = NSPersistentHistoryChangeRequest.deleteHistory(before: timestamp)

        // Configure fetchRequest to delete only the specified authors' transactions.
        if let authors, !authors.isEmpty {
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

    // MARK: - Utility

    /// Retrieve the last transaction timestamp for an author.
    /// - Parameter author: The author's name.
    /// - Returns: The latest transaction timestamp.
    public func getLastTransactionTimestamp(for author: String) throws -> Date? {
        let transactions = try fetchTransactions(from: [author], after: nil)
        return transactions.last?.timestamp
    }
}
