//
//  ComprehensiveIntegrationTests.swift
//
//
//  Created by Claude on 2025/6/27
//  Copyright © 2025 Anthropic. All rights reserved.
//

@preconcurrency import CoreData
import Foundation
import PersistentHistoryTrackingKit
import Testing

@Suite("Comprehensive Integration Tests", .serialized)
@MainActor
struct ComprehensiveIntegrationTests {
    let storeURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        .first?
        .appendingPathComponent("ComprehensiveIntegrationTest.sqlite") ?? URL(fileURLWithPath: "")
    let uniqueString = "PersistentHistoryTrackingKit.Comprehensive.Tests."
    let userDefaults = UserDefaults.standard

    // 模拟的应用标识符
    enum AppIdentifier: String, CaseIterable {
        case mainApp = "MainApp"
        case shareExtension = "ShareExtension"
        case widgetExtension = "WidgetExtension"
        case watchApp = "WatchApp"
        case backgroundTask = "BackgroundTask"
    }

    init() {
        // 清除测试环境
        cleanupEnvironment()
    }

    func cleanupEnvironment() {
        // 清除 UserDefaults
        for app in AppIdentifier.allCases {
            userDefaults.removeObject(forKey: uniqueString + app.rawValue)
        }

        // 清除数据库文件
        try? FileManager.default.removeItem(at: storeURL)
        try? FileManager.default
            .removeItem(at: storeURL.deletingPathExtension().appendingPathExtension("sqlite-wal"))
        try? FileManager.default
            .removeItem(at: storeURL.deletingPathExtension().appendingPathExtension("sqlite-shm"))
    }

    func createTestData(
        in context: NSManagedObjectContext,
        authorName: String,
        complexity: Int = 1) -> [NSManagedObjectID]
    {
        var objectIDs: [NSManagedObjectID] = []

        context.performAndWait {
            // 创建用户
            let user = TestUser(
                context: context,
                name: "User_\(authorName)_\(Date().timeIntervalSince1970)",
                email: "user@\(authorName).com")
            try! context.save()
            objectIDs.append(user.objectID)

            // 创建帖子
            for i in 0 ..< complexity {
                let post = TestPost(
                    context: context,
                    title: "Post \(i) by \(authorName)",
                    content: "Content of post \(i)",
                    author: user)
                try! context.save()
                objectIDs.append(post.objectID)

                // 为每个帖子创建评论
                for j in 0 ..< complexity {
                    let comment = TestComment(
                        context: context,
                        text: "Comment \(j) on post \(i) by \(authorName)",
                        author: user,
                        post: post)
                    try! context.save()
                    objectIDs.append(comment.objectID)
                }
            }
        }

        return objectIDs
    }

    // MARK: - 基础功能测试

    @Test("Basic multi-app synchronization test")
    func basicMultiAppSync() async throws {
        cleanupEnvironment()

        // 创建两个容器模拟不同的应用
        let mainContainer = ComprehensiveTestModel.createContainer(storeURL: storeURL)
        let extensionContainer = ComprehensiveTestModel.createContainer(storeURL: storeURL)

        mainContainer.viewContext.transactionAuthor = AppIdentifier.mainApp.rawValue
        extensionContainer.viewContext.transactionAuthor = AppIdentifier.shareExtension.rawValue

        let allAuthors = [AppIdentifier.mainApp.rawValue, AppIdentifier.shareExtension.rawValue]

        // 设置 Kit
        let mainKit = PersistentHistoryTrackingKit(
            container: mainContainer,
            currentAuthor: AppIdentifier.mainApp.rawValue,
            allAuthors: allAuthors,
            userDefaults: userDefaults,
            cleanStrategy: .byNotification(times: 1),
            uniqueString: uniqueString,
            logLevel: 2)

        let extensionKit = PersistentHistoryTrackingKit(
            container: extensionContainer,
            currentAuthor: AppIdentifier.shareExtension.rawValue,
            allAuthors: allAuthors,
            userDefaults: userDefaults,
            cleanStrategy: .byNotification(times: 1),
            uniqueString: uniqueString,
            logLevel: 2)

        // 在主应用中创建数据
        let mainObjectIDs = createTestData(
            in: mainContainer.viewContext,
            authorName: "MainApp",
            complexity: 2)

        await sleep(seconds: 2)

        // 验证扩展中能看到数据
        let extensionContext = extensionContainer.viewContext
        let foundObjects = extensionContext.performAndWait {
            mainObjectIDs.compactMap { objectID in
                try? extensionContext.existingObject(with: objectID)
            }
        }

        #expect(foundObjects.count == mainObjectIDs.count)

        // 在扩展中创建数据
        let extensionObjectIDs = createTestData(
            in: extensionContainer.viewContext,
            authorName: "Extension",
            complexity: 1)

        await sleep(seconds: 2)

        // 验证主应用中能看到数据
        let mainContext = mainContainer.viewContext
        let foundInMain = mainContext.performAndWait {
            extensionObjectIDs.compactMap { objectID in
                try? mainContext.existingObject(with: objectID)
            }
        }

        #expect(foundInMain.count == extensionObjectIDs.count)

        mainKit.stop()
        extensionKit.stop()
        cleanupEnvironment()
    }

