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
struct PersistentHistoryTrackingKitLogger: PersistentHistoryTrackingKitLoggerProtocol {
    /// 输出日志
    /// - Parameters:
    ///   - type: 日志类型：info, debug, notice, error, fault
    ///   - message: 信息内容
    func log(type: PersistentHistoryTrackingKitLogType, message: String) {
        print("[\(type.rawValue.uppercased())] : \(message)")
    }
}
