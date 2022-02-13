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
    internal init(logLevel: Int, enableLog: Bool, currentAuthor: String, allAuthor: [String], contexts: [NSManagedObjectContext], userDefaults: UserDefaults, maximumDuration: TimeInterval, uniqueString: String, logger: PersistentHistoryTrackKitLoggerProtocol, fetcher: PersistentHistoryTrackFetcher, merger: PersistentHistoryTrackKitMerger, cleaner: PersistentHistoryTrackKitCleaner?, timestampManager: TransactionTimestampManager, task: Task<Void, Never>? = nil, coordinator: NSPersistentStoreCoordinator, backgroundContext: NSManagedObjectContext) {
        self.logLevel = logLevel
        self.enableLog = enableLog
        self.currentAuthor = currentAuthor
        self.allAuthor = allAuthor
        self.contexts = contexts
        self.userDefaults = userDefaults
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

    let currentAuthor: String
    let allAuthor: [String]
    /// 需要被合并的上下文，通常是视图上下文。可以是多个
    let contexts: [NSManagedObjectContext]
    let userDefaults: UserDefaults
    /// transaction 最长可以保存的时间（秒）。如果在改时间内仍无法获取到全部的 author 更新时间戳，
    /// 将返回从当前时间剪去该秒数的日期 Date().addingTimeInterval(-1 * abs(maximumDuration))
    let maximumDuration: TimeInterval
    /// 在 UserDefaults 中保存时间戳 Key 的前缀。
    let uniqueString: String

    public var logger: PersistentHistoryTrackKitLoggerProtocol
    let fetcher: PersistentHistoryTrackFetcher
    let merger: PersistentHistoryTrackKitMerger
    let cleaner: PersistentHistoryTrackKitCleaner?
    let timestampManager: TransactionTimestampManager

    var task: Task<Void, Never>?

    private let coordinator: NSPersistentStoreCoordinator
    private let backgroundContext: NSManagedObjectContext

    func createTask() -> Task<Void, Never> {
        Task {
            // 响应 notification
            for await _ in NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange, object: coordinator).sequence where !Task.isCancelled {
                // fetch

                // merge

                // clean
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
