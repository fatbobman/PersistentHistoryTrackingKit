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
public struct PersistentHistoryTrackKitManualCleaner {
    let cleaner: PersistentHistoryTrackKitCleaner
    let timestampManager: TransactionTimestampManager
    let authors: [String]
    let logger: PersistentHistoryTrackKitLoggerProtocol
    let logLevel: Int

    init(clear: PersistentHistoryTrackKitCleaner,
         timestampManager: TransactionTimestampManager,
         logger: PersistentHistoryTrackKitLoggerProtocol,
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
    func sendMessage(type: PersistentHistoryTrackKitLogType, level: Int, message: String) {
        guard level <= logLevel else { return }
        logger.log(type: type, message: message)
    }
}
