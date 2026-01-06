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
public enum TransactionCleanStrategy: Sendable {
    case none
    case byDuration(seconds: TimeInterval)
    case byNotification(times: Int)
}

/// 清理规则协议
protocol TransactionPurgePolicy: Sendable {
    /// 在每次接收到 notification 时判断，是否可以进行清理
    mutating func allowedToClean() -> Bool
    init(strategy: TransactionCleanStrategy)
}

/// 关闭策略。设置成该策略后，Kit中将不会执行清理任务
/// 用于想手动控制清理任务执行的情况。
/// 可以使用Kit的 生成可手动执行任务的清理实例
struct TransactionCleanStrategyNone: TransactionPurgePolicy, Sendable {
    func allowedToClean() -> Bool {
        false
    }

    init(strategy: TransactionCleanStrategy = .none) {}
}

/// 按时间间隔实行清理策略。
/// 设定间隔的秒数。每次执行清理任务时，应与上次清理时间之间至少保持设定的时间距离
struct TransactionCleanStrategyByDuration: TransactionPurgePolicy, Sendable {
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

/// 按通知次数间隔实行清理策略
///
/// 每接收到几次 notification 执行一次清理。 times = 1时，每次都会执行。 times = 3时，每三次执行一次清理
struct TransactionCleanStrategyByNotification: TransactionPurgePolicy, Sendable {
    private var count: Int
    private var times: Int
    init(strategy: TransactionCleanStrategy) {
        if case .byNotification(times: let times) = strategy {
            self.times = times
            self.count = times
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
