//
//  CleanStrategy.swift
//
//
//  Created by Yang Xu on 2022/2/14
//  Copyright © 2022 Yang Xu. All rights reserved.
//
//  Follow me on Twitter: @fatbobman
//  My Blog: https://www.fatbobman.com
//  微信公共号: 肘子的Swift记事本
//

import Foundation

/// Transaction 清理策略。
///
/// 如果仅需合并，无需自动清理，可以选择none。
/// byNotification可以指定每隔通知清理一次。默认设置为 byNotification(0)
/// bySeconds设置成美两次清理中间至少间隔多少秒。
public enum TransactionCleanStrategy {
    case none
    case byDuration(seconds: TimeInterval)
    case byNotification(times: Int)
}

protocol TransactionCleanStrategyProtocol {
    mutating func allowedToClean() -> Bool
    init(strategy: TransactionCleanStrategy)
}

struct TransactionCleanStrategyNone: TransactionCleanStrategyProtocol {
    func allowedToClean() -> Bool {
        false
    }

    init(strategy: TransactionCleanStrategy) {}
}

struct TransactionCleanStrategyByDuration: TransactionCleanStrategyProtocol {
    private var lastCleanTimestamp: Date?
    private let duration: TimeInterval

    mutating func allowedToClean() -> Bool {
        if (lastCleanTimestamp ?? .distantPast).advanced(by: duration) < Date() {
            lastCleanTimestamp = Date()
            return true
        } else {
            return false
        }
    }

    init(strategy: TransactionCleanStrategy) {
        if case .byDuration(let seconds) = strategy {
            self.duration = seconds
        } else {
            fatalError("Transaction clean strategy should be byDuration")
        }
    }
}

struct TransactionCleanStrategyByNotification: TransactionCleanStrategyProtocol {
    private var count = 1
    private var times: Int
    init(strategy: TransactionCleanStrategy) {
        if case .byNotification(times: let times) = strategy {
            self.times = times
        } else {
            fatalError("Transaction clean strategy should be byNotification")
        }
    }

    mutating func allowedToClean() -> Bool {
        if count >= times {
            count = 1
            return true
        } else {
            count += 1
            return false
        }
    }
}
