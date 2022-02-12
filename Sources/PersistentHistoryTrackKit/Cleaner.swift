//
//  Cleaner.swift
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

struct PersistentHistoryTrackKitCleaner: PersistentHistoryTrackKitCleanerProtocol {
    init(backgroundContext: NSManagedObjectContext,
         authors: [String],
         logger: PersistentHistoryTrackKitLoggerProtocol?,
         timestampManager: TransactionTimestampManager) {
        self.backgroundContext = backgroundContext
        self.authors = authors
        self.logger = logger
        self.timestampManager = timestampManager
    }

    let backgroundContext: NSManagedObjectContext
    let authors: [String]
    let logger: PersistentHistoryTrackKitLoggerProtocol?
    let timestampManager: TransactionTimestampManagerProtocol

    func cleanTransaction(before timestamp: Date?) {
        guard let timestamp = timestamp else {
            logger?.log(type: .debug, messageLevel: 2, message: "There are no transactions that need to be deleted")
            return
        }
        let request = getRequest(before: timestamp)
        // clean transactions in context
        executeRequest(for: request)
    }

    // make a request for delete all transactions before timestamp
    private func getRequest(before timestamp: Date) -> NSPersistentStoreRequest {
        let needToDeleteHistoryRequest = NSPersistentHistoryChangeRequest.deleteHistory(before: timestamp)
        if let fetchRequest = NSPersistentHistoryTransaction.fetchRequest {
            var predicates = [NSPredicate]()
            for author in authors {
                let predicate = NSPredicate(format: "%K = %@",
                                            #keyPath(NSPersistentHistoryTransaction.author),
                                            author)
                predicates.append(predicate)
            }
            let compoundPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
            fetchRequest.predicate = compoundPredicate
            needToDeleteHistoryRequest.fetchRequest = fetchRequest
        }
        return needToDeleteHistoryRequest
    }

    // delete transactions
    private func executeRequest(for request: NSPersistentStoreRequest) {
        backgroundContext.performAndWait {
            do {
                try backgroundContext.execute(request)
                logger?.log(type: .debug, messageLevel: 2, message: "Delete Transactions Success")
                // 重置所有 author 的最后更新时间戳
                for author in authors {
                    timestampManager.updateLastHistoryTransactionTimestamp(for: author, to: nil)
                }
            } catch {
                logger?.log(type: .fault, messageLevel: 1, message: "Delete Transactions Error : \(error.localizedDescription)")
            }
        }
    }
}
