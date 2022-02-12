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
struct PersistentHistoryTrackFetcher: PersistentHistoryTrackKitFetcherProtocol {
    init(backgroundContext: NSManagedObjectContext,
         currentAuthor: String,
         allAuthors: [String]) {
        self.backgroundContext = backgroundContext
        self.currentAuthor = currentAuthor
        self.allAuthors = allAuthors
    }

    var backgroundContext: NSManagedObjectContext
    var currentAuthor: String
    var allAuthors: [String]

    /// 获取所有不是当前 author 产生的 transaction
    /// - Parameter date: 从该日期之后产生
    /// - Returns:[NSPersistentHistoryTransaction]
    func fetchTransactions(from date: Date) throws -> [NSPersistentHistoryTransaction] {
        try backgroundContext.performAndWait {
            let fetchRequest = createFetchRequest(from: date)
            let historyResult = try backgroundContext.execute(fetchRequest) as? NSPersistentHistoryResult
            return historyResult?.result as? [NSPersistentHistoryTransaction] ?? []
        }
    }

    /// 生成 NSPersistentHistoryChangeRequest。
    /// 所有不是当前 author 产生的 transaction。
    /// - Parameter date: 获取从该日期之后产生的 transaction
    /// - Returns: NSPersistentHistoryChangeRequest
    private func createFetchRequest(from date: Date) -> NSPersistentHistoryChangeRequest {
        let historyFetchRequest = NSPersistentHistoryChangeRequest.fetchHistory(after: date)
        if let fetchRequest = NSPersistentHistoryTransaction.fetchRequest {
            var predicates = [NSPredicate]()
            for author in allAuthors where author != currentAuthor {
                let predicate = NSPredicate(format: "%K = %@",
                                            #keyPath(NSPersistentHistoryTransaction.author),
                                            author)
                predicates.append(predicate)
            }
            let compoundPredicate = NSCompoundPredicate(type: .or, subpredicates: predicates)
            fetchRequest.predicate = compoundPredicate
            historyFetchRequest.fetchRequest = fetchRequest
        }
        return historyFetchRequest
    }
}
