//
//  ManualCleanerActor.swift
//  PersistentHistoryTrackingKit
//
//  Created by Claude on 2025-01-06
//  Copyright © 2025 Yang Xu. All rights reserved.
//

@preconcurrency import CoreData
import CoreDataEvolution
import Foundation

/// 手动清理 Actor，用于外部手动触发 Transaction 清理
///
/// 使用示例：
/// ```swift
/// let kit = PersistentHistoryTrackingKit(...)
/// let cleaner = kit.cleanerBuilder()
///
/// // 在需要清理的地方（比如 app 进入后台）
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
        logLevel: Int)
    {
        self.authors = authors
        self.logger = logger
        self.logLevel = logLevel
        self.userDefaults = userDefaults
        self.uniqueString = uniqueString

        // 手动初始化 @NSModelActor 提供的属性
        let context = container.newBackgroundContext()
        modelExecutor = NSModelObjectContextExecutor(context: context)
        modelContainer = container
    }

    /// 执行清理任务
    ///
    /// 清理逻辑：
    /// 1. 获取所有 authors 的最后时间戳
    /// 2. 找到最小的时间戳（最后的共同时间戳）
    /// 3. 清理该时间戳之前的所有 transactions
    public func clean() {
        do {
            // 1. 获取所有 authors 的最后共同时间戳
            guard let cleanTimestamp = getLastCommonTimestamp() else {
                log(.info, level: 2, "No common timestamp found, skipping clean")
                return
            }

            // 2. 执行清理
            let deletedCount = try cleanTransactions(before: cleanTimestamp, for: authors)
            log(.info, level: 2, "Cleaned \(deletedCount) transactions before \(cleanTimestamp)")
        } catch {
            log(.error, level: 1, "Clean error: \(error.localizedDescription)")
        }
    }

    /// 获取所有 authors 的最后共同时间戳（取最小值）
    private func getLastCommonTimestamp() -> Date? {
        let timestamps = authors.compactMap { author -> Date? in
            let key = uniqueString + author
            return userDefaults.object(forKey: key) as? Date
        }

        // 如果没有任何时间戳，返回 nil
        guard !timestamps.isEmpty else { return nil }

        // 返回最小的时间戳（最后的共同时间戳）
        return timestamps.min()
    }

    /// 清理指定时间戳之前的事务
    /// - Parameters:
    ///   - timestamp: 清理该时间戳之前的所有事务
    ///   - authors: 只清理这些作者的事务
    /// - Returns: 删除的事务数量
    @discardableResult
    private func cleanTransactions(before timestamp: Date, for authors: [String]) throws -> Int {
        let deleteRequest = NSPersistentHistoryChangeRequest.deleteHistory(before: timestamp)

        // 配置 fetchRequest - 只删除指定 authors 的事务
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

        // 执行删除
        let result = try modelContext.execute(deleteRequest) as? NSPersistentHistoryResult
        let deletedCount = (result?.result as? Int) ?? 0

        return deletedCount
    }

    /// 记录日志
    private func log(_ type: PersistentHistoryTrackingKitLogType, level: Int, _ message: String) {
        guard level <= logLevel else { return }
        logger.log(type: type, message: message)
    }
}
