//
//  LoggerProtocol.swift
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

/// Logger protocol for PersistentHistoryTrackKit.
/// Developers can create types conforming to this protocol to enable PersistentHistoryTrackKit to work with existing logging modules.
/// Log output switching and detail control are both on PersistentHistoryTrackKit
public protocol PersistentHistoryTrackingKitLoggerProtocol: Sendable {
  /// Output logs. Developers can convert LogType to the Type corresponding to their own logging module
  func log(type: PersistentHistoryTrackingKitLogType, message: String)
}

/// Log types. Although 5 types are defined, currently only debug and error are used.
public enum PersistentHistoryTrackingKitLogType: String, Sendable {
  case debug, info, notice, error, fault
}
