//
//  HookRegistryActor.swift
//  PersistentHistoryTrackingKit
//
//  Created by Claude on 2025-01-06
//  Copyright © 2025 Yang Xu. All rights reserved.
//

import CoreData
import Foundation

/// Hook 注册表，管理 Observer Hook（只读通知）
/// - Note: Merge Hook 已移至 TransactionProcessorActor，因为需要直接操作非 Sendable 的 Core Data 类型
public actor HookRegistryActor {
    // MARK: - Observer Hooks（用于通知/监听，不影响数据）

    private var observerHooks: [String: [HookCallback]] = [:]

    /// 注册 Observer Hook（用于通知/监听，不影响数据）
    /// - Parameters:
    ///   - entityName: 实体名称
    ///   - operation: 操作类型
    ///   - callback: 回调函数
    public func registerObserver(
        entityName: String,
        operation: HookOperation,
        callback: @escaping HookCallback)
    {
        let key = makeKey(entityName: entityName, operation: operation)
        if observerHooks[key] == nil {
            observerHooks[key] = []
        }
        observerHooks[key]?.append(callback)
    }

    /// 移除 Observer Hook
    /// - Parameters:
    ///   - entityName: 实体名称
    ///   - operation: 操作类型
    public func removeObserver(entityName: String, operation: HookOperation) {
        let key = makeKey(entityName: entityName, operation: operation)
        observerHooks.removeValue(forKey: key)
    }

    /// 触发 Observer Hook
    /// - Parameter context: Hook 上下文
    public func triggerObserver(context: HookContext) async {
        let key = makeKey(entityName: context.entityName, operation: context.operation)
        if let callbacks = observerHooks[key] {
            for callback in callbacks {
                await callback(context)
            }
        }
    }

    // MARK: - Utility

    /// 清除所有 Observer Hook
    public func removeAllObservers() {
        observerHooks.removeAll()
    }

    private func makeKey(entityName: String, operation: HookOperation) -> String {
        "\(entityName).\(operation.rawValue)"
    }
}

// MARK: - Backward Compatibility

extension HookRegistryActor {
    /// 注册 Hook 回调（向后兼容，使用 registerObserver）
    @available(*, deprecated, renamed: "registerObserver(entityName:operation:callback:)")
    public func register(
        entityName: String,
        operation: HookOperation,
        callback: @escaping HookCallback)
    {
        registerObserver(entityName: entityName, operation: operation, callback: callback)
    }

    /// 移除 Hook 回调（向后兼容，使用 removeObserver）
    @available(*, deprecated, renamed: "removeObserver(entityName:operation:)")
    public func remove(entityName: String, operation: HookOperation) {
        removeObserver(entityName: entityName, operation: operation)
    }

    /// 触发 Hook（向后兼容，使用 triggerObserver）
    @available(*, deprecated, renamed: "triggerObserver(context:)")
    public func trigger(context: HookContext) async {
        await triggerObserver(context: context)
    }

    /// 清除所有 Hook（向后兼容）
    @available(*, deprecated, renamed: "removeAllObservers()")
    public func removeAll() {
        removeAllObservers()
    }
}
