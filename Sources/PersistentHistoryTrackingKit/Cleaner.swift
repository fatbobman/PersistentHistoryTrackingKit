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

/// Persistent history transaction Cleaner
struct Cleaner: TransactionCleanerProtocol {
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
            let request = getPersistentStoreRequest(before: timestamp, for: authors)
            try backgroundContext.execute(request)
        }
    }

    // make a request for delete transactions before timestamp
    func getPersistentStoreRequest(before timestamp: Date, for allAuthors: [String]) -> NSPersistentStoreRequest {
        let historyStoreRequest = NSPersistentHistoryChangeRequest.deleteHistory(before: timestamp)
        if let fetchRequest = NSPersistentHistoryTransaction.fetchRequest {
            fetchRequest.predicate = createPredicateForAllAuthors(allAuthors: authors)
            historyStoreRequest.fetchRequest = fetchRequest
        }
        return historyStoreRequest
    }

    /// create predicate for all authors
    func createPredicateForAllAuthors(allAuthors: [String]) -> NSPredicate {
        var predicates = [NSPredicate]()
        for author in allAuthors {
            let predicate = NSPredicate(format: "%K = %@",
                                        #keyPath(NSPersistentHistoryTransaction.author),
                                        author)
            predicates.append(predicate)
        }
        let compoundPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
        return compoundPredicate
    }
}

/// 可用于外部的Transaction清理器
///
/// 在 PersistentHistoryTrackKit 中使用 cleanerBuilder() 来生成该实例。该清理器的配置继承于 Kit 实例
///
///     let kit = PersistentHistoryTrackKit(.....)
///     let cleaner = kit().cleanerBuilder
///
///     cleaner() //在需要执行清理的地方运行
///
/// 比如每次app进入后台时，执行清理任务。
public struct PersistentHistoryTrackingKitManualCleaner {
    let cleaner: Cleaner
    let timestampManager: TransactionTimestampManager
    let authors: [String]
    let logger: PersistentHistoryTrackingKitLoggerProtocol
    public var logLevel: Int

    init(clear: Cleaner,
         timestampManager: TransactionTimestampManager,
         logger: PersistentHistoryTrackingKitLoggerProtocol,
         logLevel: Int,
         authors: [String]) {
        self.cleaner = clear
        self.timestampManager = timestampManager
        self.logger = logger
        self.authors = authors
        self.logLevel = logLevel
    }

    public func callAsFunction() {
        let cleanTimestamp = timestampManager.getLastCommonTransactionTimestamp(in: authors)
        do {
            try cleaner.cleanTransaction(before: cleanTimestamp)
            sendMessage(type: .info, level: 2, message: "Delete transaction success")
        } catch {
            sendMessage(type: .error, level: 1, message: "Delete transaction error: \(error.localizedDescription)")
        }
    }

    /// 发送日志
    func sendMessage(type: PersistentHistoryTrackingKitLogType, level: Int, message: String) {
        guard level <= logLevel else { return }
        logger.log(type: type, message: message)
    }
}
