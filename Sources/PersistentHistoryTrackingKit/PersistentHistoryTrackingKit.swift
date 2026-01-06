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
    /// Note: 标记为 internal 以便测试访问
    internal let transactionProcessor: TransactionProcessorActor

    /// 日志显示等级，从 0-2 级。0 关闭 2 最详尽
    private let _logLevel: Int

    /// 需要合并的上下文列表
    private let contexts: [NSManagedObjectContext]

    /// 处理任务
    private var processingTask: Task<Void, Never>?

    /// 持久化存储容器（用于创建 cleanerBuilder）
    private let container: NSPersistentContainer

    /// 持久化存储协调器
    private let coordinator: NSPersistentStoreCoordinator

    /// 日志管理器
    private let logger: PersistentHistoryTrackingKitLoggerProtocol

    /// UserDefaults 用于保存时间戳
    /// ⚠️ UserDefaults 非 Sendable，但本身是线程安全的
    private let userDefaults: UserDefaults

    /// 时间戳保存的 Key 前缀
    private let uniqueString: String

    /// 最大持续时间（秒）
    private let maximumDuration: TimeInterval

    /// 批量操作的 authors
    private let batchAuthors: [String]

    // MARK: - Initialization

    public init(
        container: NSPersistentContainer,
        contexts: [NSManagedObjectContext]? = nil,
        currentAuthor: String,
        allAuthors: [String],
        includingCloudKitMirroring: Bool = false,
        batchAuthors: [String] = [],
        userDefaults: UserDefaults,
        cleanStrategy: TransactionCleanStrategy = .none,
        maximumDuration: TimeInterval = 60 * 60 * 24 * 7,
        uniqueString: String = "PersistentHistoryTrackingKit.lastToken.",
        logger: PersistentHistoryTrackingKitLoggerProtocol? = nil,
        logLevel: Int = 1,
        autoStart: Bool = true
    ) {
        self.currentAuthor = currentAuthor
        self.allAuthors = allAuthors
        self.container = container
        self.coordinator = container.persistentStoreCoordinator
        self.logger = logger ?? DefaultLogger()
        self._logLevel = logLevel
        self.contexts = contexts ?? [container.viewContext]
        self.userDefaults = userDefaults
        self.uniqueString = uniqueString
        self.maximumDuration = maximumDuration
        self.batchAuthors = batchAuthors

        // 创建 actors
        self.hookRegistry = HookRegistryActor()
        self.transactionProcessor = TransactionProcessorActor(
            container: container,
            hookRegistry: hookRegistry,
            cleanStrategy: cleanStrategy
        )

        if autoStart {
            start()
        }
    }

    deinit {
        stop()
    }

    // MARK: - Public Methods

    /// 注册 Observer Hook（用于通知/监听，不影响数据）
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
            await self.hookRegistry.registerObserver(entityName: entityName, operation: operation, callback: callback)
            self.log(.info, level: 2, "Registered observer hook for \(entityName).\(operation.rawValue)")
        }
    }

    /// 移除 Observer Hook
    /// - Parameters:
    ///   - entityName: 实体名称
    ///   - operation: 操作类型
    public func removeHook(
        entityName: String,
        operation: HookOperation
    ) {
        Task { @Sendable [weak self] in
            guard let self = self else { return }
            await self.hookRegistry.removeObserver(entityName: entityName, operation: operation)
            self.log(.info, level: 2, "Removed observer hook for \(entityName).\(operation.rawValue)")
        }
    }

    // MARK: - Merge Hook API

    /// 注册 Merge Hook（管道模式，可自定义合并逻辑）
    /// - Parameters:
    ///   - before: 可选，插入到此 hook 之前；如果为 nil，添加到末尾
    ///   - callback: 回调函数，接收 MergeHookInput 参数
    /// - Returns: 该 hook 的 UUID，用于后续移除
    @discardableResult
    public func registerMergeHook(
        before hookId: UUID? = nil,
        callback: @escaping MergeHookCallback
    ) async -> UUID {
        let id = await transactionProcessor.registerMergeHook(before: hookId, callback: callback)
        log(.info, level: 2, "Registered merge hook: \(id)")
        return id
    }

    /// 移除指定的 Merge Hook
    /// - Parameter hookId: hook 的 UUID
    /// - Returns: 是否成功移除
    @discardableResult
    public func removeMergeHook(id hookId: UUID) async -> Bool {
        let result = await transactionProcessor.removeMergeHook(id: hookId)
        log(.info, level: 2, "Removed merge hook: \(hookId), success: \(result)")
        return result
    }

    /// 移除所有 Merge Hook
    public func removeAllMergeHooks() async {
        await transactionProcessor.removeAllMergeHooks()
        log(.info, level: 2, "Removed all merge hooks")
    }

    /// 创建手动清理器
    ///
    /// 使用示例：
    /// ```swift
    /// let kit = PersistentHistoryTrackingKit(...)
    /// let cleaner = kit.cleanerBuilder()
    ///
    /// // 在需要清理的地方（比如 app 进入后台）
    /// Task {
    ///     await cleaner.clean()
    /// }
    /// ```
    public func cleanerBuilder() -> ManualCleanerActor {
        ManualCleanerActor(
            container: container,
            authors: allAuthors,
            userDefaults: userDefaults,
            uniqueString: uniqueString,
            logger: logger,
            logLevel: _logLevel
        )
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

        // TODO: 从 UserDefaults 读取上次处理的时间戳
        let lastTimestamp = getLastTimestampFromUserDefaults(for: currentAuthor)

        do {
            // 处理新事务（排除当前 author）
            let count = try await transactionProcessor.processNewTransactions(
                from: allAuthors,
                after: lastTimestamp,
                mergeInto: contexts,
                currentAuthor: currentAuthor,
                cleanBeforeTimestamp: nil // TODO: 计算需要清理的时间戳
            )

            log(.info, level: 2, "Processed \(count) transactions")

            // 如果处理了事务，更新时间戳
            if count > 0 {
                if let newTimestamp = try? await transactionProcessor.getLastTransactionTimestamp(for: currentAuthor) {
                    updateLastTimestampToUserDefaults(for: currentAuthor, to: newTimestamp)
                    log(.info, level: 2, "Updated timestamp to \(newTimestamp)")
                }
            }
        } catch {
            log(.error, level: 1, "Error processing transactions: \(error.localizedDescription)")
        }
    }

    /// 从 UserDefaults 读取上次处理的时间戳
    private func getLastTimestampFromUserDefaults(for author: String) -> Date? {
        let key = uniqueString + author
        return userDefaults.object(forKey: key) as? Date
    }

    /// 更新时间戳到 UserDefaults
    private func updateLastTimestampToUserDefaults(for author: String, to date: Date) {
        let key = uniqueString + author
        userDefaults.set(date, forKey: key)
    }

    /// 记录日志
    private func log(_ type: PersistentHistoryTrackingKitLogType, level: Int, _ message: String) {
        guard level <= _logLevel else { return }
        logger.log(type: type, message: message)
    }
}

