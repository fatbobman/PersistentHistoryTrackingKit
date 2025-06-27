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

@testable import PersistentHistoryTrackingKit
import Testing

@Suite("Clean Strategy Tests")
struct CleanStrategyTests {
    @Test("None strategy should never allow cleaning")
    func noneStrategy() {
        let strategy = TransactionCleanStrategyNone()
        #expect(!strategy.allowedToClean())
    }

    @Test("Duration strategy should allow cleaning based on time intervals")
    func testByDuration() async throws {
        var strategy = TransactionCleanStrategyByDuration(strategy: .byDuration(seconds: 3))

        let result1 = strategy.allowedToClean()
        #expect(result1)

        await sleep(seconds: 2)
        let result2 = strategy.allowedToClean()
        #expect(!result2)

        await sleep(seconds: 1.1)
        let result3 = strategy.allowedToClean()
        #expect(result3)

        let result4 = strategy.allowedToClean()
        #expect(!result4)

        let result5 = strategy.allowedToClean()
        #expect(!result5)

        await sleep(seconds: 3)
        let result6 = strategy.allowedToClean()
        #expect(result6)
    }

    @Test("Notification strategy should allow cleaning based on notification count")
    func testByNotification() async throws {
        var strategyBy3 =
            TransactionCleanStrategyByNotification(strategy: .byNotification(times: 3))

        let result1 = strategyBy3.allowedToClean()
        #expect(result1)

        // 每三次执行一次
        let result2 = strategyBy3.allowedToClean()
        #expect(!result2)

        let result3 = strategyBy3.allowedToClean()
        #expect(!result3)

        let result4 = strategyBy3.allowedToClean()
        #expect(result4)

        let result5 = strategyBy3.allowedToClean()
        #expect(!result5)

        let result6 = strategyBy3.allowedToClean()
        #expect(!result6)

        let result7 = strategyBy3.allowedToClean()
        #expect(result7)

        // 每次都执行
        var strategyBy1 =
            TransactionCleanStrategyByNotification(strategy: .byNotification(times: 1))

        let result8 = strategyBy1.allowedToClean()
        #expect(result8)

        let result9 = strategyBy1.allowedToClean()
        #expect(result9)

        let result10 = strategyBy1.allowedToClean()
        #expect(result10)
    }
}
