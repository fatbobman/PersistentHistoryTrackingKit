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


import Foundation
import CoreData

struct PersistentHistoryTrackKitCleaner:PersistentHistoryTrackKitCleanerProtocol{
    let backgroundContext:NSManagedObjectContext
    let authors:[String]
    let logger: PersistentHistoryTrackKitLoggerProtocol?
    let timastampManager: TransactionTimestampManager

    func cleanTransaction(before timestamp: Date?) -> Int {
        guard let timestamp = timestamp else {
            return 0
        }

        // make a request for all transactions before timestamp
        let needToDeleteHistoryRequest = NSPersistentHistoryChangeRequest.deleteHistory(before: timestamp)
        if let fetchRequest = NSPersistentHistoryTransaction.fetchRequest {
            var predicates = [NSPredicate]()
            for author in authors {
                let predicate = NSPredicate(format: "%K = %@",
                                            #keyPath(NSPersistentHistoryTransaction.author),
                                            author
                )
                predicates.append(predicate)
            }
            let compoundPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
            fetchRequest.predicate = compoundPredicate
            needToDeleteHistoryRequest.fetchRequest = fetchRequest
        }

        // Clean Transaction in context
        backgroundContext.perform {

        }

        return 0
    }

    private func execute() -> Int {
        0
    }
}
