//
//  TimestampManagerTests.swift
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
@testable import PersistentHistoryTrackingKit
import Testing

@Suite("Timestamp Manager Tests", .serialized)
struct TimestampManagerTests {
    let uniqueString = "PersistentHistoryTrackingKit.lastToken.Tests."
    let userDefaults = UserDefaults.standard

    init() {
        // 清除 UserDefaults 环境
        for author in AppActor.allCases {
            userDefaults.removeObject(forKey: uniqueString + author.rawValue)
        }
    }

    @Test("Should set single author timestamp")
    func setSingleAuthorTimestamp() {
        // given
        let author = AppActor.app1.rawValue
        let manager = TransactionTimestampManager(
            userDefaults: userDefaults,
            uniqueString: uniqueString)
        let key = uniqueString + author

        // when
        let date = Date()
        manager.updateLastHistoryTransactionTimestamp(for: author, to: date)

        // then
        #expect(date == userDefaults.value(forKey: key) as? Date)
    }

    @Test("Should handle no author update timestamp")
    func noAuthorUpdateTimestamp() {
        // given
        let max: TimeInterval = 100
        let manager = TransactionTimestampManager(
            userDefaults: userDefaults,
            maximumDuration: max,
            uniqueString: uniqueString)
        let authors = AppActor.allCases.map(\.rawValue)

        // when
        let lastTimestamp = manager.getLastCommonTransactionTimestamp(in: authors)

        // then
        #expect(lastTimestamp != nil)
    }

    @Test("Should get correct timestamp when all authors have updated")
    func allAuthorsHaveUpdatedTimestamp() {
        // given
        let testUniqueString = "PersistentHistoryTrackingKit.lastToken.Tests.testAllAuthors."

        // 清除这个测试的 UserDefaults 环境
        for author in AppActor.allCases {
            userDefaults.removeObject(forKey: testUniqueString + author.rawValue)
        }

        let manager = TransactionTimestampManager(
            userDefaults: userDefaults,
            uniqueString: testUniqueString)

        let date1 = Date().addingTimeInterval(-1000)
        let date2 = Date().addingTimeInterval(-2000)
        let date3 = Date().addingTimeInterval(-3000)

        manager.updateLastHistoryTransactionTimestamp(for: AppActor.app1.rawValue, to: date1)
        manager.updateLastHistoryTransactionTimestamp(for: AppActor.app2.rawValue, to: date2)
        manager.updateLastHistoryTransactionTimestamp(for: AppActor.app3.rawValue, to: date3)

        let authors = AppActor.allCases.map(\.rawValue)

        // when
        let lastTimestamp = manager.getLastCommonTransactionTimestamp(in: authors)

        // then
        #expect(lastTimestamp == date3)

        // 清理
        for author in AppActor.allCases {
            userDefaults.removeObject(forKey: testUniqueString + author.rawValue)
        }
    }

    @Test("Should handle partial authors update when threshold not touched")
    func partOfAuthorsHaveUpdatedTimestampAndThresholdNotYetTouched() {
        // given
        let manager = TransactionTimestampManager(
            userDefaults: userDefaults,
            uniqueString: uniqueString)

        let date1 = Date().addingTimeInterval(-1000)
        let date2 = Date().addingTimeInterval(-2000)

        manager.updateLastHistoryTransactionTimestamp(for: AppActor.app1.rawValue, to: date1)
        manager.updateLastHistoryTransactionTimestamp(for: AppActor.app2.rawValue, to: date2)

        let authors = AppActor.allCases.map(\.rawValue)

        // when
        let lastTimestamp = manager.getLastCommonTransactionTimestamp(in: authors)

        // then
        #expect(lastTimestamp != nil)
    }

    @Test("Should handle partial authors update when threshold touched")
    func partOfAuthorsHaveUpdatedTimestampAndTouchedThreshold() {
        // given
        let maxDuration = 3000.0
        let manager = TransactionTimestampManager(
            userDefaults: userDefaults,
            maximumDuration: maxDuration,
            uniqueString: uniqueString)

        let date1 = Date().addingTimeInterval(-(maxDuration + 1000))
        let date2 = Date().addingTimeInterval(-(maxDuration + 2000))

        manager.updateLastHistoryTransactionTimestamp(for: AppActor.app1.rawValue, to: date1)
        manager.updateLastHistoryTransactionTimestamp(for: AppActor.app2.rawValue, to: date2)

        let authors = AppActor.allCases.map(\.rawValue)

        // when
        let lastTimestamp = manager.getLastCommonTransactionTimestamp(in: authors)

        // then
        #expect(lastTimestamp != nil)
        if let lastTimestamp {
            #expect(lastTimestamp < date1)
        }
    }

    @Test("Should get correct timestamp when batch authors exist")
    func getLastCommonTimestampWhenBatchAuthorsIsNotEmpty() {
        // given
        let manager = TransactionTimestampManager(
            userDefaults: userDefaults,
            uniqueString: uniqueString)

        let authors = ["app1", "app1Batch"]
        let batchAuthors = ["app1Batch"]
        let currentAuthor = "app1"

        let updateDate = Date()

        // when
        manager.updateLastHistoryTransactionTimestamp(for: currentAuthor, to: updateDate)
        let lastDate1 = manager.getLastCommonTransactionTimestamp(in: authors)

        // then
        #expect(lastDate1 != nil)

        // when
        let lastDate2 = manager.getLastCommonTransactionTimestamp(
            in: authors,
            exclude: batchAuthors)

        #expect(lastDate2 == updateDate)
    }
}

enum AppActor: String, CaseIterable {
    case app1, app2, app3
}
