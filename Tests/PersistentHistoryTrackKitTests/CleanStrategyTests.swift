//
//  CleanStrategyTests.swift
//
//
//  Created by Yang Xu on 2022/2/14
//  Copyright © 2022 Yang Xu. All rights reserved.
//
//  Follow me on Twitter: @fatbobman
//  My Blog: https://www.fatbobman.com
//  微信公共号: 肘子的Swift记事本
//

@testable import PersistentHistoryTrackKit
import XCTest

class CleanStrategyTests: XCTestCase {
    func testNoneStrategy() {
        let strategy = TransactionCleanStrategyNone()
        XCTAssertFalse(strategy.allowedToClean())
    }

    func testByDuration() async throws {
        var strategy = TransactionCleanStrategyByDuration(strategy: .byDuration(seconds: 3))
        XCTAssertTrue(strategy.allowedToClean())
        await sleep(seconds: 2)
        XCTAssertFalse(strategy.allowedToClean())
        await sleep(seconds: 1.1)
        XCTAssertTrue(strategy.allowedToClean())
        XCTAssertFalse(strategy.allowedToClean())
        XCTAssertFalse(strategy.allowedToClean())
        await sleep(seconds: 3)
        XCTAssertTrue(strategy.allowedToClean())
    }

    func testByNotification() async throws {
        var strategyBy3 = TransactionCleanStrategyByNotification(strategy: .byNotification(times: 3))
        XCTAssertTrue(strategyBy3.allowedToClean())

        // 每三次执行一次
        XCTAssertFalse(strategyBy3.allowedToClean())
        XCTAssertFalse(strategyBy3.allowedToClean())
        XCTAssertTrue(strategyBy3.allowedToClean())

        XCTAssertFalse(strategyBy3.allowedToClean())
        XCTAssertFalse(strategyBy3.allowedToClean())
        XCTAssertTrue(strategyBy3.allowedToClean())

        // 每次都执行
        var strategyBy1 = TransactionCleanStrategyByNotification(strategy: .byNotification(times: 1))
        XCTAssertTrue(strategyBy1.allowedToClean())
        XCTAssertTrue(strategyBy1.allowedToClean())
        XCTAssertTrue(strategyBy1.allowedToClean())
    }
}
