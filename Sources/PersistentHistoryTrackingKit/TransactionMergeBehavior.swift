//
//  TransactionMergeBehavior.swift
//  PersistentHistoryTrackingKit
//
//  Created by Codex on 2026-07-07.
//  Copyright © 2026 Yang Xu. All rights reserved.
//

/// Controls whether PersistentHistoryTrackingKit merges processed transactions into contexts.
public enum TransactionMergeBehavior: Sendable {
  /// Run the merge hook pipeline and then the default merge when no hook finishes the pipeline.
  case automatic

  /// Skip the whole merge phase, including registered merge hooks and the default merge.
  case disabled
}
