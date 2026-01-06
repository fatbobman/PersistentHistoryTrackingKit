//
//  PersistentHistoryTrackingKit.swift
//  PersistentHistoryTrackingKit
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

/// V2: 基于 Actor 的持久化历史跟踪 Kit
public final class PersistentHistoryTrackingKit: @unchecked Sendable {

    // MARK: - Properties

    /// 日志显示等级，从 0-2 级。0 关闭 2 最详尽
    public func setLogLevel(_ level: Int) {
        // TODO: 实现线程安全的 logLevel 更新
    }

    public func getLogLevel() -> Int {
        return _logLevel
    }

    /// 当前 author
    private let currentAuthor: String

    /// 全部 authors
    private let allAuthors: [String]

    /// Hook 注册表
    private let hookRegistry: HookRegistryActor

    /// 事务处理器
    private let transactionProcessor: TransactionProcessorActor

    /// 日志显示等级，从 0-2 级。0 关闭 2 最详尽
    private let _logLevel: Int

    /// 需要合并的上下文列表
    private let contexts: [NSManagedObjectContext]

    /// 清理策略
    private var cleanStrategy: TransactionPurgePolicy

    /// 处理任务
    private var processingTask: Task<Void, Never>?

    /// 持久化存储协调器
    private let coordinator: NSPersistentStoreCoordinator

    /// 日志管理器
    private let logger: PersistentHistoryTrackingKitLoggerProtocol

    // MARK: - Initialization

    public init(
        container: NSPersistentContainer,
        contexts: [NSManagedObjectContext]? = nil,
        currentAuthor: String,
        allAuthors: [String],
        includingCloudKitMirroring: Bool = false,
        batchAuthors: [String] = [],
        userDefaults: UserDefaults,
        cleanStrategy: TransactionCleanStrategy = .byNotification(times: 1),
        maximumDuration: TimeInterval = 60 * 60 * 24 * 7,
        uniqueString: String = "PersistentHistoryTrackingKit.lastToken.",
        logger: PersistentHistoryTrackingKitLoggerProtocol? = nil,
        logLevel: Int = 1,
        autoStart: Bool = true
    ) {
        self.currentAuthor = currentAuthor
        self.allAuthors = allAuthors
        self.coordinator = container.persistentStoreCoordinator
        self.logger = logger ?? DefaultLogger()
        self._logLevel = logLevel
        self.contexts = contexts ?? [container.viewContext]

        // 创建 actors
        self.hookRegistry = HookRegistryActor()
        self.transactionProcessor = TransactionProcessorActor(container: container, hookRegistry: hookRegistry)

        // 初始化清理策略
        switch cleanStrategy {
        case .none:
            self.cleanStrategy = TransactionCleanStrategyNone()
        case .byDuration:
            self.cleanStrategy = TransactionCleanStrategyByDuration(strategy: cleanStrategy)
        case .byNotification:
            self.cleanStrategy = TransactionCleanStrategyByNotification(strategy: cleanStrategy)
        }

        if autoStart {
            start()
        }
    }

    deinit {
        stop()
    }

    // MARK: - Public Methods

    /// 注册 Hook
    /// - Parameters:
    ///   - entityName: 实体名称
    ///   - operation: 操作类型
    ///   - callback: 回调函数
    public func registerHook(
        entityName: String,
        operation: HookOperation,
        callback: @escaping HookCallback
    ) {
        Task { @Sendable [weak self] in
            guard let self = self else { return }
            await self.hookRegistry.register(entityName: entityName, operation: operation, callback: callback)
            self.log(.info, level: 2, "Registered hook for \(entityName).\(operation.rawValue)")
        }
    }

    /// 移除 Hook
    /// - Parameters:
    ///   - entityName: 实体名称
    ///   - operation: 操作类型
    public func removeHook(
        entityName: String,
        operation: HookOperation
    ) {
        Task { @Sendable [weak self] in
            guard let self = self else { return }
            await self.hookRegistry.remove(entityName: entityName, operation: operation)
            self.log(.info, level: 2, "Removed hook for \(entityName).\(operation.rawValue)")
        }
    }

    /// 启动处理任务
    public func start() {
        guard processingTask == nil else { return }

        processingTask = Task { @Sendable [weak self, coordinator] in
            guard let self = self else { return }

            self.log(.info, level: 1, "Persistent History Tracking Kit V2 Started")

            // 监听 NSPersistentStoreRemoteChange 通知
            let center = NotificationCenter.default
            let name = NSNotification.Name.NSPersistentStoreRemoteChange

            for await _ in center.notifications(named: name, object: coordinator) where !Task.isCancelled {
                await self.handleRemoteChangeNotification()
            }

            self.log(.info, level: 1, "Persistent History Tracking Kit V2 Stopped")
        }

        log(.info, level: 2, "Started transaction processing task")
    }

    /// 停止处理任务
    public func stop() {
        processingTask?.cancel()
        processingTask = nil
        log(.info, level: 2, "Stopped transaction processing task")
    }

    // MARK: - Private Methods

    /// 处理远程变更通知
    private func handleRemoteChangeNotification() async {
        log(.info, level: 2, "Received NSPersistentStoreRemoteChange notification")

        // TODO: 实现时间戳管理和事务处理
        // 这部分需要与 userDefaults 和时间戳管理逻辑集成

        do {
            // 处理新事务
            let count = try await transactionProcessor.processNewTransactions(
                from: allAuthors,
                after: nil, // TODO: 从 UserDefaults 读取上次时间戳
                mergeInto: contexts,
                cleanFor: currentAuthor
            )

            log(.info, level: 2, "Processed \(count) transactions")

            // TODO: 更新时间戳到 UserDefaults
        } catch {
            log(.error, level: 1, "Error processing transactions: \(error.localizedDescription)")
        }
    }

    /// 记录日志
    private func log(_ type: PersistentHistoryTrackingKitLogType, level: Int, _ message: String) {
        guard level <= _logLevel else { return }
        logger.log(type: type, message: message)
    }
}

