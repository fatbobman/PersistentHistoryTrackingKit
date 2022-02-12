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
        let logger = PersistentHistoryTrackKitLogger(enable: true,
                                                     level: 2)
        // when
        logger.log(type: .info, messageLevel: 1, message: "hello")
    }
}

struct MyLogger: PersistentHistoryTrackKitLoggerProtocol {
    var enable: Bool
    var level: Int
    func log(type: PersistentHistoryTrackKitLogType, messageLevel: Int, message: String) {
        guard enable, messageLevel <= level else { return }
        print("[\(type.rawValue.uppercased())] : message")
    }
}
