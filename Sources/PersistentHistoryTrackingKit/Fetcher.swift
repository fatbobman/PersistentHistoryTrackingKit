//
//  Fetcher.swift
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
struct Fetcher: TransactionFetcherProtocol {
    init(backgroundContext: NSManagedObjectContext,
         currentAuthor: String,
         allAuthors: [String],
         includingCloudKitMirroring: Bool = false) {
        self.backgroundContext = backgroundContext
        self.currentAuthor = currentAuthor
        if includingCloudKitMirroring {
            self.allAuthors = Array(Set(allAuthors + Self.cloudMirrorAuthors))
        } else {
            self.allAuthors = Array(Set(allAuthors))
        }
    }

    var backgroundContext: NSManagedObjectContext
    var currentAuthor: String
    var allAuthors: [String]

    /// 获取所有不是当前 author 产生的 transaction
    /// - Parameter date: 从该日期之后产生
    /// - Returns:[NSPersistentHistoryTransaction]
    func fetchTransactions(from date: Date) throws -> [NSPersistentHistoryTransaction] {
        try backgroundContext.performAndWait {
            let historyChangeRequest = createHistoryChangeRequest(from: date)
            let historyResult = try backgroundContext.execute(historyChangeRequest) as? NSPersistentHistoryResult
            return historyResult?.result as? [NSPersistentHistoryTransaction] ?? []
        }
    }

    /// 生成 NSPersistentHistoryChangeRequest。
    /// 所有不是当前 author 产生的 transaction。
    /// - Parameter date: 获取从该日期之后产生的 transaction
    /// - Returns: NSPersistentHistoryChangeRequest
    func createHistoryChangeRequest(from date: Date) -> NSPersistentHistoryChangeRequest {
        let historyChangeRequest = NSPersistentHistoryChangeRequest.fetchHistory(after: date)
        if let fetchRequest = NSPersistentHistoryTransaction.fetchRequest {
            fetchRequest.predicate = createPredicateForOtherAuthors(currentAuthor: currentAuthor, allAuthors: allAuthors)
            historyChangeRequest.fetchRequest = fetchRequest
        }
        return historyChangeRequest
    }

    /// 创建排除当前author的查询谓词
    func createPredicateForOtherAuthors(currentAuthor: String, allAuthors: [String]) -> NSPredicate {
        var predicates = [NSPredicate]()
        for author in allAuthors where author != currentAuthor {
            let predicate = NSPredicate(format: "%K = %@",
                                        #keyPath(NSPersistentHistoryTransaction.author),
                                        author)
            predicates.append(predicate)
        }
        let compoundPredicate = NSCompoundPredicate(type: .or, subpredicates: predicates)
        return compoundPredicate
    }
}
