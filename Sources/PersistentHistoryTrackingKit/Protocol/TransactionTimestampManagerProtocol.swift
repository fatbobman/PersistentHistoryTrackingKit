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
public protocol TransactionTimestampManagerProtocol {
    /// 从给定的 author 列表中，获取可以安全删除的时间戳。
    ///
    /// 如果给定了 exclude ，将仅对 authors - batchAuthors 的 author 进行时间判断
    /// Cleaner 将依据该时间戳 ，指示 Core Data 删除该时间戳之前的 Transaction。
    /// - Returns: 可以安全删除的日期。
    /// 当返回值为 nil 时，意味需要更新时间戳的 author 还没有全部更新
    func getLastCommonTransactionTimestamp(in authors: [String], exclude batchAuthors: [String]) -> Date?
    /// 更新指定 author 的最后更新日期
    /// 最后更新是指，该 author 对应的程序（app，app extension）已经在改时间戳完成了 Transaction 的合并工作
    func updateLastHistoryTransactionTimestamp(for author: String, to newDate: Date?)
    /// 获取指定的 author 的最后更新日期
    /// - Parameter author: author 是每个 app 或 app extension 的字符串名称。该名称应与NSManagedObjectContext的transactionAuthor一致
    /// - Returns: 该 author 的最后更新日期。如果该 author 尚未更新日期，则返回 nil
    func getLastHistoryTransactionTimestamp(for author: String) -> Date?
}
