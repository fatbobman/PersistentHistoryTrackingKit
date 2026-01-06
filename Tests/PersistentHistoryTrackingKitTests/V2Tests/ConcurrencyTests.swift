//
//  ConcurrencyTests.swift
//  PersistentHistoryTrackingKitTests
//
//  Created by Claude on 2025-01-06
//

import CoreData
import Testing
@testable import PersistentHistoryTrackingKit

@Suite("Concurrency Safety Tests")
struct ConcurrencyTests {

    @Test("多线程并发写入")
    func concurrentWrites() async throws {
        let container = TestModelBuilder.createContainer(author: "App1")

        // 并发创建多个 context 并写入数据
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<5 {
                group.addTask {
                    let context = container.newBackgroundContext()
                    context.transactionAuthor = "App\(i)"

                    do {
                        TestModelBuilder.createPerson(
                            name: "Person\(i)",
                            age: Int32(20 + i),
                            in: context
                        )
                        try context.save()
                    } catch {
                        Issue.record("Failed to save in concurrent write: \(error)")
                    }
                }
            }
        }

        // 验证所有数据都写入成功
        let context = container.viewContext
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Person")
        let results = try context.fetch(fetchRequest)
        #expect(results.count == 5)
    }

    @Test("多 Actor 并发访问")
    func multipleActorsConcurrentAccess() async throws {
        let container = TestModelBuilder.createContainer(author: "App1")
        let context = container.viewContext

        // 创建初始数据
        for i in 0..<10 {
            TestModelBuilder.createPerson(name: "Person\(i)", age: Int32(20 + i), in: context)
        }
        try context.save()

        // 创建多个 processor 并发访问
        let hookRegistry = HookRegistryActor()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<3 {
                group.addTask {
                    let processor = TransactionProcessorActor(
                        container: container,
                        hookRegistry: hookRegistry,
                        cleanStrategy: .none
                    )

                    do {
                        // 使用 Actor 内部的测试方法
                        let result = try await processor.testFetchTransactionsExcludesAuthor(
                            from: ["App1"],
                            after: nil,
                            excludeAuthor: nil
                        )
                        // 验证至少获取到了数据
                        guard result.count >= 1 else {
                            Issue.record("Expected at least 1 transaction")
                            return
                        }
                    } catch {
                        Issue.record("Failed to fetch in concurrent access: \(error)")
                    }
                }
            }
        }

        #expect(true) // 主要验证不会崩溃
    }

    @Test("Clean 和 Fetch 并发")
    func cleanAndFetchConcurrent() async throws {
        let container = TestModelBuilder.createContainer(author: "App1")
        let context = container.viewContext

        // 创建数据
        TestModelBuilder.createPerson(name: "Alice", age: 30, in: context)
        try context.save()

        let hookRegistry = HookRegistryActor()
        let processor = TransactionProcessorActor(
            container: container,
            hookRegistry: hookRegistry,
            cleanStrategy: .none
        )

        // 并发执行 fetch 和 clean
        await withTaskGroup(of: Void.self) { group in
            // Fetch task
            group.addTask {
                do {
                    for _ in 0..<5 {
                        _ = try await processor.testFetchTransactionsExcludesAuthor(
                            from: ["App1"],
                            after: nil,
                            excludeAuthor: nil
                        )
                    }
                } catch {
                    Issue.record("Failed to fetch: \(error)")
                }
            }

            // Clean task
            group.addTask {
                do {
                    for _ in 0..<5 {
                        _ = try await processor.testCleanTransactions(
                            before: Date(),
                            for: ["App1"],
                            expectedBefore: nil
                        )
                    }
                } catch {
                    Issue.record("Failed to clean: \(error)")
                }
            }
        }

        #expect(true) // 主要验证不会崩溃
    }

    @Test("Hook 并发触发")
    func concurrentHookTriggering() async throws {
        let hookRegistry = HookRegistryActor()

        actor Counter {
            var count = 0
            func increment() { count += 1 }
            func get() -> Int { count }
        }

        let counter = Counter()

        // 注册 Hook
        let callback: HookCallback = { _ in
            await counter.increment()
        }
        await hookRegistry.register(entityName: "Person", operation: .insert, callback: callback)

        // 并发触发 Hook
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    let context = HookContext(
                        entityName: "Person",
                        operation: .insert,
                        objectID: NSManagedObjectID(),
                        objectIDURL: URL(string: "x-coredata://test/\(i)")!,
                        tombstone: nil,
                        timestamp: Date(),
                        author: "TestAuthor"
                    )
                    await hookRegistry.trigger(context: context)
                }
            }
        }

        // 验证所有 Hook 都被触发
        let finalCount = await counter.get()
        #expect(finalCount == 100)
    }

    @Test("多个 Kit 实例并发运行")
    func multipleKitInstancesConcurrent() async throws {
        let container = TestModelBuilder.createContainer(author: "App1")

        // 创建多个 Kit 实例
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<3 {
                group.addTask {
                    let userDefaults = UserDefaults.standard
                    let uniqueString = "TestKit.MultiInstance.\(i).\(UUID().uuidString)."

                    let kit = PersistentHistoryTrackingKit(
                        container: container,
                        contexts: [container.newBackgroundContext()],
                        currentAuthor: "App\(i)",
                        allAuthors: ["App1", "App2", "App3"],
                        userDefaults: userDefaults,
                        uniqueString: uniqueString,
                        logLevel: 0,
                        autoStart: false
                    )

                    // 执行一些操作（使用 Actor 内部的测试方法）
                    do {
                        _ = try await kit.transactionProcessor.testFetchTransactionsExcludesAuthor(
                            from: ["App1"],
                            after: nil,
                            excludeAuthor: nil
                        )
                    } catch {
                        Issue.record("Failed in multi-instance test: \(error)")
                    }
                }
            }
        }

        #expect(true) // 主要验证不会崩溃
    }

    @Test("Cleaner 并发执行")
    func concurrentCleaners() async throws {
        let container = TestModelBuilder.createContainer(author: "App1")
        let context = container.viewContext

        // 创建数据
        TestModelBuilder.createPerson(name: "Alice", age: 30, in: context)
        try context.save()

        // 创建多个 cleaner 并发执行
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<3 {
                group.addTask {
                    let userDefaults = UserDefaults.standard
                    let uniqueString = "TestKit.ConcurrentCleaners.\(i).\(UUID().uuidString)."
                    userDefaults.set(Date(), forKey: uniqueString + "App1")

                    let cleaner = ManualCleanerActor(
                        container: container,
                        authors: ["App1"],
                        userDefaults: userDefaults,
                        uniqueString: uniqueString,
                        logger: DefaultLogger(),
                        logLevel: 0
                    )

                    await cleaner.clean()
                }
            }
        }

        // 验证数据仍然存在
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Person")
        let results = try context.fetch(fetchRequest)
        #expect(results.count == 1)
    }
}
