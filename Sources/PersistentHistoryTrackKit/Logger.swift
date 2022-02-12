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

/// PersistentHistoryTrackKit 日志的默认实现。
/// 如果开发者没有使用自定义的日志实现，则 PersistentHistoryTrackKit 会默认使用本实现
struct PersistentHistoryTrackKitLogger: PersistentHistoryTrackKitLoggerProtocol {
    let enable: Bool
    let level: Int

    init(enable: Bool = true,
         level: Int = 1) {
        self.enable = enable
        self.level = level
    }

    func log(type: PersistentHistoryTrackKitLogType, messageLevel: Int, message: String) {
        guard enable, messageLevel <= level else { return }
        print("[\(type.rawValue.uppercased())] : message")
    }
}
