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

/// 事务信息，包含时间戳、作者和变更详情
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

/// Hook 上下文，传递给注册的回调函数
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
        author: String
    ) {
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

/// 墓碑信息，记录已删除对象的唯一数据
public struct Tombstone: Sendable, Codable {
    public let attributes: [String: String]
    public let deletedDate: Date?

    public init(attributes: [String: String], deletedDate: Date? = nil) {
        self.attributes = attributes
        self.deletedDate = deletedDate ?? Date()
    }
}

// MARK: - Hook Operation

/// Hook 监听的操作类型
public enum HookOperation: String, Sendable {
    case insert
    case update
    case delete
}

// MARK: - Hook Callback

/// Observer Hook 回调函数类型（用于通知/监听，不影响数据）
public typealias HookCallback = @Sendable (HookContext) async -> Void

// MARK: - Merge Hook

/// Merge Hook 的执行结果
public enum MergeHookResult: Sendable {
    /// 继续执行管道中的下一个 hook
    case goOn
    /// 完成，跳过后续所有 hook（包括默认合并）
    case finish
}

/// Merge Hook 输入参数容器
/// - Note: 使用 @unchecked Sendable 包装非 Sendable 的 Core Data 类型，
///         确保在 TransactionProcessorActor 内部安全使用
public struct MergeHookInput: @unchecked Sendable {
    public let transactions: [NSPersistentHistoryTransaction]
    public let contexts: [NSManagedObjectContext]

    public init(transactions: [NSPersistentHistoryTransaction], contexts: [NSManagedObjectContext]) {
        self.transactions = transactions
        self.contexts = contexts
    }
}

/// Merge Hook 回调函数类型（用于自定义合并逻辑，可能影响数据）
///
/// - Note: 此回调在 TransactionProcessorActor 内执行，管道按注册顺序串行执行。
///
/// - Warning: 如果在 hook 中执行异步操作，**必须使用 `await` 等待完成**，否则无法保证管道顺序。
///
/// ## ✅ 正确用法
/// ```swift
/// await processor.registerMergeHook { input in
///     for context in input.contexts {
///         await context.perform {  // ✅ 有 await
///             // 操作...
///         }
///     }
///     return .goOn
/// }
/// ```
///
/// ## ❌ 错误用法（会破坏管道串行性）
/// ```swift
/// await processor.registerMergeHook { input in
///     context.perform {  // ❌ 没有 await，异步执行不等待
///         // 操作...
///     }
///     return .goOn  // 立即返回，perform 可能还在执行
/// }
///
/// await processor.registerMergeHook { input in
///     Task {  // ❌ 启动独立 Task，不等待
///         await someOperation()
///     }
///     return .goOn
/// }
/// ```
public typealias MergeHookCallback = @Sendable (MergeHookInput) async throws -> MergeHookResult
