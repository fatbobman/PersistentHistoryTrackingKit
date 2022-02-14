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

@testable import PersistentHistoryTrackKit
import XCTest

class TimestampManagerTests: XCTestCase {
    let uniqueString = "PersistentHistoryTrackKit.lastToken."
    let userDefaults = UserDefaults.standard

    override func setUpWithError() throws {
        // 清除 UserDefaults 环境
        for author in AppActor.allCases {
            userDefaults.removeObject(forKey: uniqueString + author.rawValue)
        }
    }

    func testSetSingleAuthorTimestamp() {
        // given
        let author = AppActor.app1.rawValue
        let manager = TransactionTimestampManager(userDefaults: userDefaults, uniqueString: uniqueString)
        let key = uniqueString + author

        // when
        let date = Date()
        manager.updateLastHistoryTransactionTimestamp(for: author, to: date)

        // then
        XCTAssertEqual(date, userDefaults.value(forKey: key) as? Date)
    }

    func testNoAuthorUpdateTimestamp() {
        // given
        let manager = TransactionTimestampManager(userDefaults: userDefaults)
        let authors = AppActor.allCases.map { $0.rawValue }

        // when
        let lastTimestamp = manager.getLastCommonTransactionTimestamp(in: authors)

        // then
        XCTAssertNil(lastTimestamp)
    }

    func testAllAuthorsHaveUpdatedTimestamp() {
        // given
        let manager = TransactionTimestampManager(userDefaults: userDefaults)

        let date1 = Date().addingTimeInterval(-1000)
        let date2 = Date().addingTimeInterval(-2000)
        let date3 = Date().addingTimeInterval(-3000)

        manager.updateLastHistoryTransactionTimestamp(for: AppActor.app1.rawValue, to: date1)
        manager.updateLastHistoryTransactionTimestamp(for: AppActor.app2.rawValue, to: date2)
        manager.updateLastHistoryTransactionTimestamp(for: AppActor.app3.rawValue, to: date3)

        let authors = AppActor.allCases.map { $0.rawValue }

        // when
        let lastTimestamp = manager.getLastCommonTransactionTimestamp(in: authors)

        // then
        XCTAssertEqual(lastTimestamp, date3)
    }

    // 仅部分author设置了时间戳，尚未触及阈值日期
    func testPartOfAuthorsHaveUpdatedTimestampAndThresholdNotYetTouched() {
        // given
        let manager = TransactionTimestampManager(userDefaults: userDefaults)

        let date1 = Date().addingTimeInterval(-1000)
        let date2 = Date().addingTimeInterval(-2000)

        manager.updateLastHistoryTransactionTimestamp(for: AppActor.app1.rawValue, to: date1)
        manager.updateLastHistoryTransactionTimestamp(for: AppActor.app2.rawValue, to: date2)

        let authors = AppActor.allCases.map { $0.rawValue }

        // when
        let lastTimestampe = manager.getLastCommonTransactionTimestamp(in: authors)

        // then
        XCTAssertNil(lastTimestampe)
    }

    // 部分author设置了时间戳，已触及阈值日期
    func testPartOfAuthorsHaveUpdatedTimestampAndTouchedThreshould() {
        // given
        let maxDuration = 3000.0
        let manager = TransactionTimestampManager(userDefaults: userDefaults, maximumDuration: maxDuration)

        let date1 = Date().addingTimeInterval(-(maxDuration + 1000))
        let date2 = Date().addingTimeInterval(-(maxDuration + 2000))

        manager.updateLastHistoryTransactionTimestamp(for: AppActor.app1.rawValue, to: date1)
        manager.updateLastHistoryTransactionTimestamp(for: AppActor.app2.rawValue, to: date2)

        let authors = AppActor.allCases.map { $0.rawValue }

        // when
        let lastTimestamp = manager.getLastCommonTransactionTimestamp(in: authors)

        // then
        XCTAssertNotNil(lastTimestamp)
        if let lastTimestamp = lastTimestamp {
            XCTAssertGreaterThan(lastTimestamp, date1)
        }
    }
}

enum AppActor: String, CaseIterable {
    case app1, app2, app3
}
