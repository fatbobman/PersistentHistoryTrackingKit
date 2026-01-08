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
public actor HookRegistryActor: ObserverHookProtocol {
    // MARK: - Observer Hooks (for notification/monitoring, do not modify data)

    /// Internal structure to hold observer hook with UUID
    private struct ObserverHookItem {
        let id: UUID
        let callback: HookCallback
    }

    /// Observer hooks grouped by entity + operation key
    private var observerHooks: [String: [ObserverHookItem]] = [:]

    /// Reverse mapping from UUID to key for fast lookup
    private var hookIdToKey: [UUID: String] = [:]

    /// Register an Observer Hook (for notification/monitoring, does not modify data)
    /// - Parameters:
    ///   - entityName: The name of the entity
    ///   - operation: The type of operation
    ///   - callback: The callback function to execute
    /// - Returns: UUID that can be used to remove this specific hook
    @discardableResult
    public func registerObserver(
        entityName: String,
        operation: HookOperation,
        callback: @escaping HookCallback) -> UUID
    {
        let key = makeKey(entityName: entityName, operation: operation)
        let id = UUID()
        let item = ObserverHookItem(id: id, callback: callback)

        if observerHooks[key] == nil {
            observerHooks[key] = []
        }
        observerHooks[key]?.append(item)
        hookIdToKey[id] = key

        return id
    }

    /// Remove a specific Observer Hook by its UUID
    /// - Parameter id: The UUID of the hook to remove
    /// - Returns: Whether the hook was successfully removed
    @discardableResult
    public func removeObserver(id: UUID) -> Bool {
        guard let key = hookIdToKey[id] else {
            return false
        }

        // Remove from hooks array
        observerHooks[key]?.removeAll { $0.id == id }

        // Remove from reverse mapping
        hookIdToKey.removeValue(forKey: id)

        // Clean up empty arrays
        if observerHooks[key]?.isEmpty == true {
            observerHooks.removeValue(forKey: key)
        }

        return true
    }

    /// Remove all Observer Hooks for a specific entity and operation
    /// - Parameters:
    ///   - entityName: The name of the entity
    ///   - operation: The type of operation
    public func removeObserver(entityName: String, operation: HookOperation) {
        let key = makeKey(entityName: entityName, operation: operation)

        // Remove all UUID mappings for this key
        if let items = observerHooks[key] {
            for item in items {
                hookIdToKey.removeValue(forKey: item.id)
            }
        }

        // Remove the hooks for this key
        observerHooks.removeValue(forKey: key)
    }

    /// Trigger Observer Hooks with the given context
    /// - Parameter context: The hook context containing transaction information
    public func triggerObserver(context: HookContext) async {
        let key = makeKey(entityName: context.entityName, operation: context.operation)
        if let items = observerHooks[key] {
            for item in items {
                await item.callback(context)
            }
        }
    }

    // MARK: - Utility

    /// Remove all registered Observer Hooks
    public func removeAllObservers() {
        observerHooks.removeAll()
        hookIdToKey.removeAll()
    }

    private func makeKey(entityName: String, operation: HookOperation) -> String {
        "\(entityName).\(operation.rawValue)"
    }
}