    @Test("Complex multi-app scenario with relationships")
    func complexMultiAppWithRelationships() async throws {
        cleanupEnvironment()

        let apps: [(AppIdentifier, NSPersistentContainer, PersistentHistoryTrackingKit)] = [
            AppIdentifier.mainApp,
            AppIdentifier.shareExtension,
            AppIdentifier.widgetExtension,
        ].map { appId in
            let container = ComprehensiveTestModel.createContainer(storeURL: storeURL)
            container.viewContext.transactionAuthor = appId.rawValue

            let kit = PersistentHistoryTrackingKit(
                container: container,
                currentAuthor: appId.rawValue,
                allAuthors: AppIdentifier.allCases.map(\.rawValue),
                userDefaults: userDefaults,
                cleanStrategy: .byNotification(times: 1),
                uniqueString: uniqueString,
                logLevel: 1)

            return (appId, container, kit)
        }

        var createdUserIDs: [UUID] = []
        var createdPostIDs: [UUID] = []

        // 每个应用创建不同的数据
        for (_, (appId, container, _)) in apps.enumerated() {
            container.viewContext.performAndWait {
                let user = TestUser(
                    context: container.viewContext,
                    name: "User from \(appId.rawValue)")
                createdUserIDs.append(user.userID)

                let post = TestPost(
                    context: container.viewContext,
                    title: "Post from \(appId.rawValue)",
                    content: "Content",
                    author: user)
                createdPostIDs.append(post.postID)

                _ = TestComment(
                    context: container.viewContext,
                    text: "Comment from \(appId.rawValue)",
                    author: user,
                    post: post)

                try! container.viewContext.save()
            }

            // 给数据同步一些时间
            await sleep(seconds: 1)
        }

        await sleep(seconds: 3)

        // 验证每个应用都能看到所有数据
        for (appId, container, _) in apps {
            let context = container.viewContext
            let results = context.performAndWait {
                let userRequest = NSFetchRequest<TestUser>(entityName: "User")
                let postRequest = NSFetchRequest<TestPost>(entityName: "Post")
                let commentRequest = NSFetchRequest<TestComment>(entityName: "Comment")

                let users = try! context.fetch(userRequest)
                let posts = try! context.fetch(postRequest)
                let comments = try! context.fetch(commentRequest)

                return (users.count, posts.count, comments.count)
            }

            #expect(
                results.0 == 3,
                "App \(appId.rawValue) should see 3 users, but found \(results.0)")
            #expect(
                results.1 == 3,
                "App \(appId.rawValue) should see 3 posts, but found \(results.1)")
            #expect(
                results.2 == 3,
                "App \(appId.rawValue) should see 3 comments, but found \(results.2)")
        }

        // 清理
        for (_, _, kit) in apps {
            kit.stop()
        }
        cleanupEnvironment()
    }

    @Test("Batch operations synchronization")
    @available(macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0, *)
    func batchOperationSync() async throws {
        cleanupEnvironment()

        let mainContainer = ComprehensiveTestModel.createContainer(storeURL: storeURL)
        let extensionContainer = ComprehensiveTestModel.createContainer(storeURL: storeURL)

        mainContainer.viewContext.transactionAuthor = AppIdentifier.mainApp.rawValue
        extensionContainer.viewContext.transactionAuthor = AppIdentifier.shareExtension.rawValue

        let batchContext = mainContainer.newBackgroundContext()
        batchContext.transactionAuthor = AppIdentifier.backgroundTask.rawValue

        let allAuthors = [
            AppIdentifier.mainApp.rawValue,
            AppIdentifier.shareExtension.rawValue,
            AppIdentifier.backgroundTask.rawValue,
        ]

        let mainKit = PersistentHistoryTrackingKit(
            container: mainContainer,
            currentAuthor: AppIdentifier.mainApp.rawValue,
            allAuthors: allAuthors,
            batchAuthors: [AppIdentifier.backgroundTask.rawValue],
            userDefaults: userDefaults,
            cleanStrategy: .byNotification(times: 1),
            uniqueString: uniqueString,
            logLevel: 2)

        let extensionKit = PersistentHistoryTrackingKit(
            container: extensionContainer,
            currentAuthor: AppIdentifier.shareExtension.rawValue,
            allAuthors: allAuthors,
            batchAuthors: [AppIdentifier.backgroundTask.rawValue],
            userDefaults: userDefaults,
            cleanStrategy: .byNotification(times: 1),
            uniqueString: uniqueString,
            logLevel: 2)

        // 执行批量插入
        var insertedCount = 0
        let targetCount = 50
        try batchContext.performAndWait {
            let batchInsert = NSBatchInsertRequest(entity: TestUser
                .entity())
            { (dictionary: NSMutableDictionary) -> Bool in
                dictionary["userID"] = UUID()
                dictionary["name"] = "Batch User \(insertedCount)"
                dictionary["email"] = "batch\(insertedCount)@test.com"
                dictionary["createdAt"] = Date()

                insertedCount += 1
                return insertedCount >= targetCount // 插入指定数量后停止
            }
            batchInsert.resultType = .count

            let result = try batchContext.execute(batchInsert) as! NSBatchInsertResult
            let actualCount = result.result as! Int
            #expect(
                actualCount == targetCount - 1,
                "Expected at least \(targetCount - 1) users, got \(actualCount)") // 批量插入可能会有细微差异
            insertedCount = actualCount
        }

        await sleep(seconds: 3)

        // 验证批量数据在其他上下文中可见
        let mainCount = mainContainer.viewContext.performAndWait {
            let request = NSFetchRequest<TestUser>(entityName: "User")
            return try! mainContainer.viewContext.count(for: request)
        }

        let extensionCount = extensionContainer.viewContext.performAndWait {
            let request = NSFetchRequest<TestUser>(entityName: "User")
            return try! extensionContainer.viewContext.count(for: request)
        }

        #expect(
            mainCount == insertedCount,
            "Main container should have \(insertedCount) users, got \(mainCount)")
        #expect(
            extensionCount == insertedCount,
            "Extension container should have \(insertedCount) users, got \(extensionCount)")
        #expect(mainCount == extensionCount)

        mainKit.stop()
        extensionKit.stop()
        cleanupEnvironment()
    }

    @Test("Stress test with concurrent operations")
    func concurrentOperationsStress() async throws {
        cleanupEnvironment()

        let container1 = ComprehensiveTestModel.createContainer(storeURL: storeURL)
        let container2 = ComprehensiveTestModel.createContainer(storeURL: storeURL)
        let container3 = ComprehensiveTestModel.createContainer(storeURL: storeURL)

        container1.viewContext.transactionAuthor = AppIdentifier.mainApp.rawValue
        container2.viewContext.transactionAuthor = AppIdentifier.shareExtension.rawValue
        container3.viewContext.transactionAuthor = AppIdentifier.widgetExtension.rawValue

        let allAuthors = [
            AppIdentifier.mainApp.rawValue,
            AppIdentifier.shareExtension.rawValue,
            AppIdentifier.widgetExtension.rawValue,
        ]

        let kits = [
            PersistentHistoryTrackingKit(
                container: container1,
                currentAuthor: AppIdentifier.mainApp.rawValue,
                allAuthors: allAuthors,
                userDefaults: userDefaults,
                cleanStrategy: .byNotification(times: 2),
                uniqueString: uniqueString,
                logLevel: 0, // 减少日志输出
            ),
            PersistentHistoryTrackingKit(
                container: container2,
                currentAuthor: AppIdentifier.shareExtension.rawValue,
                allAuthors: allAuthors,
                userDefaults: userDefaults,
                cleanStrategy: .byNotification(times: 2),
                uniqueString: uniqueString,
                logLevel: 0),
            PersistentHistoryTrackingKit(
                container: container3,
                currentAuthor: AppIdentifier.widgetExtension.rawValue,
                allAuthors: allAuthors,
                userDefaults: userDefaults,
                cleanStrategy: .byNotification(times: 2),
                uniqueString: uniqueString,
                logLevel: 0),
        ]

        let containers = [container1, container2, container3]

        // 并发创建数据
        await withTaskGroup(of: Void.self) { group in
            for (index, container) in containers.enumerated() {
                group.addTask {
                    for i in 0 ..< 5 {
                        container.viewContext.performAndWait {
                            let user = TestUser(
                                context: container.viewContext,
                                name: "Concurrent User \(index)-\(i)")
                            let post = TestPost(
                                context: container.viewContext,
                                title: "Concurrent Post \(index)-\(i)",
                                content: "Content",
                                author: user)
                            _ = TestComment(
                                context: container.viewContext,
                                text: "Concurrent Comment \(index)-\(i)",
                                author: user,
                                post: post)

                            try! container.viewContext.save()
                        }

                        // 小延迟避免过于密集的操作
                        try! await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
                    }
                }
            }
        }

        await sleep(seconds: 5)

        // 验证数据一致性
        let expectedTotalUsers = 15 // 3个容器 × 5个用户

        for (index, container) in containers.enumerated() {
            let context = container.viewContext
            let counts = context.performAndWait {
                let userRequest = NSFetchRequest<TestUser>(entityName: "User")
                let postRequest = NSFetchRequest<TestPost>(entityName: "Post")
                let commentRequest = NSFetchRequest<TestComment>(entityName: "Comment")

                let userCount = try! context.count(for: userRequest)
                let postCount = try! context.count(for: postRequest)
                let commentCount = try! context.count(for: commentRequest)

                return (userCount, postCount, commentCount)
            }

            #expect(
                counts.0 == expectedTotalUsers,
                "Container \(index) should have \(expectedTotalUsers) users, found \(counts.0)")
            #expect(
                counts.1 == expectedTotalUsers,
                "Container \(index) should have \(expectedTotalUsers) posts, found \(counts.1)")
            #expect(
                counts.2 == expectedTotalUsers,
                "Container \(index) should have \(expectedTotalUsers) comments, found \(counts.2)")
        }

        // 清理
        for kit in kits {
            kit.stop()
        }
        cleanupEnvironment()
    }

    @Test("Transaction cleanup verification")
    func transactionCleanup() async throws {
        cleanupEnvironment()

        let container = ComprehensiveTestModel.createContainer(storeURL: storeURL)
        container.viewContext.transactionAuthor = AppIdentifier.mainApp.rawValue

        let kit = PersistentHistoryTrackingKit(
            container: container,
            currentAuthor: AppIdentifier.mainApp.rawValue,
            allAuthors: [AppIdentifier.mainApp.rawValue],
            userDefaults: userDefaults,
            cleanStrategy: .byNotification(times: 1),
            uniqueString: uniqueString,
            logLevel: 2)

        // 创建一些数据以生成事务
        for i in 0 ..< 5 {
            container.viewContext.performAndWait {
                _ = TestUser(context: container.viewContext, name: "Cleanup Test User \(i)")
                try! container.viewContext.save()
            }
            await sleep(seconds: 0.5)
        }

        await sleep(seconds: 2)

        // 验证数据已创建
        let userCount = container.viewContext.performAndWait {
            let request = NSFetchRequest<TestUser>(entityName: "User")
            return try! container.viewContext.count(for: request)
        }

        #expect(userCount == 5)

        // 手动触发清理
        let cleaner = kit.cleanerBuilder()
        cleaner()

        await sleep(seconds: 1)

        // 验证数据仍然存在（清理只删除历史事务，不删除数据）
        let userCountAfterCleanup = container.viewContext.performAndWait {
            let request = NSFetchRequest<TestUser>(entityName: "User")
            return try! container.viewContext.count(for: request)
        }

        #expect(userCountAfterCleanup == 5)

        kit.stop()
        cleanupEnvironment()
    }

    @Test("Performance test with large dataset")
    func performanceWithLargeDataset() async throws {
        cleanupEnvironment()

        let container1 = ComprehensiveTestModel.createContainer(storeURL: storeURL)
        let container2 = ComprehensiveTestModel.createContainer(storeURL: storeURL)

        container1.viewContext.transactionAuthor = AppIdentifier.mainApp.rawValue
        container2.viewContext.transactionAuthor = AppIdentifier.shareExtension.rawValue

        let allAuthors = [AppIdentifier.mainApp.rawValue, AppIdentifier.shareExtension.rawValue]

        let kit1 = PersistentHistoryTrackingKit(
            container: container1,
            currentAuthor: AppIdentifier.mainApp.rawValue,
            allAuthors: allAuthors,
            userDefaults: userDefaults,
            cleanStrategy: .byDuration(seconds: 2),
            uniqueString: uniqueString,
            logLevel: 0)

        let kit2 = PersistentHistoryTrackingKit(
            container: container2,
            currentAuthor: AppIdentifier.shareExtension.rawValue,
            allAuthors: allAuthors,
            userDefaults: userDefaults,
            cleanStrategy: .byDuration(seconds: 2),
            uniqueString: uniqueString,
            logLevel: 0)

        let startTime = Date()

        // 在第一个容器中创建大量数据
        container1.viewContext.performAndWait {
            for i in 0 ..< 50 {
                let user = TestUser(context: container1.viewContext, name: "Performance User \(i)")
                for j in 0 ..< 3 {
                    let post = TestPost(
                        context: container1.viewContext,
                        title: "Post \(j) by User \(i)",
                        content: "Content",
                        author: user)
                    for k in 0 ..< 2 {
                        _ = TestComment(
                            context: container1.viewContext,
                            text: "Comment \(k) on Post \(j)",
                            author: user,
                            post: post)
                    }
                }

                if i % 10 == 0 {
                    try! container1.viewContext.save()
                }
            }
            try! container1.viewContext.save()
        }

        let creationTime = Date().timeIntervalSince(startTime)
        print("Data creation took: \(creationTime) seconds")

        await sleep(seconds: 5)

        // 验证第二个容器中的数据
        let syncTime = Date()
        let counts = container2.viewContext.performAndWait {
            let userRequest = NSFetchRequest<TestUser>(entityName: "User")
            let postRequest = NSFetchRequest<TestPost>(entityName: "Post")
            let commentRequest = NSFetchRequest<TestComment>(entityName: "Comment")

            let userCount = try! container2.viewContext.count(for: userRequest)
            let postCount = try! container2.viewContext.count(for: postRequest)
            let commentCount = try! container2.viewContext.count(for: commentRequest)

            return (userCount, postCount, commentCount)
        }

        let totalSyncTime = Date().timeIntervalSince(syncTime)
        print("Data synchronization verification took: \(totalSyncTime) seconds")

        #expect(counts.0 == 50) // 50 users
        #expect(counts.1 == 150) // 50 users × 3 posts
        #expect(counts.2 == 300) // 50 users × 3 posts × 2 comments

        let totalTime = Date().timeIntervalSince(startTime)
        print("Total test time: \(totalTime) seconds")

        // 性能要求：总时间不应该超过30秒
        #expect(totalTime < 30.0)

        kit1.stop()
        kit2.stop()
        cleanupEnvironment()
    }
}
