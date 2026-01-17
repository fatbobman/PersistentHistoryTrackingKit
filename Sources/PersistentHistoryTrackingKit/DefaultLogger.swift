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

/// Default logger implementation for PersistentHistoryTrackingKit.
/// Used automatically unless a custom logger is supplied by the developer.
struct DefaultLogger: PersistentHistoryTrackingKitLoggerProtocol {
  /// Output a log message.
  /// - Parameters:
  ///   - type: Log type: info, debug, notice, error, or fault.
  ///   - message: Text to log.
  func log(type: PersistentHistoryTrackingKitLogType, message: String) {
    print("[\(type.rawValue.uppercased())] : \(message)")
  }
}
