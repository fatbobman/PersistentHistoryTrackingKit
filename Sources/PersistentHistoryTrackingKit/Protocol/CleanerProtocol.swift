//
//  CleanerProtocol.swift
//
//
//  Created by Yang Xu on 2022/2/11
//  Copyright © 2022 Yang Xu. All rights reserved.
//
//  Follow me on Twitter: @fatbobman
//  My Blog: https://www.fatbobman.com
//  微信公共号: 肘子的Swift记事本
//

import CoreData
import Foundation

public protocol TransactionCleanerProtocol {
    /// 用来提取Request和删除 transaction 的上下文。通常是私有上下文
    var backgroundContext: NSManagedObjectContext { get }
    /// 清理 transactions 时只处理 transactionAuthor 在该数组中的 transaction
    var authors: [String] { get }
    /// 清除指定时间之前由 authors 产生的 transaction
    func cleanTransaction(before timestamp: Date?) throws
}
