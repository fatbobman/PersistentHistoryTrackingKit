//
//  HookRegistryActor.swift
//  PersistentHistoryTrackingKit
//
//  Created by Claude on 2025-01-06
//  Copyright © 2025 Yang Xu. All rights reserved.
//

import Foundation

/// Hook 注册表，管理所有 Hook 回调
public actor HookRegistryActor {
    private var hooks: [String: [HookCallback]] = [:]

    public init() {}

    /// 注册 Hook 回调
    /// - Parameters:
    ///   - entityName: 实体名称
    ///   - operation: 操作类型
    ///   - callback: 回调函数
    public func register(
        entityName: String,
        operation: HookOperation,
        callback: @escaping HookCallback
    ) {
        let key = makeKey(entityName: entityName, operation: operation)
        if hooks[key] == nil {
            hooks[key] = []
        }
        hooks[key]?.append(callback)
    }

    /// 移除 Hook 回调
    /// - Parameters:
    ///   - entityName: 实体名称
    ///   - operation: 操作类型
    public func remove(entityName: String, operation: HookOperation) {
        let key = makeKey(entityName: entityName, operation: operation)
        hooks.removeValue(forKey: key)
    }

    /// 触发 Hook
    /// - Parameter context: Hook 上下文
    public func trigger(context: HookContext) {
        let key = makeKey(entityName: context.entityName, operation: context.operation)
        if let callbacks = hooks[key] {
            for callback in callbacks {
                callback(context)
            }
        }
    }

    /// 清除所有 Hook
    public func removeAll() {
        hooks.removeAll()
    }

    private func makeKey(entityName: String, operation: HookOperation) -> String {
        "\(entityName).\(operation.rawValue)"
    }
}
