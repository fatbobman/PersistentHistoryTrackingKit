//
//  Logger.swift
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

#if canImport(OSLog)
import OSLog
#endif

/// PersistentHistoryTrackKit 日志的默认实现。
/// 如果开发者没有使用自定义的日志实现，则 PersistentHistoryTrackKit 会默认使用本实现
class PersistentHistoryTrackKitLogger: PersistentHistoryTrackKitLoggerProtocol {
    private let subsystem: String
    private let category: String
    let enable: Bool
    let level: Int

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
    private lazy var logger = Logger(subsystem: subsystem, category: category)

    init(enable: Bool = true,
         level: Int = 1,
         subsystem: String = "",
         category: String = "PersistentHistoryTrackKit") {
        self.subsystem = subsystem
        self.category = category
        self.enable = enable
        self.level = level
    }

    #if canImport(OSLog)
    func log(type: PersistentHistoryTrackKitLogType, messageLevel: Int, message: String) {
        if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
            guard enable, messageLevel <= level else { return }
            switch type {
            case .debug:
                logger.debug("\(message)")
            case .info:
                logger.info("\(message)")
            case .notice:
                logger.notice("\(message)")
            case .error:
                logger.error("\(message)")
            case .fault:
                logger.fault("\(message)")
            }
        } else {
            printLogToConsole(type: type, messageLevel: messageLevel, message: message)
        }
    }
    #else
    func log(type: PersistentHistoryTrackKitLogType, message: String) {
        printLogToConsole(type: type, message: message)
    }
    #endif

    private func printLogToConsole(type: PersistentHistoryTrackKitLogType, messageLevel: Int, message: String) {
        guard enable, messageLevel <= level else { return }
        let type = type.rawValue.uppercased()
        print("\(type) : \(message)")
    }
}
