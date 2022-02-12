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
    init(
        backgroundContext: NSManagedObjectContext,
        authors: [String]
    ) {
        self.backgroundContext = backgroundContext
        self.authors = authors
    }

    let backgroundContext: NSManagedObjectContext
    let authors: [String]

    func cleanTransaction(before timestamp: Date?) throws {
        guard let timestamp = timestamp else { return }
        try backgroundContext.performAndWait {
            let request = getRequest(before: timestamp)
            try backgroundContext.execute(request)
        }
    }

    // make a request for delete transactions before timestamp
    private func getRequest(before timestamp: Date) -> NSPersistentStoreRequest {
        let historyStoreRequest = NSPersistentHistoryChangeRequest.deleteHistory(before: timestamp)
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
            historyStoreRequest.fetchRequest = fetchRequest
        }
        return historyStoreRequest
    }
}
