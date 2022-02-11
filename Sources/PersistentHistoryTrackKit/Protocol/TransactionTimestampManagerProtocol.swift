//
//  TransactionTimestampManagerProtocol.swift
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

/// 保存和获取时间戳的管理协议。
protocol TransactionTimestampManagerProtocol {
    /// 从给定的 author 列表中，获取可以安全删除的时间戳。
    /// Cleaner 将依据该时间戳 ，指示 Core Data 删除该时间戳之前的 Transaction。
    /// - Returns: 可以安全删除的日期。当返回值为 nil 时，将不会对 Transaction 进行清理
    func getLastCommonTransactionTimestamp(in authors: [String]) -> Date?
    /// 更新指定 author 的最后更新日期
    /// 最后更新是指，该 author 对应的程序（app，app extension）已经在改时间戳完成了 Transaction 的合并工作
    func updateLastHistoryTransactionTimestamp(for author: String, to newDate: Date?)
}
