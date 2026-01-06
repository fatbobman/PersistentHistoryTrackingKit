//
//  HookRegistryActor.swift
//  PersistentHistoryTrackingKit
//
//  Created by Claude on 2025-01-06
//  Copyright © 2025 Yang Xu. All rights reserved.
//

import CoreData
import Foundation

/// Hook registry for managing Observer Hooks (read-only notifications)
/// - Note: Merge Hooks have been moved to TransactionProcessorActor because they need direct access to non-Sendable Core Data types
public actor HookRegistryActor {
    // MARK: - Observer Hooks (for notification/monitoring, do not modify data)

    private var observerHooks: [String: [HookCallback]] = [:]

    /// Register an Observer Hook (for notification/monitoring, does not modify data)
    /// - Parameters:
    ///   - entityName: The name of the entity
    ///   - operation: The type of operation
    ///   - callback: The callback function to execute
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

    /// Remove Observer Hooks for a specific entity and operation
    /// - Parameters:
    ///   - entityName: The name of the entity
    ///   - operation: The type of operation
    public func removeObserver(entityName: String, operation: HookOperation) {
        let key = makeKey(entityName: entityName, operation: operation)
        observerHooks.removeValue(forKey: key)
    }

    /// Trigger Observer Hooks with the given context
    /// - Parameter context: The hook context containing transaction information
    public func triggerObserver(context: HookContext) async {
        let key = makeKey(entityName: context.entityName, operation: context.operation)
        if let callbacks = observerHooks[key] {
            for callback in callbacks {
                await callback(context)
            }
        }
    }

    // MARK: - Utility

    /// Remove all registered Observer Hooks
    public func removeAllObservers() {
        observerHooks.removeAll()
    }

    private func makeKey(entityName: String, operation: HookOperation) -> String {
        "\(entityName).\(operation.rawValue)"
    }
}

