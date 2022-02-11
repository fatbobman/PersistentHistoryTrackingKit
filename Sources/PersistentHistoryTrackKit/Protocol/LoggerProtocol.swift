//
//  PersistentHistoryTrackLoggerProtocol.swift
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

/// 用于 PersistentHistoryTrackKit 的日志协议。
/// 开发者可以创建符合该协议的类型，以便让 PersistentHistoryTrackKi t与你已有的日志模块协同工作。
/// 日志输出的开关和细节控制均在 PersistentHistoryTrackKit 上
public protocol PersistentHistoryTrackKitLoggerProtocol {
    /// 输出日志。开发者可以将 LogType 转换成自己使用的日志模块对应的 Type
    func log(type: PersistentHistroyTrackKitLogType, message: String)
}

/// 日志类型。尽管定义了5中类型，不过当前只会使用其中的 debug 和 error。
public enum PersistentHistroyTrackKitLogType:String {
    case debug, info, notice, error, fault
}
