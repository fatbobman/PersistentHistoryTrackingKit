//
//  TransactionTimestampManager.swift
//
//
//  Created by Yang Xu on 2022/2/10
//  Copyright © 2022 Yang Xu. All rights reserved.
//
//  Follow me on Twitter: @fatbobman
//  My Blog: https://www.fatbobman.com
//  微信公共号: 肘子的Swift记事本
//

import Foundation

/// author 的 Transaction 合并更新的时间戳管理器。
/// 本实现采用 UserDefaults 对每个 author 的最后更新日期进行保存，并从中返回可被安全删除的日期。
/// 为了防止在 AppGrounp 的情况下，部分 app 始终没有被启用或实现，从而导致数据不全的情况。
/// 本实现设定了阈值日期机制，在满足了设定的情况下，将阈值日期作为可安全删除的日期返回
struct TransactionTimestampManager: TransactionTimestampManagerProtocol {
    /// 用于保存的 UserDefaults 实例。对于 AppGroup，应该使用可用于全体成员的实例。如：UserDefaults(suiteName: Settings.AppGroup.groupID)
    private let userDefaults: UserDefaults
    /// transaction 最长可以保存的时间（秒）。如果在改时间内仍无法获取到全部的 author 更新时间戳，
    /// 将返回从当前时间剪去该秒数的日期 Date().addingTimeInterval(-1 * abs(maximumDuration))
    private let maximumDuration: TimeInterval
    /// 在 UserDefaults 中保存时间戳 Key 的前缀。
    private let uniqueString: String

    func getLastCommonTransactionTimestamp(in authors: [String], exclude batchAuthors: [String] = []) -> Date? {
        let shouldCheckAuthors = Set(authors).subtracting(batchAuthors)
        let lastTimestamps = shouldCheckAuthors
            .compactMap { author in
                getLastHistoryTransactionTimestamp(for: author)
            }
        // 没有任何author记录时间的情况下，直接返回nil
        let lastTimestamp = lastTimestamps.min() ?? Date().addingTimeInterval(-1 * abs(maximumDuration))
        return lastTimestamp
    }

    func updateLastHistoryTransactionTimestamp(for author: String, to newDate: Date?) {
        let key = uniqueString + author
        userDefaults.set(newDate, forKey: key)
    }

    /// 获取指定的 author 的最后更新日期
    /// - Parameter author: author 是每个 app 或 app extension 的字符串名称。该名称应与NSManagedObjectContext的transactionAuthor一致
    /// - Returns: 该 author 的最后更新日期。如果该 author 尚未更新日期，则返回 nil
    func getLastHistoryTransactionTimestamp(for author: String) -> Date? {
        let key = uniqueString + author
        return userDefaults.value(forKey: key) as? Date
    }

    /// 创建 author 的 Transaction 合并更新的时间戳管理器。
    /// - Parameters:
    ///   - userDefaults: 用于保存的 UserDefaults 实例。
    ///   对于 AppGroup，应该使用可用于全体成员的实例。如：UserDefaults(suiteName: Settings.AppGroup.groupID)
    ///   - maximumDuration: transaction 最长可以保存的时间（秒）。如果在改时间内仍无法获取到全部的 author 更新时间戳，
    ///   将返回从当前时间剪去该秒数的日期 Date().addingTimeInterval(-1 * abs(maximumDuration))。默认值为 604,800 秒（7日）。
    ///   - uniqueString: 在 UserDefaults 中保存时间戳 Key 的前缀。默认值为："PersistentHistoryTrackingKit.lastToken."
    init(userDefaults: UserDefaults,
         maximumDuration: TimeInterval = 60 * 60 * 24 * 7, // 7 days
         uniqueString: String = "PersistentHistoryTrackingKit.lastToken.") {
        self.userDefaults = userDefaults
        self.maximumDuration = maximumDuration
        self.uniqueString = uniqueString
    }
}
