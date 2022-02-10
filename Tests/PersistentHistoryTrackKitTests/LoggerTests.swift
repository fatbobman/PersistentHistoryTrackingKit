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

@testable import PersistentHistoryTrackKit
import XCTest

class LoggerTests: XCTestCase {
    func testLogger() throws {
        // given
        let logger = PersistentHistoryTrackKitLogger(subsystem: "com.fatbobman", category: "PersistentHistoryTrackKit")
        // when
        logger.log(type: .info, message: "hello")
    }

    func testLoggerProtocol() {
        let logger = Logger()
        logger.log(type: .info, message: "hello world")
    }
}

struct Logger: PersistentHistoryTrackKitLoggerProtocol {
    func log(type: PersistentHistroyTrackKitLogType, message: String) {
        print(type.rawValue, message)
    }
}
