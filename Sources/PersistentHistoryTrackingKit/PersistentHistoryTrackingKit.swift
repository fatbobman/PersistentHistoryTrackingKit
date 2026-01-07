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

/// V2: Actor-based persistent history tracking kit.
public final class PersistentHistoryTrackingKit: @unchecked Sendable {
    // MARK: - Properties

    /// Log verbosity level from 0–2 (0 disables logging, 2 is the most verbose).
    /// - Note: In V2 the log level is fixed at initialization time.
    public var logLevel: Int {
        _logLevel
    }

    /// Current author identifier.
    private let currentAuthor: String

    /// All authors to monitor.
    private let allAuthors: [String]

    /// Hook registry.
    private let hookRegistry: HookRegistryActor

    /// Transaction processor.
    /// Note: Internal for test visibility.
    let transactionProcessor: TransactionProcessorActor

    /// Cached log level value (0–2, where 0 disables logging).
    private let _logLevel: Int

    /// Contexts that receive merged transactions.
    private let contexts: [NSManagedObjectContext]

    /// Whether CloudKit mirroring authors are included.
    private let includingCloudKitMirroring: Bool

    /// CloudKit mirroring authors
    private static let cloudMirrorAuthors = ["NSCloudKitMirroringDelegate.import"]

    /// Background processing task.
    private var processingTask: Task<Void, Never>?

    /// Persistent container (used to build manual cleaners).
    private let container: NSPersistentContainer

    /// Persistent store coordinator.
    private let coordinator: NSPersistentStoreCoordinator

    /// Logger instance.
    private let logger: PersistentHistoryTrackingKitLoggerProtocol

    /// UserDefaults used to persist timestamps.
    /// ⚠️ UserDefaults is not Sendable but is thread-safe in practice.
    private let userDefaults: UserDefaults

    /// Key prefix for timestamp storage.
    private let uniqueString: String

    /// Maximum retention duration (seconds).
    private let maximumDuration: TimeInterval

    /// Authors participating in a batch job (excluded from cleanup thresholds).
    private let batchAuthors: [String]

