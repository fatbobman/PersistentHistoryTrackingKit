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

class PersistentHistoryTrackKitLogger: PersistentHistoryTrackKitLoggerProtocol {
    private let subsystem: String
    private let category: String

    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
    private lazy var logger = Logger(subsystem: subsystem, category: category)

    init(subsystem: String = "", category: String = "PersistentHistoryTrackKit") {
        self.subsystem = subsystem
        self.category = category
    }

    #if canImport(OSLog)
    func log(type: PersistentHistroyTrackKitLogType, message: String) {
        if #available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *) {
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
            printLogToConsole(type: type, message: message)
        }
    }
    #else
    func log(type: PersistentHistroyTrackKitLogType, message: String) {
        printLogToConsole(type: type, message: message)
    }
    #endif

    private func printLogToConsole(type: PersistentHistroyTrackKitLogType, message: String) {
        let type = type.rawValue.uppercased()
        print("\(type) : \(message)")
    }
}
