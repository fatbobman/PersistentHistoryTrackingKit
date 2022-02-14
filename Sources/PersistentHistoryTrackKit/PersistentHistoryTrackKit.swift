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

// swiftlint:disable line_length

public final class PersistentHistoryTrackKit {
    init(logLevel: Int,
         enableLog: Bool,
         strategy: TransactionCleanStrategy,
         currentAuthor: String,
         allAuthor: [String],
         viewContext: NSManagedObjectContext,
         contexts: [NSManagedObjectContext],
         userDefaults: UserDefaults,
         maximumDuration: TimeInterval,
         uniqueString: String,
         logger: PersistentHistoryTrackKitLoggerProtocol,
         autoStart: Bool) {
        self.logLevel = logLevel
        self.enableLog = enableLog
        self.currentAuthor = currentAuthor
        self.authors = allAuthor
        self.contexts = contexts
        self.maximumDuration = maximumDuration
        self.uniqueString = uniqueString
        self.logger = logger

        // 检查 viewContext 是否为视图上下文
        guard viewContext.concurrencyType == .mainQueueConcurrencyType else {
            fatalError("`viewContext` must be a view context ( concurrencyType == .mainQueueConcurrencyType)")
        }

        guard let coordinator = viewContext.persistentStoreCoordinator else {
            fatalError("`viewContext` must have a persistentStoreCoordinator available")
        }

        let backgroundContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        backgroundContext.persistentStoreCoordinator = coordinator

        switch strategy {
        case .none:
            self.strategy = TransactionCleanStrategyNone()
        case .byDuration:
            self.strategy = TransactionCleanStrategyByDuration(strategy: strategy)
        case .byNotification:
            self.strategy = TransactionCleanStrategyByNotification(strategy: strategy)
        }

        self.fetcher = PersistentHistoryTrackFetcher(
            backgroundContext: backgroundContext,
            currentAuthor: currentAuthor,
            allAuthors: authors
        )

        self.merger = PersistentHistoryTrackKitMerger()
        self.cleaner = PersistentHistoryTrackKitCleaner(backgroundContext: backgroundContext, authors: authors)
        self.timestampManager = TransactionTimestampManager(userDefaults: userDefaults, uniqueString: uniqueString)
        self.coordinator = coordinator
        self.backgroundContext = backgroundContext

        if autoStart {
            start()
        }
    }

    /// 日志显示等级，从1-3级。数字越大信息越详尽
    public var logLevel: Int
    /// 日志开关
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
    let cleaner: PersistentHistoryTrackKitCleaner
    /// 时间戳管理器，过去并更新合并事件戳
    let timestampManager: TransactionTimestampManager

    /// 处理持久化历史跟踪事件的任务。可以通过start开启，stop停止。
    var task = [Task<Void, Never>]()

    /// 持久化存储协调器，用于缩小通知返回
    private let coordinator: NSPersistentStoreCoordinator
    /// 专职处理transaction的托管对象上下文
    private let backgroundContext: NSManagedObjectContext

    /// 创建处理 Transaction 的任务。
    ///
    /// 通过将持久化历史跟踪记录的通知转换成异步序列，实现了逐个处理的机制。
    func createTask() -> Task<Void, Never> {
        Task {
            sendMessage(type: .info, level: 1, message: "Persistent History Track Kit Start")
            // 响应 notification
            let publisher = NotificationCenter.default.publisher(
                for: .NSPersistentStoreRemoteChange,
                object: coordinator
            )
            for await _ in publisher.sequence where !Task.isCancelled {
                sendMessage(type: .info,
                            level: 3,
                            message: "handle a `NSPersistentStoreRemoteChange` notification")

                // fetch
                let lastTimestamp = timestampManager
                    .getLastHistoryTransactionTimestamp(for: currentAuthor) ?? Date.distantPast

                sendMessage(type: .info,
                            level: 3,
                            message: "The last history transaction timestamp for \(authors) is \(Self.dateFormatter.string(from: lastTimestamp))")
                var transactions = [NSPersistentHistoryTransaction]()
                do {
                    transactions = try fetcher.fetchTransactions(from: lastTimestamp)
                    sendMessage(type: .info, level: 2, message: "There are \(transactions.count) transaction related to \(currentAuthor) in the query")
                } catch {
                    sendMessage(type: .error, level: 1, message:
                        "Fetch transaction error: \(error.localizedDescription)")
                    continue
                }

                // merge
                guard let lastTimestamp = transactions.last?.timestamp else { continue }
                merger(merge: transactions, into: contexts)
                timestampManager.updateLastHistoryTransactionTimestamp(for: currentAuthor, to: lastTimestamp)
                sendMessage(type: .info,
                            level: 3,
                            message: "merge \(transactions.count) transactions, update \(currentAuthor) timestamp to \(Self.dateFormatter.string(from: lastTimestamp))")

                // clean
                guard strategy.allowedToClean() else { continue }
                let cleanTimestamp = timestampManager.getLastCommonTransactionTimestamp(in: authors)
                do {
                    try cleaner.cleanTransaction(before: cleanTimestamp)
                    sendMessage(type: .info, level: 2, message: "Delete transaction success")
                } catch {
                    sendMessage(type: .error, level: 1, message: "Delete transaction error: \(error.localizedDescription)")
                }
            }
            sendMessage(type: .info, level: 1, message: "Persistent History Track Kit Stop")
        }
    }

