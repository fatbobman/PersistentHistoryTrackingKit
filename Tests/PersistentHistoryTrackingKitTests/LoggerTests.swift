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
import XCTest

class LoggerTests: XCTestCase {
    func testLogger() throws {
        // given
        let logger = LoggerSpy()
        // when
        logger.log(type: .info, message: "hello")
        // then
        XCTAssertEqual(LoggerSpy.message, "hello")
        XCTAssertEqual(LoggerSpy.type, .info)
    }
}

struct LoggerSpy: PersistentHistoryTrackingKitLoggerProtocol {
    static var type:PersistentHistoryTrackingKitLogType?
    static var message:String?
    func log(type: PersistentHistoryTrackingKitLogType, message: String) {
        Self.type = type
        Self.message = message
    }
}
