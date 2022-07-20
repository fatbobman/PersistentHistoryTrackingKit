//
//  FetcherProtocol.swift
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

/// 获取从指定时期之后的，非当前author生成的 transaction
protocol TransactionFetcherProtocol {
    /// 托管对象上下文。最好使用背景上下文
    var backgroundContext: NSManagedObjectContext { get }
    /// 当前的 author 名称。应用程序上下文的 transactionAuthor 需要与其一致
    var currentAuthor: String { get }
    /// 全部的 author 名称。在 app group 的情况下，每个app或app extension都使用各自的 author 名称
    /// 在同一个app下，对于批量添加的数据（batch insert），应该使用单独的 author，以区别。
    var allAuthors: [String] { get }

    /// 获取指定日期后的所有 Transaction。
    func fetchTransactions(from date: Date) throws -> [NSPersistentHistoryTransaction]
}

extension TransactionFetcherProtocol {
    static var cloudMirrorAuthors: [String] { ["NSCloudKitMirroringDelegate.import"] }
}
