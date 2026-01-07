# Persistent History Tracking Kit

**Swift 6 ready** • **Actor-based** • **Fully concurrent** • **Type-safe**

A modern, production-ready library for handling Core Data's Persistent History Tracking with full Swift 6 concurrency support.

![Platform](https://img.shields.io/badge/Platform-iOS%2017%2B%20|%20macOS%2014%2B%20|%20tvOS%2017%2B%20|%20watchOS%2010%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.0-orange)
![License](https://img.shields.io/badge/License-MIT-green)

[English](https://github.com/fatbobman/PersistentHistoryTrackingKit/blob/main/README.md) | [中文版说明](https://github.com/fatbobman/PersistentHistoryTrackingKit/blob/main/READMECN.md)

---

## What's New in V2 🎉

Version 2 is a **complete rewrite** with modern Swift concurrency:

- ✅ **Full Swift 6 Compliance** - Concurrency-safe design tuned for Swift 6
- ✅ **Actor-Based Architecture** - Thread-safe by design with `HookRegistryActor` and `TransactionProcessorActor`
- ✅ **Zero Memory Leaks** - No retain cycles, properly managed lifecycle
- ✅ **Data Race Free** - Comprehensive concurrency testing with Swift Testing
- ✅ **Hook System** - Powerful Observer and Merge Hooks for custom behaviors
- ✅ **Modern API** - Async/await throughout, UUID-based hook management

**Migration from V1:** V2 requires iOS 17+, macOS 14+, and Swift 6. See [Migration Guide](#migration-from-v1) for details.

---

## What is Persistent History Tracking?

> Use persistent history tracking to determine what changes have occurred in the store since the enabling of persistent history tracking. — Apple Documentation

When you enable Persistent History Tracking, Core Data creates **transactions** for all changes across:
- Your main app
- App extensions (widgets, share extensions, etc.)
- Background contexts
- CloudKit sync (if enabled)

**PersistentHistoryTrackingKit** automates the process of:
1. 📥 Fetching new transactions from other contexts
2. 🔄 Merging them into your app's context
3. 🧹 Cleaning up old transactions
4. 🎣 Triggering custom hooks for monitoring or custom merge logic

**Want to learn more?**

- 📖 **[Using Persistent History Tracking in CoreData](https://fatbobman.com/en/posts/persistenthistorytracking/)** - Comprehensive guide covering the fundamentals, concepts, and implementation patterns

---

## Version Availability

### V2 (Current Branch)

- **Minimum Requirements**: iOS 17+, macOS 14+, Swift 6.0+
- **Features**: Actor-based architecture, Hook system, full Swift 6 concurrency
- **Recommended for**: New projects targeting modern platforms

### V1 (Stable)

- **Minimum Requirements**: iOS 13+, macOS 10.15+, Swift 5.5+
- **Features**: Proven stability, lower system requirements
- **Recommended for**: Projects that need to support older platforms

**Use V1 if:**

- You need to support iOS 13-16 or macOS 10.15-13
- You're not ready to migrate to Swift 6
- You prefer the battle-tested V1 API

📦 **Install V1**:

```swift
dependencies: [
    .package(url: "https://github.com/fatbobman/PersistentHistoryTrackingKit.git", from: "1.0.0")
]
```

Or use the `version-1` branch: [V1 Documentation](https://github.com/fatbobman/PersistentHistoryTrackingKit/tree/version-1)

---

## Quick Start

### Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/fatbobman/PersistentHistoryTrackingKit.git", from: "2.0.0")
]
```

### Basic Setup

```swift
import CoreData
import PersistentHistoryTrackingKit

// 1. Enable persistent history tracking in your Core Data stack
let container = NSPersistentContainer(name: "MyApp")
let description = container.persistentStoreDescriptions.first!

description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

container.loadPersistentStores { _, error in
    if let error = error {
        fatalError("Failed to load store: \(error)")
    }
}

// 2. Set transaction authors
container.viewContext.transactionAuthor = "MainApp"

// 3. Initialize PersistentHistoryTrackingKit
let kit = PersistentHistoryTrackingKit(
    container: container,
    contexts: [container.viewContext],
    currentAuthor: "MainApp",
    allAuthors: ["MainApp", "WidgetExtension", "ShareExtension"],
    userDefaults: .standard,
    cleanStrategy: .byDuration(seconds: 60 * 60 * 24 * 7), // 7 days
    logLevel: 1
)

// Kit starts automatically by default
```

That's it! The kit will now automatically:
- Detect remote changes
- Merge transactions from other authors
- Clean up old history
- Keep your contexts in sync

---

## Core Concepts

### Authors

Each part of your app should have a unique **author** name:

```swift
// Main app
container.viewContext.transactionAuthor = "MainApp"

// Widget extension
widgetContext.transactionAuthor = "WidgetExtension"

// Background batch operations
batchContext.transactionAuthor = "BatchProcessor"
```

Then configure the kit with all authors:

```swift
allAuthors: ["MainApp", "WidgetExtension", "BatchProcessor"]
```

### Cleanup Strategies

**Important**: Transaction cleanup is optional and low-overhead. Old transactions don't impact performance significantly. There's no need for aggressive cleanup - choose a relaxed interval that works for your app.

```swift
// Option 1: Time-based cleanup (recommended)
// Clean up at most once per time interval
cleanStrategy: .byDuration(seconds: 60 * 60 * 24 * 7) // 7 days

// Option 2: Notification-based cleanup
// Clean up after N notifications (less common)
cleanStrategy: .byNotification(times: 10)

// Option 3: No automatic cleanup (manual control)
cleanStrategy: .none
```

**Recommendations**:

- **Most apps**: Use `.byDuration(seconds: 60 * 60 * 24 * 7)` (7 days) - provides a good balance
- **CloudKit users**: **Must** use `.byDuration(seconds: 60 * 60 * 24 * 7)` or longer to avoid `NSPersistentHistoryTokenExpiredError`
- **Frequent transactions**: Consider `.byDuration(seconds: 60 * 60 * 24 * 3)` (3 days)
- **Manual control**: Use `.none` and clean on specific events (app background, etc.)

**⚠️ Important for CloudKit Users**:

CloudKit relies on persistent history internally. If history is cleaned up too aggressively, CloudKit may lose its tracking tokens, causing `NSPersistentHistoryTokenExpiredError` (error code 134301), which can lead to local database purges and forced re-sync from iCloud.

**Always use time-based cleanup with sufficient duration** (7+ days) when using CloudKit:

```swift
let kit = PersistentHistoryTrackingKit(
    container: container,
    currentAuthor: "MainApp",
    allAuthors: ["MainApp", "WidgetExtension"],
    cleanStrategy: .byDuration(seconds: 60 * 60 * 24 * 7),  // 7 days minimum for CloudKit
    userDefaults: userDefaults
)
```

**Note**: By default, the kit does **not** clean up transactions generated by `NSPersistentCloudKitContainer` (CloudKit mirroring), avoiding interference with CloudKit's internal synchronization.

### Manual Cleanup

For maximum flexibility, you can control when cleanup happens:

```swift
let kit = PersistentHistoryTrackingKit(
    // ... other parameters
    cleanStrategy: .none,  // Disable automatic cleanup
    autoStart: false
)

// Build a manual cleaner
let cleaner = kit.cleanerBuilder()

// Clean up at your preferred timing
// For example: when app enters background, during low usage, etc.
Task {
    await cleaner.clean()
}

// Start the kit when ready
kit.start()
```

---

## Hook System 🎣

V2 introduces a powerful **Hook System** for monitoring changes and customizing merge behavior.

### Observer Hooks (Read-Only Monitoring)

Monitor specific entity operations without modifying data:

```swift
// Monitor Person insertions
let hookId = await kit.registerObserver(
    entityName: "Person",
    operation: .insert
) { context in
    print("New person created: \(context.objectIDURL)")

    // Send analytics
    await Analytics.track(event: "person_created", properties: [
        "timestamp": context.timestamp,
        "author": context.author
    ])
}

// Remove specific hook later
await kit.removeObserver(id: hookId)

// Or remove all hooks for an entity+operation
await kit.removeObserver(entityName: "Person", operation: .insert)
```

**Use cases:** Logging, analytics, notifications, cache invalidation

### Merge Hooks (Custom Merge Logic)

Implement custom merge behavior with full access to Core Data:

```swift
// Custom conflict resolution
await kit.registerMergeHook { input in
    for transaction in input.transactions {
        for context in input.contexts {
            await context.perform {
                // Custom merge logic here
                // You have full access to NSManagedObjectContext
            }
        }
    }

    // Return .goOn to continue to next hook
    // Return .finish to skip remaining hooks and default merge
    return .goOn
}
```

**Use cases:** Conflict resolution, deduplication, validation, custom merge strategies

### Real-World Examples

**Disable Undo Manager During Merge:**

```swift
await kit.registerMergeHook { input in
    for transaction in input.transactions {
        let notification = transaction.objectIDNotification()

        for context in input.contexts {
            await context.perform {
                let undoManager = context.undoManager
                context.undoManager = nil

                context.mergeChanges(fromContextDidSave: notification)

                context.undoManager = undoManager
            }
        }
    }
    return .finish
}
```

**Deduplication:**

```swift
await kit.registerMergeHook { input in
    for context in input.contexts {
        await context.perform {
            for transaction in input.transactions {
                guard let changes = transaction.changes else { continue }

                for change in changes where change.changeType == .insert {
                    guard let object = try? context.existingObject(with: change.changedObjectID),
                          let uniqueID = object.value(forKey: "uniqueID") as? String else {
                        continue
                    }

                    // Find duplicates and remove
                    // ... deduplication logic
                }
            }
            try? context.save()
        }
    }
    return .goOn
}
```

**📚 Complete Hook Documentation:** [Docs/HookMechanism.md](Docs/HookMechanism.md)

---

## API Reference

### Initialization Parameters

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `container` | `NSPersistentContainer` | Your Core Data container | Required |
| `contexts` | `[NSManagedObjectContext]?` | Contexts to merge into | `[container.viewContext]` |
| `currentAuthor` | `String` | Current app's author name | Required |
| `allAuthors` | `[String]` | All author names to track | Required |
| `includingCloudKitMirroring` | `Bool` | Include CloudKit transactions | `false` |
| `batchAuthors` | `[String]` | Authors that only write, never merge | `[]` |
| `userDefaults` | `UserDefaults` | Storage for timestamps | Required |
| `cleanStrategy` | `TransactionCleanStrategy` | Cleanup strategy | `.none` |
| `maximumDuration` | `TimeInterval` | Max transaction age | 7 days |
| `uniqueString` | `String` | UserDefaults key prefix | Auto-generated |
| `logger` | `PersistentHistoryTrackingKitLoggerProtocol?` | Custom logger | `DefaultLogger` |
| `logLevel` | `Int` | Log verbosity (0-2) | `1` |
| `autoStart` | `Bool` | Start automatically | `true` |

### Observer Hook Methods

```swift
// Register observer hook (returns UUID for removal)
func registerObserver(
    entityName: String,
    operation: HookOperation,
    callback: @escaping HookCallback
) async -> UUID

// Remove specific hook by UUID
func removeObserver(id: UUID) async -> Bool

// Remove all hooks for entity+operation
func removeObserver(entityName: String, operation: HookOperation) async

// Remove all observer hooks
func removeAllObservers() async
```

### Merge Hook Methods

```swift
// Register merge hook (returns UUID)
func registerMergeHook(
    before hookId: UUID? = nil,
    callback: @escaping MergeHookCallback
) async -> UUID

// Remove specific merge hook
func removeMergeHook(id: UUID) async -> Bool

// Remove all merge hooks
func removeAllMergeHooks() async
```

### Control Methods

```swift
// Start/stop the kit
func start()
func stop()

// Build a manual cleaner
func cleanerBuilder() -> ManualCleanerActor
```

---

## Advanced Usage

### App Groups

For sharing data across app and extensions:

```swift
let appGroupDefaults = UserDefaults(suiteName: "group.com.yourapp")!

let kit = PersistentHistoryTrackingKit(
    container: container,
    currentAuthor: "MainApp",
    allAuthors: ["MainApp", "WidgetExtension"],
    userDefaults: appGroupDefaults, // Use shared UserDefaults
    cleanStrategy: .byDuration(seconds: 60 * 60 * 24 * 7)
)
```

### Custom Logger

Integrate with your logging system:

```swift
struct MyLogger: PersistentHistoryTrackingKitLoggerProtocol {
    func log(type: PersistentHistoryTrackingKitLogType, message: String) {
        switch type {
        case .debug:
            Logger.debug(message)
        case .info:
            Logger.info(message)
        case .notice:
            Logger.notice(message)
        case .error:
            Logger.error(message)
        case .fault:
            Logger.fault(message)
        }
    }
}

let kit = PersistentHistoryTrackingKit(
    // ... other parameters
    logger: MyLogger(),
    logLevel: 2 // 0: off, 1: important, 2: detailed
)
```

### Multiple Hooks with Execution Order

Observer Hooks execute in **registration order**:

```swift
// These execute sequentially: Hook 1 → Hook 2 → Hook 3
let hook1 = await kit.registerObserver(entityName: "Person", operation: .insert) { _ in
    print("Hook 1")
}

let hook2 = await kit.registerObserver(entityName: "Person", operation: .insert) { _ in
    print("Hook 2")
}

let hook3 = await kit.registerObserver(entityName: "Person", operation: .insert) { _ in
    print("Hook 3")
}

// Remove only Hook 2
await kit.removeObserver(id: hook2)
// Now only Hook 1 and Hook 3 execute
```

Merge Hooks support **pipeline insertion**:

```swift
let hookA = await kit.registerMergeHook { _ in
    print("Hook A")
    return .goOn
}

// Insert before hookA
let hookB = await kit.registerMergeHook(before: hookA) { _ in
    print("Hook B")
    return .goOn
}

// Execution order: Hook B → Hook A
```

---

## Requirements

- iOS 17.0+ / macOS 14.0+ / tvOS 17.0+ / watchOS 10.0+
- Swift 6.0+
- Xcode 16.0+

---

## Documentation

- **[Hook Mechanism Guide](Docs/HookMechanism.md)** - Complete guide to Observer and Merge Hooks
- **[Core Data Persistent History Tracking](https://fatbobman.com/en/posts/persistenthistorytracking/)** - Blog post on the fundamentals

---

## Testing

**⚠️ Important: Tests Must Run Serially**

Due to Core Data's singleton nature and shared persistent stores, **tests must run serially**, not in parallel. Running tests in parallel will cause race conditions and failures.

### Recommended: Use the test script

```bash
# Run all tests serially (recommended)
./test.sh
```

The test script ensures:

- ✅ All tests run sequentially
- ✅ Proper cleanup between test suites
- ✅ Reliable results

### Alternative: Manual testing (caution required)

If you run tests manually, use filters with caution:

```bash
# ⚠️ Only use this for individual test suites
swift test --filter HookRegistryActorTests

# ❌ AVOID: Running all tests may cause failures due to Core Data conflicts
swift test  # May fail - use test.sh instead
```

Test suites include:

- Unit tests for all actors and components
- Integration tests with real Core Data stack
- Concurrency stress tests
- Memory leak detection
- Hook system tests (Observer and Merge Hooks)

---

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

### Development Setup

```bash
git clone https://github.com/fatbobman/PersistentHistoryTrackingKit.git
cd PersistentHistoryTrackingKit
swift build
./test.sh
```

---

## License

This library is released under the MIT license. See [LICENSE](LICENSE) for details.

---

## Author

**Fatbobman (肘子)**

- Blog: [fatbobman.com](https://fatbobman.com)
- Newsletter: [Fatbobman's Swift Weekly](https://weekly.fatbobman.com)
- Twitter: [@fatbobman](https://twitter.com/fatbobman)

---

## Acknowledgments

Thanks to the Swift and Core Data communities for their valuable feedback and contributions.

Special thanks to contributors who helped improve V2:
- Community members who submitted PRs for undo manager handling and deduplication strategies
- Early testers of the Swift 6 migration

---

## Sponsor

If you find this library helpful, consider supporting my work:

<a href="https://buymeacoffee.com/fatbobman" target="_blank">
<img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" >
</a>

**[☕ Buy Me a Coffee](https://buymeacoffee.com/fatbobman)**

Your support helps me continue maintaining and improving open-source Swift libraries. Thank you! 🙏