    /// Timestamp manager for reading/updating author timestamps.
    private let timestampManager: TransactionTimestampManager

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
        autoStart: Bool = true)
    {
        self.currentAuthor = currentAuthor
        self.allAuthors = allAuthors
        self.container = container
        coordinator = container.persistentStoreCoordinator
        self.logger = logger ?? DefaultLogger()
        _logLevel = logLevel
        self.contexts = contexts ?? [container.viewContext]
        self.userDefaults = userDefaults
        self.uniqueString = uniqueString
        self.maximumDuration = maximumDuration
        self.batchAuthors = batchAuthors
        self.includingCloudKitMirroring = includingCloudKitMirroring
        if includingCloudKitMirroring {
            self.logger.log(
                type: .notice,
                message: "⚠️ Cleaning while including CloudKit mirroring authors can corrupt cloud-sync data. Proceed only if you understand the risks.")
        }

        // Instantiate helper actors.
        hookRegistry = HookRegistryActor()

        // Build the timestamp manager.
        timestampManager = TransactionTimestampManager(
            userDefaults: userDefaults,
            maximumDuration: maximumDuration,
            uniqueString: uniqueString)

        transactionProcessor = TransactionProcessorActor(
            container: container,
            hookRegistry: hookRegistry,
            cleanStrategy: cleanStrategy,
            timestampManager: timestampManager)

        if autoStart {
            start()
        }
    }

    deinit {
        stop()
    }

    // MARK: - Public Methods - Observer Hooks

    /// Register an Observer Hook (notification/monitoring only, no data changes).
    /// - Parameters:
    ///   - entityName: Entity name.
    ///   - operation: Operation type.
    ///   - callback: Callback.
    /// - Returns: UUID that can be used to remove this specific hook.
    @discardableResult
    public func registerObserver(
        entityName: String,
        operation: HookOperation,
        callback: @escaping HookCallback) async -> UUID
    {
        let id = await hookRegistry.registerObserver(
            entityName: entityName,
            operation: operation,
            callback: callback)
        log(.info, level: 2, "Registered observer hook for \(entityName).\(operation.rawValue) (ID: \(id))")
        return id
    }

    /// Remove a specific Observer Hook by its UUID.
    /// - Parameter id: The UUID of the hook to remove.
    /// - Returns: Whether the hook was successfully removed.
    @discardableResult
    public func removeObserver(id: UUID) async -> Bool {
        let removed = await hookRegistry.removeObserver(id: id)
        if removed {
            log(.info, level: 2, "Removed observer hook (ID: \(id))")
        } else {
            log(.notice, level: 2, "Failed to remove observer hook (ID: \(id)) - not found")
        }
        return removed
    }

    /// Remove all Observer Hooks for a specific entity and operation.
    /// - Parameters:
    ///   - entityName: Entity name.
    ///   - operation: Operation type.
    public func removeObserver(entityName: String, operation: HookOperation) async {
        await hookRegistry.removeObserver(entityName: entityName, operation: operation)
        log(.info, level: 2, "Removed all observer hooks for \(entityName).\(operation.rawValue)")
    }

    /// Remove all registered Observer Hooks.
    public func removeAllObservers() async {
        await hookRegistry.removeAllObservers()
        log(.info, level: 2, "Removed all observer hooks")
    }

    // MARK: - Deprecated Observer Hook API

    /// Register an Observer Hook (notification/monitoring only, no data changes).
    /// - Parameters:
    ///   - entityName: Entity name.
    ///   - operation: Operation type.
    ///   - callback: Callback.
    /// - Note: Deprecated. Use `registerObserver(entityName:operation:callback:) async -> UUID` instead.
    @available(*, deprecated, message: "Use registerObserver(entityName:operation:callback:) async -> UUID instead")
    public func registerHook(
        entityName: String,
        operation: HookOperation,
        callback: @escaping HookCallback)
    {
        Task { @Sendable [weak self] in
            guard let self else { return }
            _ = await registerObserver(
                entityName: entityName,
                operation: operation,
                callback: callback)
        }
    }

    /// Remove an Observer Hook.
    /// - Parameters:
    ///   - entityName: Entity name.
    ///   - operation: Operation type.
    /// - Note: Deprecated. Use `removeObserver(entityName:operation:) async` instead.
    @available(*, deprecated, message: "Use removeObserver(entityName:operation:) async instead")
    public func removeHook(
        entityName: String,
        operation: HookOperation)
    {
        Task { @Sendable [weak self] in
            guard let self else { return }
            await removeObserver(entityName: entityName, operation: operation)
        }
    }

    // MARK: - Merge Hook API

    /// Register a Merge Hook (pipeline style for custom merge logic).
    /// - Parameters:
    ///   - before: Optional hook ID to insert before; appended to the end if nil.
    ///   - callback: Callback receiving `MergeHookInput`.
    /// - Returns: Hook UUID for later removal.
    @discardableResult
    public func registerMergeHook(
        before hookId: UUID? = nil,
        callback: @escaping MergeHookCallback) async -> UUID
    {
        let id = await transactionProcessor.registerMergeHook(before: hookId, callback: callback)
        log(.info, level: 2, "Registered merge hook: \(id)")
        return id
    }

    /// Remove a specific Merge Hook.
    /// - Parameter hookId: Hook UUID.
    /// - Returns: Whether the hook was removed.
    @discardableResult
    public func removeMergeHook(id hookId: UUID) async -> Bool {
        let result = await transactionProcessor.removeMergeHook(id: hookId)
        log(.info, level: 2, "Removed merge hook: \(hookId), success: \(result)")
        return result
    }

    /// Remove every registered Merge Hook.
    public func removeAllMergeHooks() async {
        await transactionProcessor.removeAllMergeHooks()
        log(.info, level: 2, "Removed all merge hooks")
    }

    /// Create a manual cleaner actor.
    ///
    /// Usage example:
    /// ```swift
    /// let kit = PersistentHistoryTrackingKit(...)
    /// let cleaner = kit.cleanerBuilder()
    ///
    /// // Whenever cleanup is appropriate (e.g., when the app moves to background)
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
            logLevel: _logLevel)
    }

    /// Start the background processing task.
    public func start() {
        guard processingTask == nil else { return }

        processingTask = Task { @Sendable [weak self, coordinator] in
            guard let self else { return }

            log(.info, level: 1, "Persistent History Tracking Kit V2 Started")

            // Listen for NSPersistentStoreRemoteChange notifications.
            let center = NotificationCenter.default
            let name = NSNotification.Name.NSPersistentStoreRemoteChange

            for await _ in center.notifications(named: name, object: coordinator)
                where !Task.isCancelled
            {
                await self.handleRemoteChangeNotification()
            }

            log(.info, level: 1, "Persistent History Tracking Kit V2 Stopped")
        }

        log(.info, level: 2, "Started transaction processing task")
    }

    /// Stop the background processing task.
    public func stop() {
        processingTask?.cancel()
        processingTask = nil
        log(.info, level: 2, "Stopped transaction processing task")
    }

    // MARK: - Private Methods

    /// Handle remote change notifications.
    private func handleRemoteChangeNotification() async {
        log(.info, level: 2, "Received NSPersistentStoreRemoteChange notification")

        // Read the last processed timestamp.
        let lastTimestamp = timestampManager.getLastHistoryTransactionTimestamp(for: currentAuthor)

        // Determine which authors to process (add CloudKit authors when needed).
        let authorsToProcess = includingCloudKitMirroring
            ? Array(Set(allAuthors + Self.cloudMirrorAuthors))
            : allAuthors

        do {
            // Process new transactions and update timestamps automatically.
            let count = try await transactionProcessor
                .processNewTransactionsWithTimestampManagement(
                    from: authorsToProcess,
                    after: lastTimestamp,
                    mergeInto: contexts,
                    currentAuthor: currentAuthor,
                    batchAuthors: batchAuthors)

            log(.info, level: 2, "Processed \(count) transactions")
        } catch {
            log(.error, level: 1, "Error processing transactions: \(error.localizedDescription)")
        }
    }

    /// Log helper respecting the configured verbosity.
    private func log(_ type: PersistentHistoryTrackingKitLogType, level: Int, _ message: String) {
        guard level <= _logLevel else { return }
        logger.log(type: type, message: message)
    }
}
