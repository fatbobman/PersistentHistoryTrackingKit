//
//  ObserverHookProtocol.swift
//  PersistentHistoryTrackingKit
//
//  Created by Claude on 2025-01-08
//  Copyright © 2025 Yang Xu. All rights reserved.
//

public import Foundation

public protocol ObserverHookProtocol: Actor {
  @discardableResult
  func registerObserver(
    entityName: String,
    operation: HookOperation,
    callback: @escaping HookCallback
  ) -> UUID
  @discardableResult
  func removeObserver(id: UUID) -> Bool
  func removeObserver(entityName: String, operation: HookOperation)
  func triggerObserver(contexts: [HookContext]) async
  func removeAllObservers()
}
