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

/// Hook 回调函数类型
public typealias HookCallback = @Sendable (HookContext) async -> Void
