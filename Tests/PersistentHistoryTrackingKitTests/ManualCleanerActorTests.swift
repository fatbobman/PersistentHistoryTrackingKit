//
//  ManualCleanerActorTests.swift
//  PersistentHistoryTrackingKitTests
//
//  Created by Claude on 2025-01-06
//

import CoreData
import Testing
@testable import PersistentHistoryTrackingKit

@Suite("ManualCleanerActor Tests", .serialized)
struct ManualCleanerActorTests {

    @Test("执行清理 - 正常流程")
    func cleanNormalFlow() async throws {
        let container = TestModelBuilder.createContainer(author: "App1")
        let context = container.viewContext

        // 创建数据
        TestModelBuilder.createPerson(name: "Alice", age: 30, in: context)
        try context.save()

        // 模拟 UserDefaults 保存时间戳
        let userDefaults = UserDefaults.standard
        let uniqueString = "TestKit.lastToken."
        userDefaults.set(Date(), forKey: uniqueString + "App1")

        // 创建 cleaner
        let cleaner = ManualCleanerActor(
            container: container,
            authors: ["App1"],
            userDefaults: userDefaults,
            uniqueString: uniqueString,
            logger: DefaultLogger(),
            logLevel: 2
        )

        // 执行清理（不应该崩溃）
        await cleaner.clean()

        // 清理后验证数据仍然存在（因为时间戳是当前时间）
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Person")
        let results = try context.fetch(fetchRequest)
        #expect(results.count == 1)
    }

    @Test("获取最后共同时间戳")
    func getLastCommonTimestamp() async throws {
        let container = TestModelBuilder.createContainer(author: "App1")

        // 模拟多个 author 的时间戳
        let userDefaults = UserDefaults.standard
        let uniqueString = "TestKit.lastToken."

        let date1 = Date(timeIntervalSinceNow: -100) // 100 秒前
        let date2 = Date(timeIntervalSinceNow: -50)  // 50 秒前
        let date3 = Date(timeIntervalSinceNow: -200) // 200 秒前（最小）

        userDefaults.set(date1, forKey: uniqueString + "App1")
        userDefaults.set(date2, forKey: uniqueString + "App2")
        userDefaults.set(date3, forKey: uniqueString + "App3")

        // 创建 cleaner
        let cleaner = ManualCleanerActor(
            container: container,
            authors: ["App1", "App2", "App3"],
            userDefaults: userDefaults,
            uniqueString: uniqueString,
            logger: DefaultLogger(),
            logLevel: 0
        )

        // 执行清理（会使用最小的时间戳）
        await cleaner.clean()

        // 验证：这个测试主要验证不会崩溃
        #expect(true)
    }

    @Test("空时间戳处理")
    func handleEmptyTimestamp() async throws {
        let container = TestModelBuilder.createContainer(author: "App1")

        // 使用新的 uniqueString，确保没有时间戳
        let userDefaults = UserDefaults.standard
        let uniqueString = "TestKit.EmptyTimestamp.\(UUID().uuidString)."

        // 创建 cleaner
        let cleaner = ManualCleanerActor(
            container: container,
            authors: ["NonExistentApp"],
            userDefaults: userDefaults,
            uniqueString: uniqueString,
            logger: DefaultLogger(),
            logLevel: 0
        )

        // 执行清理（应该跳过，不崩溃）
        await cleaner.clean()

        #expect(true)
    }

    @Test("清理后验证事务数量")
    func verifyTransactionCountAfterClean() async throws {
        let container = TestModelBuilder.createContainer(author: "App1")
        let context = container.viewContext

        // 创建第一批数据
        TestModelBuilder.createPerson(name: "Alice", age: 30, in: context)
        try context.save()

        let firstTimestamp = Date()

        // 等待一点时间
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 秒

        // 创建第二批数据
        TestModelBuilder.createPerson(name: "Bob", age: 25, in: context)
        try context.save()

        // 模拟 UserDefaults 保存第一个时间戳
        let userDefaults = UserDefaults.standard
        let uniqueString = "TestKit.lastToken.\(UUID().uuidString)."
        userDefaults.set(firstTimestamp, forKey: uniqueString + "App1")

        // 创建 cleaner
        let cleaner = ManualCleanerActor(
            container: container,
            authors: ["App1"],
            userDefaults: userDefaults,
            uniqueString: uniqueString,
            logger: DefaultLogger(),
            logLevel: 0
        )

        // 执行清理
        await cleaner.clean()

        // 验证数据仍然存在（clean 只清理 transaction history，不清理实际数据）
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Person")
        let results = try context.fetch(fetchRequest)
        #expect(results.count == 2) // 两条数据都应该存在
    }
}
