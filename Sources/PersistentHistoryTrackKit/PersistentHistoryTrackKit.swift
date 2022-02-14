//
//  PersistentHistoryTrackKit.swift
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

public final class PersistentHistoryTrackKit {
    internal init(logLevel: Int, enableLog: Bool, strategy: TransactionCleanStrategy, currentAuthor: String, allAuthor: [String], contexts: [NSManagedObjectContext], userDefaults: UserDefaults, maximumDuration: TimeInterval, uniqueString: String, logger: PersistentHistoryTrackKitLoggerProtocol, fetcher: PersistentHistoryTrackFetcher, merger: PersistentHistoryTrackKitMerger, cleaner: PersistentHistoryTrackKitCleaner?, timestampManager: TransactionTimestampManager, task: Task<Void, Never>? = nil, coordinator: NSPersistentStoreCoordinator, backgroundContext: NSManagedObjectContext) {
        self.logLevel = logLevel
        self.enableLog = enableLog
        self.strategy = TransactionCleanStrategyNone(strategy: .none)
        self.currentAuthor = currentAuthor
        self.authors = allAuthor
        self.contexts = contexts
        self.maximumDuration = maximumDuration
        self.uniqueString = uniqueString
        self.logger = logger
        self.fetcher = fetcher
        self.merger = merger
        self.cleaner = cleaner
        self.timestampManager = timestampManager
        self.task = task
        self.coordinator = coordinator
        self.backgroundContext = backgroundContext
    }

    public var logLevel: Int
    public var enableLog: Bool

    var strategy: TransactionCleanStrategyProtocol

    let currentAuthor: String
    let authors: [String]
    /// 需要被合并的上下文，通常是视图上下文。可以是多个
    let contexts: [NSManagedObjectContext]
    /// transaction 最长可以保存的时间（秒）。如果在改时间内仍无法获取到全部的 author 更新时间戳，
    /// 将返回从当前时间剪去该秒数的日期 Date().addingTimeInterval(-1 * abs(maximumDuration))
    let maximumDuration: TimeInterval
    /// 在 UserDefaults 中保存时间戳 Key 的前缀。
    let uniqueString: String
    /// 日志管理器
    let logger: PersistentHistoryTrackKitLoggerProtocol
    /// 获取需要处理的 transaction
    let fetcher: PersistentHistoryTrackFetcher
    /// 合并transaction到指定的托管对象上下文中（contexts）
    let merger: PersistentHistoryTrackKitMerger
    /// transaction清除器，清除可确认的已被所有authors合并的transaction
    let cleaner: PersistentHistoryTrackKitCleaner?
    /// 时间戳管理器，过去并更新合并事件戳
    let timestampManager: TransactionTimestampManager

    /// 处理持久化历史跟踪事件的任务。可以通过start开启，stop停止。
    var task: Task<Void, Never>?

    /// 持久化存储协调器，用于缩小通知返回
    private let coordinator: NSPersistentStoreCoordinator
    /// 专职处理transaction的托管对象上下文
    private let backgroundContext: NSManagedObjectContext

    func createTask() -> Task<Void, Never> {
        Task {
            // 响应 notification
            let publisher = NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange, object: coordinator)
            for await _ in publisher.sequence where !Task.isCancelled {
                // fetch
                let lastTimestamp = timestampManager.getLastHistoryTransactionTimestamp(for: currentAuthor) ?? Date.distantPast
                var transactions = [NSPersistentHistoryTransaction]()
                do {
                    transactions = try fetcher.fetchTransactions(from: lastTimestamp)
                    sendMessage(type: .notice, level: 2, message: "There are \(transactions.count) transaction related to \(currentAuthor) in the query")
                } catch {
                    sendMessage(type: .error, level: 1, message: "Fetch transaction error: \(error.localizedDescription)")
                    continue
                }

                // merge
                merger(merge: transactions, into: contexts)
                timestampManager.updateLastHistoryTransactionTimestamp(for: currentAuthor, to: Date())

                // clean
                guard strategy.allowedToClean() else { continue }
                let cleanTimestamp = timestampManager.getLastCommonTransactionTimestamp(in: authors)
                do {
                    try cleaner?.cleanTransaction(before: cleanTimestamp)
                    sendMessage(type: .notice, level: 2, message: "Delete transaction success")
                } catch {
                    sendMessage(type: .error, level: 1, message: "Delete transaction error: \(error.localizedDescription)")
                }
            }
        }
    }
}

public extension PersistentHistoryTrackKit {
    /// 发送日志
    internal func sendMessage(type: PersistentHistoryTrackKitLogType, level: Int, message: String) {
        guard enableLog, level <= logLevel else { return }
        logger.log(type: type, message: message)
    }

    /// 启动处理任务
    func start() {
        stop()
        task? = createTask()
    }

    /// 停止处理任务
    func stop() {
        task?.cancel()
        task = nil
    }
}

public extension PersistentHistoryTrackKit {
//    convenience init() {}
}
