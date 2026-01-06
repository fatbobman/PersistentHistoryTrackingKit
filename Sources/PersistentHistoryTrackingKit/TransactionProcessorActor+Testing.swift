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
/// 测试扩展：在 Actor 内部执行测试逻辑，避免 NSPersistentHistoryTransaction 跨越 Actor 边界
extension TransactionProcessorActor {

    /// 测试 fetchTransactions 是否正确排除指定 author
    /// - Parameters:
    ///   - authors: 要获取的作者列表
    ///   - date: 起始时间戳
    ///   - excludeAuthor: 要排除的 author
    /// - Returns: (事务数量, 是否所有事务都不包含被排除的 author)
    public func testFetchTransactionsExcludesAuthor(
        from authors: [String],
        after date: Date?,
        excludeAuthor: String?
    ) throws -> (count: Int, allExcluded: Bool) {
        let transactions = try fetchTransactions(from: authors, after: date, excludeAuthor: excludeAuthor)

        // 验证所有事务都不包含被排除的 author
        let allExcluded: Bool
        if let excludeAuthor = excludeAuthor {
            allExcluded = transactions.allSatisfy { $0.author != excludeAuthor }
        } else {
            allExcluded = true
        }

        return (transactions.count, allExcluded)
    }

    /// 测试 cleanTransactions 的删除结果
    /// - Parameters:
    ///   - timestamp: 清理该时间戳之前的事务
    ///   - authors: 要清理的作者列表
    ///   - expectedBefore: 清理前预期的事务数量（用于验证）
    /// - Returns: (删除的事务数量, 清理后剩余的事务数量)
    public func testCleanTransactions(
        before timestamp: Date,
        for authors: [String],
        expectedBefore: Int?
    ) throws -> (deletedCount: Int, remainingCount: Int) {
        // 清理前获取事务数量
        let beforeTransactions = try fetchTransactions(from: authors, after: nil)
        let beforeCount = beforeTransactions.count

        // 如果提供了预期值，验证它
        if let expected = expectedBefore {
            guard beforeCount == expected else {
                throw TestError.unexpectedCount(expected: expected, actual: beforeCount)
            }
        }

        // 执行清理
        let deletedCount = try cleanTransactions(before: timestamp, for: authors)

        // 清理后获取剩余事务数量
        let afterTransactions = try fetchTransactions(from: authors, after: nil)
        let remainingCount = afterTransactions.count

        return (deletedCount, remainingCount)
    }

    /// 测试 processNewTransactions 完整流程
    /// - Parameters:
    ///   - authors: 要处理的作者列表
    ///   - lastTimestamp: 上次处理的时间戳
    ///   - contexts: 要合并到的上下文列表
    ///   - currentAuthor: 当前作者
    ///   - cleanBeforeTimestamp: 清理时间戳
    ///   - expectedEntityName: 预期的实体名称（用于验证）
    /// - Returns: (处理的事务数量, 第一个事务的作者, 第一个变更的实体名称)
    public func testProcessNewTransactions(
        from authors: [String],
        after lastTimestamp: Date?,
        mergeInto contexts: [NSManagedObjectContext],
        currentAuthor: String?,
        cleanBeforeTimestamp: Date?,
        expectedEntityName: String?
    ) async throws -> (count: Int, firstAuthor: String?, firstEntityName: String?) {
        // 获取处理前的事务信息
        let transactions = try fetchTransactions(from: authors, after: lastTimestamp, excludeAuthor: currentAuthor)

        let firstAuthor = transactions.first?.author
        let firstEntityName = transactions.first?.changes?.first?.changedObjectID.entity.name

        // 如果提供了预期的实体名称，验证它
        if let expected = expectedEntityName, let actual = firstEntityName {
            guard actual == expected else {
                throw TestError.unexpectedEntityName(expected: expected, actual: actual)
            }
        }

        // 执行完整的处理流程
        let count = try await processNewTransactions(
            from: authors,
            after: lastTimestamp,
            mergeInto: contexts,
            currentAuthor: currentAuthor,
            cleanBeforeTimestamp: cleanBeforeTimestamp
        )

        return (count, firstAuthor, firstEntityName)
    }

    /// 测试 getLastTransactionTimestamp
    /// - Parameter author: 作者名称
    /// - Returns: (是否存在时间戳, 时间戳值, 是否在合理范围内)
    public func testGetLastTransactionTimestamp(
        for author: String,
        maxAge: TimeInterval = 10 // 默认 10 秒内
    ) throws -> (hasTimestamp: Bool, timestamp: Date?, isRecent: Bool) {
        let timestamp = try getLastTransactionTimestamp(for: author)
        let hasTimestamp = timestamp != nil

        // 验证时间戳是否在合理范围内（不早于 maxAge 秒前，不晚于现在）
        let isRecent: Bool
        if let timestamp = timestamp {
            let now = Date()
            let earliestValid = now.addingTimeInterval(-maxAge)
            isRecent = timestamp >= earliestValid && timestamp <= now.addingTimeInterval(1)
        } else {
            isRecent = false
        }

        return (hasTimestamp, timestamp, isRecent)
    }

    /// 测试 Hook 是否被正确触发
    /// - Parameters:
    ///   - authors: 要处理的作者列表
    ///   - contexts: 要合并到的上下文列表
    ///   - expectedEntityName: 预期触发 Hook 的实体名称
    ///   - expectedOperation: 预期的操作类型
    /// - Returns: (处理的事务数量, 第一个变更的详细信息)
    public func testHookTrigger(
        from authors: [String],
        after date: Date?,
        mergeInto contexts: [NSManagedObjectContext],
        currentAuthor: String?,
        expectedEntityName: String,
        expectedOperation: HookOperation
    ) async throws -> (count: Int, entityName: String?, operation: HookOperation?) {
        let transactions = try fetchTransactions(from: authors, after: date, excludeAuthor: currentAuthor)

        let firstChange = transactions.first?.changes?.first
        let entityName = firstChange?.changedObjectID.entity.name
        let operation = firstChange.map { convertToHookOperation($0.changeType) }

        // 验证实体名称和操作类型
        if let entityName = entityName, entityName != expectedEntityName {
            throw TestError.unexpectedEntityName(expected: expectedEntityName, actual: entityName)
        }

        if let operation = operation, operation != expectedOperation {
            throw TestError.unexpectedOperation(expected: expectedOperation, actual: operation)
        }

        // 执行处理（会触发 Hook）
        let count = try await processNewTransactions(
            from: authors,
            after: date,
            mergeInto: contexts,
            currentAuthor: currentAuthor,
            cleanBeforeTimestamp: nil
        )

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
        case .unexpectedCount(let expected, let actual):
            return "Expected count \(expected), got \(actual)"
        case .unexpectedEntityName(let expected, let actual):
            return "Expected entity '\(expected)', got '\(actual)'"
        case .unexpectedOperation(let expected, let actual):
            return "Expected operation \(expected), got \(actual)"
        }
    }
}
#endif
