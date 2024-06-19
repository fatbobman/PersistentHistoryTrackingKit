//
//  DeduplicatorProtocol.swift
//
//
//  Created by Yang Yubo on 2024/6/18.
//

import CoreData
import Foundation

public protocol TransactionDeduplicatorProtocol {
    /// 将 transaction 中的重复数据从托管对象上下文删除
    func callAsFunction(deduplicate transactions: [NSPersistentHistoryTransaction], in contexts: [NSManagedObjectContext])
}
