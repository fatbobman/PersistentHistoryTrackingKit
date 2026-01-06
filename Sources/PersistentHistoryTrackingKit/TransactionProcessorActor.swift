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

    /// 时间戳管理器
    private let timestampManager: TransactionTimestampManager

    // MARK: - Merge Hooks（在同一 Actor 内管理，避免跨 Actor 传递非 Sendable 类型）

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
        modelExecutor = NSModelObjectContextExecutor(context: context)
        modelContainer = container
    }

    // MARK: - Merge Hook 注册

    /// 注册 Merge Hook（管道模式，可自定义合并逻辑）
    /// - Parameters:
    ///   - before: 可选，插入到此 hook 之前；如果为 nil，添加到末尾
    ///   - callback: 回调函数，在同一 Actor 内执行
    /// - Returns: 该 hook 的 UUID，用于后续移除
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

    /// 移除指定的 Merge Hook
    /// - Parameter hookId: hook 的 UUID
    /// - Returns: 是否成功移除
    @discardableResult
    public func removeMergeHook(id hookId: UUID) -> Bool {
        let initialCount = mergeHooks.count
        mergeHooks.removeAll { $0.id == hookId }
        return mergeHooks.count < initialCount
    }

    /// 移除所有 Merge Hook
    public func removeAllMergeHooks() {
        mergeHooks.removeAll()
    }

    /// 主入口：处理新事务
    /// - Parameters:
    ///   - authors: 需要处理的作者列表
    ///   - lastTimestamp: 上次处理的时间戳
    ///   - contexts: 需要合并到的上下文列表
    ///   - currentAuthor: 当前作者（用于排除自己的事务）
    ///   - cleanBeforeTimestamp: 清理该时间戳之前的事务（可选）
    /// - Returns: 处理的事务数量
    @discardableResult
    public func processNewTransactions(
        from authors: [String],
        after lastTimestamp: Date?,
        mergeInto contexts: [NSManagedObjectContext],
        currentAuthor: String? = nil,
        cleanBeforeTimestamp: Date? = nil) async throws -> Int
    {
        // 1. Fetch（排除当前 author）
        let transactions = try fetchTransactions(
            from: authors,
            after: lastTimestamp,
            excludeAuthor: currentAuthor)
        guard !transactions.isEmpty else { return 0 }

        // 2. Trigger Observer Hooks（不影响数据）
        await triggerObserverHooks(for: transactions)

        // 3. Trigger Merge Hooks（管道模式，可能影响数据）
        // 在同一 Actor 内执行，避免跨 Actor 传递非 Sendable 类型
        try await triggerMergeHooks(transactions: transactions, contexts: contexts)

        // 4. Clean（如果指定了清理时间戳）
        if let cleanTimestamp = cleanBeforeTimestamp {
            _ = try cleanTransactions(before: cleanTimestamp, for: authors)
        }

        return transactions.count
    }

    /// 处理新事务并自动管理时间戳（内部使用）
    /// - Parameters:
    ///   - authors: 需要处理的作者列表
    ///   - lastTimestamp: 上次处理的时间戳
    ///   - contexts: 需要合并到的上下文列表
    ///   - currentAuthor: 当前作者（用于排除自己的事务和更新时间戳）
    ///   - batchAuthors: 批量操作的 authors（从清理计算中排除）
    /// - Returns: 处理的事务数量
    @discardableResult
    internal func processNewTransactionsWithTimestampManagement(
        from authors: [String],
        after lastTimestamp: Date?,
        mergeInto contexts: [NSManagedObjectContext],
        currentAuthor: String,
        batchAuthors: [String] = []) async throws -> Int
    {
        // 1. Fetch（排除当前 author）
        let transactions = try fetchTransactions(
            from: authors,
            after: lastTimestamp,
            excludeAuthor: currentAuthor)
        guard !transactions.isEmpty else { return 0 }

        // 2. Trigger Observer Hooks（不影响数据）
        await triggerObserverHooks(for: transactions)

        // 3. Trigger Merge Hooks（管道模式，可能影响数据）
        try await triggerMergeHooks(transactions: transactions, contexts: contexts)

        // 4. 更新当前 author 的时间戳
        if let newTimestamp = transactions.last?.timestamp {
            timestampManager.updateLastHistoryTransactionTimestamp(
                for: currentAuthor,
                to: newTimestamp
            )
        }

        // 5. 计算并执行清理
        if let cleanTimestamp = timestampManager.getLastCommonTransactionTimestamp(
            in: authors,
            exclude: batchAuthors
        ) {
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
    func fetchTransactions(
        from authors: [String],
        after date: Date?,
        excludeAuthor: String? = nil) throws -> [NSPersistentHistoryTransaction]
    {
        let historyChangeRequest = NSPersistentHistoryChangeRequest
            .fetchHistory(after: date ?? .distantPast)

        // 配置 fetchRequest - 排除当前 author
        if let fetchRequest = NSPersistentHistoryTransaction.fetchRequest {
            let predicates = authors.compactMap { author -> NSPredicate? in
                // 如果指定了要排除的 author，跳过它
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

        // 执行查询
        let result = try modelContext.execute(historyChangeRequest) as? NSPersistentHistoryResult
        return result?.result as? [NSPersistentHistoryTransaction] ?? []
    }

    // MARK: - Merge

    /// 合并事务到指定的上下文
    /// - Parameters:
    ///   - transactions: 事务列表
    ///   - contexts: 目标上下文列表
    /// - Note: 使用 Core Data 标准 API，内部自动处理线程安全和异步调度
    private func mergeTransactions(
        _ transactions: [NSPersistentHistoryTransaction],
        into contexts: [NSManagedObjectContext]) async throws
    {
        // 使用 Core Data 标准 API：一次性合并所有事务到所有上下文
        // NSManagedObjectContext.mergeChanges 会自动处理：
        for transaction in transactions {
            let userInfo = transaction.objectIDNotification().userInfo ?? [:]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: userInfo, into: contexts)
        }
    }

    // MARK: - Observer Hook

    /// 为事务触发 Observer Hook（只读通知）
    /// - Parameter transactions: 事务列表
    private func triggerObserverHooks(for transactions: [NSPersistentHistoryTransaction]) async {
        for transaction in transactions {
            guard let changes = transaction.changes else { continue }

            for change in changes {
                let entityName = change.changedObjectID.entity.name ?? "Unknown"

                // 提取墓碑数据（仅删除操作有墓碑）
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

    /// 从 NSPersistentHistoryChange 提取墓碑数据
    /// - Parameters:
    ///   - change: 历史变更记录
    ///   - timestamp: 事务时间戳
    /// - Returns: 墓碑数据（仅删除操作返回非 nil）
    private func extractTombstone(
        from change: NSPersistentHistoryChange,
        timestamp: Date) -> Tombstone?
    {
        // 只有删除操作才有墓碑
        guard change.changeType == .delete else { return nil }

        // 获取 Core Data 的 tombstone 字典
        guard let rawTombstone = change.tombstone else { return nil }

        // 将 [AnyHashable: Any] 转换为 [String: String]
        var attributes: [String: String] = [:]
        for (key, value) in rawTombstone {
            // key 转换为 String
            let keyString: String = if let stringKey = key as? String {
                stringKey
            } else {
                String(describing: key)
            }

            // 尝试将值转换为字符串表示
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
                // 其他类型使用 description
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

    /// 触发 Merge Hook 管道
    /// - Parameters:
    ///   - transactions: 事务列表
    ///   - contexts: 目标上下文列表
    /// - Note: 所有操作在同一 Actor 内执行，无并发安全问题
    private func triggerMergeHooks(
        transactions: [NSPersistentHistoryTransaction],
        contexts: [NSManagedObjectContext]) async throws
    {
        let input = MergeHookInput(transactions: transactions, contexts: contexts)

        // 依次执行 merge hooks
        for item in mergeHooks {
            let result = try await item.callback(input)
            if result == .finish {
                return // 某个 hook 已处理，跳过默认合并
            }
        }

        // 所有 hook 都返回 .goOn（或无 hook），执行默认合并
        try await mergeTransactions(transactions, into: contexts)
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
