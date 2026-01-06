//
//  ConcurrencyTests.swift
//  PersistentHistoryTrackingKitTests
//
//  Created by Claude on 2025-01-06
//

import CoreData
import Testing
@testable import PersistentHistoryTrackingKit

@Suite("Concurrency Safety Tests", .serialized)
struct ConcurrencyTests {

    @Test("Multithreaded concurrent writes")
    func concurrentWrites() async throws {
        let container = TestModelBuilder.createContainer(author: "App1")

        // Spawn multiple contexts and write concurrently.
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

        // Ensure every record was persisted.
        let context = container.viewContext
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Person")
        let results = try context.fetch(fetchRequest)
        #expect(results.count == 5)
    }

    @Test("Multiple actors accessing concurrently")
    func multipleActorsConcurrentAccess() async throws {
        let container = TestModelBuilder.createContainer(author: "App1")
        let context = container.viewContext

        // Seed initial data.
        for i in 0..<10 {
            TestModelBuilder.createPerson(name: "Person\(i)", age: Int32(20 + i), in: context)
        }
        try context.save()

        // Spin up several processors that access concurrently.
        let hookRegistry = HookRegistryActor()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<3 {
                group.addTask {
                    let timestampManager = TransactionTimestampManager(
                        userDefaults: UserDefaults.standard,
                        maximumDuration: 604800
                    )
                    let processor = TransactionProcessorActor(
                        container: container,
                        hookRegistry: hookRegistry,
                        cleanStrategy: .none,
                        timestampManager: timestampManager
                    )

                    do {
                        // Use internal Actor test methods
                        let result = try await processor.testFetchTransactionsExcludesAuthor(
                            from: ["App1"],
                            after: nil as Date?,
                            excludeAuthor: nil as String?
                        )
                        // Ensure at least one transaction is returned.
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

        // Test passes if no crash or Issue.record was triggered
    }

    @Test("Clean and fetch concurrently")
    func cleanAndFetchConcurrent() async throws {
        let container = TestModelBuilder.createContainer(author: "App1")
        let context = container.viewContext

        // Seed initial data.
        TestModelBuilder.createPerson(name: "Alice", age: 30, in: context)
        try context.save()

        let hookRegistry = HookRegistryActor()
        let timestampManager = TransactionTimestampManager(
            userDefaults: UserDefaults.standard,
            maximumDuration: 604800
        )
        let processor = TransactionProcessorActor(
            container: container,
            hookRegistry: hookRegistry,
            cleanStrategy: .none,
            timestampManager: timestampManager
        )

        // Run fetch and clean concurrently.
        await withTaskGroup(of: Void.self) { group in
            // Fetch task.
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

            // Clean task.
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

        // Test passes if no crash or Issue.record was triggered
    }

    @Test("Concurrent hook triggering")
    func concurrentHookTriggering() async throws {
        let hookRegistry = HookRegistryActor()

        actor Counter {
            var count = 0
            func increment() { count += 1 }
            func get() -> Int { count }
        }

        let counter = Counter()

        // Register the hook.
        let callback: HookCallback = { _ in
            await counter.increment()
        }
        await hookRegistry.registerObserver(entityName: "Person", operation: .insert, callback: callback)

        // Fire hooks concurrently.
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
                    await hookRegistry.triggerObserver(context: context)
                }
            }
        }

        // Ensure every hook ran.
        let finalCount = await counter.get()
        #expect(finalCount == 100)
    }

    @Test("Multiple kit instances running concurrently")
    func multipleKitInstancesConcurrent() async throws {
        let container = TestModelBuilder.createContainer(author: "App1")

        // Create several kit instances.
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

                    // Execute some operations (using internal actor test helpers).
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

        // Test passes if no crash or Issue.record was triggered
    }

    @Test("Cleaners executing concurrently")
    func concurrentCleaners() async throws {
        let container = TestModelBuilder.createContainer(author: "App1")
        let context = container.viewContext

        // Seed initial data.
        TestModelBuilder.createPerson(name: "Alice", age: 30, in: context)
        try context.save()

        // Launch several cleaners concurrently.
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

        // Ensure the managed data remains.
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Person")
        let results = try context.fetch(fetchRequest)
        #expect(results.count == 1)
    }
}