    /// 发送日志
    func sendMessage(type: PersistentHistoryTrackKitLogType, level: Int, message: String) {
        guard enableLog, level <= logLevel else { return }
        logger.log(type: type, message: message)
    }
}

public extension PersistentHistoryTrackKit {
    /// 启动处理任务
    func start() {
        if !task.isEmpty {
            stop()
        }
        task.append(createTask())
    }

    /// 停止处理任务
    func stop() {
        task.forEach {
            $0.cancel()
        }
        task.removeAll()
    }
}

extension PersistentHistoryTrackKit {
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()
}

public extension PersistentHistoryTrackKit {
    /// 创建一个可独立运行的 transaction 清除器
    ///
    /// 通常使用该清除器时，cleanStrategy 应设置为 .none
    /// 在 PersistentHistoryTrackKit 中使用 cleanerBuilder() 来生成该实例。该清理器的配置继承于 Kit 实例
    ///
    ///     let kit = PersistentHistoryTrackKit(.....)
    ///     let cleaner = kit().cleanerBuilder
    ///
    ///     cleaner() //在需要执行清理的地方运行
    ///
    /// 比如每次app进入后台时，执行清理任务。
    func cleanerBuilder() -> PersistentHistoryTrackKitManualCleaner {
        PersistentHistoryTrackKitManualCleaner(
            clear: cleaner,
            timestampManager: timestampManager,
            logger: logger,
            enableLog: enableLog,
            logLevel: logLevel,
            authors: authors
        )
    }
}

public extension PersistentHistoryTrackKit {
    /// 使用viewContext的初始化器
    convenience init(viewContext: NSManagedObjectContext,
                     contexts: [NSManagedObjectContext]? = nil,
                     currentAuthor: String,
                     authors: [String],
                     userDefaults: UserDefaults,
                     cleanStrategy: TransactionCleanStrategy = .byNotification(times: 1),
                     maximumDuration: TimeInterval = 60 * 60 * 24 * 7,
                     uniqueString: String = "PersistentHistoryTrackKit.lastToken.",
                     logger: PersistentHistoryTrackKitLoggerProtocol? = nil,
                     enableLog: Bool = true,
                     logLevel: Int = 1,
                     autoStart: Bool = true) {
        let contexts = contexts ?? [viewContext]
        let logger = logger ?? PersistentHistoryTrackKitLogger()
        self.init(logLevel: logLevel,
                  enableLog: enableLog,
                  strategy: cleanStrategy,
                  currentAuthor: currentAuthor,
                  allAuthor: authors,
                  viewContext: viewContext,
                  contexts: contexts,
                  userDefaults: userDefaults,
                  maximumDuration: maximumDuration,
                  uniqueString: uniqueString,
                  logger: logger,
                  autoStart: autoStart)
    }

    /// 使用NSPersistentContainer的初始化器
    convenience init(container: NSPersistentContainer,
                     contexts: [NSManagedObjectContext]? = nil,
                     currentAuthor: String,
                     authors: [String],
                     userDefaults: UserDefaults,
                     cleanStrategy: TransactionCleanStrategy = .byNotification(times: 1),
                     maximumDuration: TimeInterval = 60 * 60 * 24 * 7,
                     uniqueString: String = "PersistentHistoryTrackKit.lastToken.",
                     logger: PersistentHistoryTrackKitLoggerProtocol? = nil,
                     enableLog: Bool = true,
                     logLevel: Int = 1,
                     autoStart: Bool = true) {
        let viewContext = container.viewContext
        let contexts = contexts ?? [viewContext]
        let logger = logger ?? PersistentHistoryTrackKitLogger()
        self.init(logLevel: logLevel,
                  enableLog: enableLog,
                  strategy: cleanStrategy,
                  currentAuthor: currentAuthor,
                  allAuthor: authors,
                  viewContext: viewContext,
                  contexts: contexts,
                  userDefaults: userDefaults,
                  maximumDuration: maximumDuration,
                  uniqueString: uniqueString,
                  logger: logger,
                  autoStart: autoStart)
    }
}
