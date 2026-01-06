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

/// 事务处理器，负责 fetch、merge、hook、clean
@NSModelActor(disableGenerateInit: true)
public actor TransactionProcessorActor {
    private let hookRegistry: HookRegistryActor

    /// 清理策略（在 Actor 内部管理，线程安全）
    private var cleanStrategy: TransactionPurgePolicy

    public init(container: NSPersistentContainer, hookRegistry: HookRegistryActor, cleanStrategy: TransactionCleanStrategy) {
        self.hookRegistry = hookRegistry

        // 初始化清理策略
        switch cleanStrategy {
        case .none:
            self.cleanStrategy = TransactionCleanStrategyNone()
        case .byDuration:
            self.cleanStrategy = TransactionCleanStrategyByDuration(strategy: cleanStrategy)
        case .byNotification:
            self.cleanStrategy = TransactionCleanStrategyByNotification(strategy: cleanStrategy)
        }

        // 手动初始化 @NSModelActor 提供的属性
        let context = container.newBackgroundContext()
        self.modelExecutor = NSModelObjectContextExecutor(context: context)
        self.modelContainer = container
    }

    /// 主入口：处理新事务
    /// - Parameters:
    ///   - authors: 需要处理的作者列表
    ///   - lastTimestamp: 上次处理的时间戳
    ///   - contexts: 需要合并到的上下文列表
    ///   - currentAuthor: 当前作者（用于排除自己的事务）
    ///   - cleanBeforeTimestamp: 清理该时间戳之前的事务
    /// - Returns: 处理的事务数量
    @discardableResult
    public func processNewTransactions(
        from authors: [String],
        after lastTimestamp: Date?,
        mergeInto contexts: [NSManagedObjectContext],
        currentAuthor: String? = nil,
        cleanBeforeTimestamp: Date? = nil
    ) async throws -> Int {
        // 1. Fetch（排除当前 author）
        let transactions = try fetchTransactions(from: authors, after: lastTimestamp, excludeAuthor: currentAuthor)
        guard !transactions.isEmpty else { return 0 }

        // 2. Trigger hooks
        await triggerHooks(for: transactions)

        // 3. Merge
        try await mergeTransactions(transactions, into: contexts)

        // 4. Clean
        if let cleanTimestamp = cleanBeforeTimestamp {
            _ = try cleanTransactions(before: cleanTimestamp, for: authors)
        }

        return transactions.count
    }

    // MARK: - Fetch

    /// 获取指定作者和时间戳之后的事务（排除当前 author）
    /// - Parameters:
    ///   - authors: 作者列表
    ///   - date: 起始时间戳
    ///   - excludeAuthor: 要排除的 author（通常是当前 author）
    /// - Returns: 事务列表
    /// - Note: 这个方法只能在 Actor 内部调用，测试应使用测试扩展方法
    internal func fetchTransactions(from authors: [String], after date: Date?, excludeAuthor: String? = nil) throws -> [NSPersistentHistoryTransaction] {
        let historyChangeRequest = NSPersistentHistoryChangeRequest.fetchHistory(after: date ?? .distantPast)

        // 配置 fetchRequest - 排除当前 author
        if let fetchRequest = NSPersistentHistoryTransaction.fetchRequest {
            let predicates = authors.compactMap { author -> NSPredicate? in
                // 如果指定了要排除的 author，跳过它
                if let exclude = excludeAuthor, author == exclude {
                    return nil
                }
                return NSPredicate(format: "%K = %@",
                                 #keyPath(NSPersistentHistoryTransaction.author),
                                 author)
            }

            if !predicates.isEmpty {
                fetchRequest.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
                historyChangeRequest.fetchRequest = fetchRequest
            }
        }

        // 执行查询
        let result = try modelContext.execute(historyChangeRequest) as? NSPersistentHistoryResult
        return result?.result as? [NSPersistentHistoryTransaction] ?? []
    }

    // MARK: - Merge

    /// 合并事务到指定的上下文
    /// - Parameters:
    ///   - transactions: 事务列表
    ///   - contexts: 目标上下文列表
    private func mergeTransactions(_ transactions: [NSPersistentHistoryTransaction], into contexts: [NSManagedObjectContext]) async throws {
        for context in contexts {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                context.performAndWait {
                    for transaction in transactions {
                        // 使用 NSPersistentHistoryTransaction 的正确 API
                        guard let changes = transaction.changes else { continue }

                        for change in changes {
                            // 根据变更类型处理
                            switch change.changeType {
                            case .insert, .update:
                                // 对于插入和更新，尝试获取对象并刷新
                                if let object = try? context.existingObject(with: change.changedObjectID) {
                                    context.refresh(object, mergeChanges: true)
                                }
                            case .delete:
                                // 对于删除，确保对象被删除
                                let object = context.object(with: change.changedObjectID)
                                context.delete(object)
                            @unknown default:
                                break
                            }
                        }
                    }
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Hook

    /// 为事务触发 Hook
    /// - Parameter transactions: 事务列表
    private func triggerHooks(for transactions: [NSPersistentHistoryTransaction]) async {
        for transaction in transactions {
            guard let changes = transaction.changes else { continue }

            for change in changes {
                let entityName = change.changedObjectID.entity.name ?? "Unknown"
                let context = HookContext(
                    entityName: entityName,
                    operation: convertToHookOperation(change.changeType),
                    objectID: change.changedObjectID,
                    objectIDURL: change.changedObjectID.uriRepresentation(),
                    tombstone: nil, // TODO: Extract tombstone info if needed
                    timestamp: transaction.timestamp,
                    author: transaction.author ?? "Unknown"
                )

                await hookRegistry.trigger(context: context)
            }
        }
    }

    internal func convertToHookOperation(_ changeType: NSPersistentHistoryChangeType) -> HookOperation {
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

    // MARK: - Clean

    /// 清理指定时间戳之前的事务
    /// - Parameters:
    ///   - timestamp: 清理该时间戳之前的所有事务
    ///   - authors: 只清理这些作者的事务（为 nil 则清理所有）
    /// - Returns: 删除的事务数量
    @discardableResult
    public func cleanTransactions(before timestamp: Date, for authors: [String]?) throws -> Int {
        let deleteRequest = NSPersistentHistoryChangeRequest.deleteHistory(before: timestamp)

        // 配置 fetchRequest - 只删除指定 authors 的事务
        if let authors = authors, !authors.isEmpty {
            if let fetchRequest = NSPersistentHistoryTransaction.fetchRequest {
                let predicates = authors.map { author in
                    NSPredicate(format: "%K = %@",
                               #keyPath(NSPersistentHistoryTransaction.author),
                               author)
                }
                fetchRequest.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
                deleteRequest.fetchRequest = fetchRequest
            }
        }

        // 执行删除
        let result = try modelContext.execute(deleteRequest) as? NSPersistentHistoryResult
        let deletedCount = (result?.result as? Int) ?? 0

        return deletedCount
    }

    /// 清理已被所有作者合并的事务（便捷方法）
    /// - Parameters:
    ///   - author: 当前作者
    ///   - authors: 所有作者列表
    public func cleanTransactions(for author: String, authors: [String]) throws {
        // 这个方法保留用于向后兼容
        // 实际使用时应该使用 cleanTransactions:before:for: 方法
        // TODO: 从外部获取最后的共同时间戳
    }

    // MARK: - Utility

    /// 获取最后的事务时间戳
    /// - Parameter author: 作者名称
    /// - Returns: 最后的事务时间戳
    public func getLastTransactionTimestamp(for author: String) throws -> Date? {
        let transactions = try fetchTransactions(from: [author], after: nil)
        return transactions.last?.timestamp
    }
}
