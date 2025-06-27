//
//  LoggerTests.swift
//
//
//  Created by Yang Xu on 2022/2/10
//  Copyright © 2022 Yang Xu. All rights reserved.
//
//  Follow me on Twitter: @fatbobman
//  My Blog: https://www.fatbobman.com
//  微信公共号: 肘子的Swift记事本
//

@testable import PersistentHistoryTrackingKit
import Testing

@Suite("Logger Tests")
struct LoggerTests {
    @Test("Logger should correctly log messages and types")
    func testLogger() {
        // given
        let logger = LoggerSpy()
        // when
        logger.log(type: .info, message: "hello")
        // then
        #expect(logger.message == "hello")
        #expect(logger.type == .info)
    }
}

final class LoggerSpy: PersistentHistoryTrackingKitLoggerProtocol {
    var type: PersistentHistoryTrackingKitLogType?
    var message: String?

    func log(type: PersistentHistoryTrackingKitLogType, message: String) {
        self.type = type
        self.message = message
    }
}
