//
//  File.swift
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

struct TransactionTimestampManager: TransactionTimestampManagerProtocol {
    private let userDefaults: UserDefaults
    private let maximumDuration: TimeInterval
    private let uniqueString: String

    func getLastCommonTransactionTimestamp(in authors: [String]) -> Date? {
        let lastTimestamps = authors
            .compactMap { author in
                getLastHistoryTransactionTimestamp(for: author)
            }
        // 没有任何author记录时间的情况下，直接返回nil
        guard let lastTimestamp = lastTimestamps.min() else { return nil }

        // 如果全部的author都记录了时间戳，则返回最早的日期。
        if lastTimestamps.count == authors.count {
            // 返回所有auhtor时间戳中最早的日期）
            return lastTimestamp
        } else {
            // 阈值日期
            let thresholdDate = Date().addingTimeInterval(-1 * abs(maximumDuration))
            if lastTimestamp < thresholdDate {
                // 在最长持续时间之内仍未收集到全部author的时间戳，则返回阈值日期
                return thresholdDate
            } else {
                // 继续等待其他的author时间戳
                return nil
            }
        }
    }

    func updateLastHistoryTransactionTimestamp(for author: String, to newDate: Date?) {
        let key = uniqueString + author
        userDefaults.set(newDate, forKey: key)
    }

    private func getLastHistoryTransactionTimestamp(for author: String) -> Date? {
        let key = uniqueString + author
        return userDefaults.value(forKey: key) as? Date
    }

    init(userDefaults: UserDefaults,
         maximumDuration: TimeInterval = 60 * 60 * 24 * 7, // 7 days
         uniqueString: String = "PersistentHistoryTrackKit.lastToken.") {
        self.userDefaults = userDefaults
        self.maximumDuration = maximumDuration
        self.uniqueString = uniqueString
    }
}
