# Persistent History Tracking Kit

A Swift 6 compatible library that helps you easily handle Core Data's Persistent History Tracking with full concurrency safety and thread-safe operations.

![os](https://img.shields.io/badge/Platform%20Compatibility-iOS%20|%20macOS%20|%20tvOS%20|%20watchOS-blue) ![swift](https://img.shields.io/badge/Swift%20Compatibility-5.5%20|%206.0-green) ![concurrency](https://img.shields.io/badge/Concurrency-Safe-brightgreen) ![sendable](https://img.shields.io/badge/Sendable-Compliant-orange) [![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/fatbobman/PersistentHistoryTrackingKit)

[中文版说明](https://github.com/fatbobman/PersistentHistoryTrackingKit/blob/main/READMECN.md)

## ✨ Key Features

- 🚀 **Swift 6 Ready**: Full compatibility with Swift 6's strict concurrency checking
- 🔒 **Thread-Safe**: True `Sendable` compliance with proper synchronization mechanisms
- 🔄 **Automatic Synchronization**: Seamlessly syncs data across app targets and extensions
- 🧹 **Smart Cleanup**: Intelligent transaction cleanup with multiple strategies
- 📱 **Multi-Target Support**: Perfect for apps with extensions, widgets, and background tasks
- ⚡ **High Performance**: Optimized for minimal overhead and fast operations
- 🛡️ **Memory Safe**: No retain cycles or memory leaks
- 🧪 **Well Tested**: Comprehensive test suite with 31 passing tests

## What's This？

> Use persistent history tracking to determine what changes have occurred in the store since the enabling of persistent history tracking.  —— Apple Documentation

When Persistent History Tracking is enabled, your application will begin creating transactions for any changes that occur in Core Data Storage. Whether they come from application extensions, background contexts, or the main application.

Each target of your application can fetch the transactions that have occurred since a given date and merge them into the local storage. This way, you can keep up to date with changes made by other persistent storage coordinators and keep your storage up to date. After merging all transactions, you can update the merge date so that the next time you merge, you will only get the new transactions that have not yet been processed.

The **Persistent History Tracking Kit** will automate the above process for you.

## How does persistent history tracking work?

Upon receiving a remote notification of Persistent History Tracking from Core Data, Persistent History Tracking Kit will do the following:

- Query the current author's (current author) last merge transaction time
- Get new transactions created by other applications, application extensions, background contexts, etc. (all authors) in addition to this application since the date of the last merged transaction
- Merge the new transaction into the specified context (usually the current application's view context)
- Update the current application's merge transaction time
- Clean up transactions that have been merged by all applications

For more specific details on how this works, read [在 CoreData 中使用持久化历史跟踪](https://fatbobman.com/zh/posts/persistenthistorytracking/) or [Using Persistent History Tracking in CoreData](https://fatbobman.com/en/posts/persistenthistorytracking/).

## 🚀 Swift 6 Compatibility

This library is fully compatible with Swift 6's strict concurrency checking:

- ✅ **True Sendable Compliance**: Not just `@unchecked Sendable` - properly implemented thread safety
- ✅ **Actor Isolation**: Respects Swift's actor isolation rules
- ✅ **Data Race Free**: Comprehensive concurrency testing ensures no data races
- ✅ **Memory Safe**: No retain cycles or memory leaks
- ✅ **Async/Await Ready**: Modern Swift concurrency patterns

### Concurrency Testing

The library includes comprehensive concurrency tests that can be run with:

```bash
# Enable Core Data concurrency debugging
export NSDebugConcurrencyType=1
export NSCoreDataConcurrencyDebug=1

# Run tests with concurrency checks
swift test --package-path .
```

## Usage

### Basic Setup

```swift
import PersistentHistoryTrackingKit

class CoreDataStack {
    private var kit: PersistentHistoryTrackingKit?
    
    init() {
        container = NSPersistentContainer(name: "DataModel")
        
        // Configure persistent store for history tracking
        let description = container.persistentStoreDescriptions.first!
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Core Data failed to load: \(error.localizedDescription)")
            }
        }
        
        // Set transaction author
        container.viewContext.transactionAuthor = "MainApp"
        
        // Initialize the kit
        kit = PersistentHistoryTrackingKit(
            container: container,
            currentAuthor: "MainApp",
            allAuthors: ["MainApp", "ShareExtension", "WidgetExtension"],
            userDefaults: UserDefaults(suiteName: "group.com.example.app") ?? .standard,
            cleanStrategy: .byNotification(times: 1),
            logLevel: 1
        )
    }
    
    deinit {
        kit?.stop()
    }
}
```

### Advanced Configuration for App Groups

```swift
// For apps with multiple targets (main app + extensions)
class AppGroupCoreDataStack {
    private let kit: PersistentHistoryTrackingKit
    
    init() {
        // Use App Group container
        let container = NSPersistentContainer(name: "SharedDataModel")
        
        // Configure for shared access
        let storeURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.example.app")?
            .appendingPathComponent("SharedData.sqlite")
        
        let description = NSPersistentStoreDescription(url: storeURL!)
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, _ in }
        
        // Initialize with proper configuration
        kit = PersistentHistoryTrackingKit(
            container: container,
            currentAuthor: "MainApp",
            allAuthors: ["MainApp", "ShareExtension", "WidgetExtension", "BackgroundSync"],
            batchAuthors: ["BackgroundSync"], // For batch operations
            userDefaults: UserDefaults(suiteName: "group.com.example.app")!,
            cleanStrategy: .byNotification(times: 2),
            maximumDuration: 60 * 60 * 24 * 7, // 7 days
            logLevel: 2
        )
    }
}
```

### Swift Testing Framework

This library uses the modern Swift Testing framework. Here's how to test your integration:

```swift
import Testing
import PersistentHistoryTrackingKit

@Test("Multi-app synchronization works correctly")
func testMultiAppSync() async throws {
    // Your test implementation
    let kit1 = PersistentHistoryTrackingKit(/* config for app1 */)
    let kit2 = PersistentHistoryTrackingKit(/* config for app2 */)
    
    // Test data synchronization between apps
    // ...
    
    kit1.stop()
    kit2.stop()
}
```

## Parameters

### currentAuthor

The name of the author of the current application. The name is usually the same as the transaction name of the view context

```swift
container.viewContext.transactionAuthor = "app1"
```

### allAuthors

The author name of all members managed by the Persistent History Tracking Kit.

Persistent History Tracking Kit should only be used to manage transactions generated by developer-created applications, application extensions, and backend contexts; other system-generated transactions (e.g. Core Data with CloudKit) are handled by the system itself.

For example, if your application author name is: "appAuthor" and your application extension author name is: "extensionAuthor", then.

```swift
allAuthors: ["appAuthor", "extensionAuthor"],
```

For transactions generated in the backend context, the backend context should also have a separate author name if it is not set to auto-merge.

```swift
allAuthors: ["appAuthor", "extensionAuthor", "appBatchAuthor"],
```

### includingCloudKitMirroring

Whether or not to merge network data imported by Core Data with CloudKit, is only used in scenarios where the Core Data cloud sync state needs to be switched in real time. See [Switching Core Data Cloud Sync Status in Real-Time](https://fatbobman.com/en/posts/real-time-switching-of-cloud-syncs-status/) for details on usage

### batchAuthors

Some authors (such as background contexts for batch changes) only create transactions and do not merge and clean up transactions generated by other authors. You can speed up the cleanup of such transactions by setting them in batchAuthors.

```swift
batchAuthors: ["appBatchAuthor"],
```

Even if not set, these transactions will be automatically cleared after reaching maximumDuration.

### maximumDuration

Normally, transactions are only cleaned up after they have been merged by all authors. However, in some cases, individual authors may not run for a long time or may not be implemented yet, causing transactions to remain in SQLite. In the long run, this can cause a performance degradation of the database.

By setting maximumDuration, Persistent History Tracking Kit will force the removal of transactions that have reached the set duration. The default setting is 7 days.

```swift
maximumDuration: 60 * 60 * 24 * 7,
```

Performing cleanup on transactions does not harm the application's data.

### contexts

The context used for merging transactions, usually the application's view context. By default, it is automatically set to the container's view context.

```swift
contexts: [viewContext],
```

### userDefaults

If an App Group is used, use the UserDefaults available for the group.

```swift
let appGroupUserDefaults = UserDefaults(suiteName: "group.com.yourGroup")!

userDefaults: appGroupUserDefaults,
```

### cleanStrategy

Persistent History Tracking Kit currently supports three transaction cleanup strategies:

- none

  Merge only, no cleanup

- byDuration

  Set a minimum time interval between cleanups

- byNotification

  Set the minimum number of notifications between cleanups

```swift
// Each notification triggers cleanup
cleanStrategy: .byNotification(times: 1),
// At least 60 seconds between cleanups
cleanStrategy: .byDuration(seconds: 60),
// No automatic cleanup
cleanStrategy: .none,
```

### ⚠️ Important: Cleanup Strategy Recommendations

**Avoid frequent cleanup operations** to maintain optimal performance:

#### Recommended Strategies

1. **`.byDuration()` - Preferred for most applications**

   ```swift
   // Clean every few hours (recommended)
   cleanStrategy: .byDuration(seconds: 60 * 60 * 4) // 4 hours
   
   // Or even daily cleanup for low-activity apps
   cleanStrategy: .byDuration(seconds: 60 * 60 * 24) // 24 hours
   ```

2. **`.none` with manual cleanup - Best for full control**

   ```swift
   // Set up with no automatic cleanup
   cleanStrategy: .none
   
   // Perform manual cleanup at optimal times
   let cleaner = kit.cleanerBuilder()
   
   // Example: Clean when app enters background
   NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
       cleaner()
   }
   ```

3. **`.byNotification()` - Use with caution**

   ```swift
   // Avoid too frequent cleanup
   cleanStrategy: .byNotification(times: 50) // Clean every 50 notifications instead of 1
   ```

#### Why Avoid Frequent Cleanup?

- **Performance Impact**: Frequent cleanup operations can impact database performance
- **Unnecessary Overhead**: Most applications don't need immediate cleanup after every change
- **Battery Life**: Reduces unnecessary background processing
- **Resource Optimization**: Allows the system to batch operations more efficiently

#### Best Practices

- Use `.byDuration()` with intervals of **several hours to days**
- Consider your app's usage patterns (high vs. low activity)
- Monitor cleanup frequency in logs during development
- Use manual cleanup for apps with predictable usage patterns

When the cleanup policy is set to none, cleanup can be performed at the right time by generating separate cleanup instances.

```swift
let kit = PersistentHistoryTrackingKit(
    container: container,
    currentAuthor: "app1",
    allAuthors: "app1,app2,app3",
    userDefaults: userDefaults,
    cleanStrategy: .byNotification(times: 1),
    logLevel: 3,
    autoStart: false
)
let cleaner = kit.cleanerBuilder()

// Execute cleaner at the right time, for example when the application enters the background
clear()
```

### uniqueString

The string prefix for the timestamp in UserDefaults.

### logger

The Persistent History Tracking Kit provides default logging output. To export Persistent History Tracking Kit information through the logging system you are using, simply make your logging code conform to the PersistentHistoryTrackingKitLoggerProtocol.

```swift
public protocol PersistentHistoryTrackingKitLoggerProtocol {
    func log(type: PersistentHistoryTrackingKitLogType, message: String)
}

struct MyLogger: PersistentHistoryTrackingKitLoggerProtocol {
    func log(type: PersistentHistoryTrackingKitLogType, message: String) {
        print("[\(type.rawValue.uppercased())] : message")
    }
}

logger:MyLogger(),
```

### logLevel

The output of log messages can be controlled by setting logLevel:

- 0 Turn off log output
- 1 Important status only
- 2 Detail information

### autoStart

Whether to start the Persistent History Tracking Kit instance as soon as it is created.

During the execution of the application, the running state can be changed by start() or stop().

```swift
kit.start()
kit.stop()
```

## 🎯 Best Practices

### 1. Swift 6 Migration

When migrating to Swift 6, the library provides full compatibility:

- Enable strict concurrency checking in your project
- The library is truly `Sendable` compliant (not just `@unchecked`)
- No code changes needed in your existing usage

### 2. Memory Management

```swift
class DataManager {
    private var kit: PersistentHistoryTrackingKit?
    
    deinit {
        // Always stop the kit to prevent memory leaks
        kit?.stop()
    }
}
```

### 3. App Group Configuration

```swift
// Use consistent identifiers across all targets
let groupDefaults = UserDefaults(suiteName: "group.com.yourapp.shared")!
let kit = PersistentHistoryTrackingKit(
    container: container,
    currentAuthor: "MainApp", // Unique per target
    allAuthors: ["MainApp", "ShareExtension", "WidgetExtension"],
    userDefaults: groupDefaults, // Shared UserDefaults
    cleanStrategy: .byNotification(times: 1)
)
```

### 4. Testing with Concurrency

```bash
# Run the provided concurrency test script
./run_tests_with_concurrency_checks.sh

# Or manually with environment variables
export NSDebugConcurrencyType=1
export NSCoreDataConcurrencyDebug=1
swift test --package-path .
```

### 5. Transaction Cleanup Strategy

Choose the right cleanup strategy for optimal performance:

```swift
// ✅ Recommended: Cleanup every few hours
let kit = PersistentHistoryTrackingKit(
    container: container,
    currentAuthor: "MainApp",
    allAuthors: ["MainApp", "Extension"],
    userDefaults: userDefaults,
    cleanStrategy: .byDuration(seconds: 60 * 60 * 6), // 6 hours
    logLevel: 1
)

// ✅ Also good: Manual cleanup for full control
let kitWithManualCleanup = PersistentHistoryTrackingKit(
    // ... other configuration
    cleanStrategy: .none
)

// Clean up when appropriate (e.g., app backgrounding)
let cleaner = kitWithManualCleanup.cleanerBuilder()
// Call cleaner() when needed

// ⚠️ Avoid: Too frequent automatic cleanup
// cleanStrategy: .byNotification(times: 1) // This is too frequent!
```

### 6. Error Handling

```swift
// The kit handles most errors internally, but monitor logs
let kit = PersistentHistoryTrackingKit(
    // ... configuration
    logLevel: 2 // Enable detailed logging for debugging
)
```

## Requirements

### Minimum Platform Versions

- iOS 13.0+
- macOS 10.15+
- macCatalyst 13.0+
- tvOS 13.0+
- watchOS 6.0+

### Swift Versions

- Swift 5.5+ (for basic functionality)
- Swift 6.0+ (for full concurrency features)

### Xcode

- Xcode 14.0+ (for Swift 5.5 support)
- Xcode 16.0+ (for Swift 6.0 support)

## 📦 Installation

### Swift Package Manager

Add this package to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/fatbobman/PersistentHistoryTrackingKit.git", from: "1.0.0")
]
```

### Xcode Integration

1. In Xcode, select **File > Add Package Dependencies...**
2. Enter the repository URL: `https://github.com/fatbobman/PersistentHistoryTrackingKit.git`
3. Choose **Up to Next Major Version** and click **Add Package**

### Swift 6 Specific Setup

For Swift 6 projects, you can use the Swift 6 specific package manifest:

```swift
// Package@swift-6.swift is automatically used when building with Swift 6
```

## 🔄 Migration Guide

### From Pre-Swift 6 Versions

If you're upgrading from an earlier version:

1. **No API Changes Required**: The public API remains the same
2. **Enhanced Safety**: Your existing code now benefits from true `Sendable` compliance
3. **Better Performance**: Memory leaks and retain cycles have been eliminated
4. **Improved Testing**: Switch to Swift Testing framework for better async support

### Example Migration

```swift
// Before (still works)
let kit = PersistentHistoryTrackingKit(/* your config */)

// After (same API, enhanced safety)
let kit = PersistentHistoryTrackingKit(/* your config */)
// Now with true Sendable compliance and memory safety!
```

## 🧪 Testing

### Running Tests

```bash
# Basic test run
swift test

# With concurrency debugging
./run_tests_with_concurrency_checks.sh

# Specific test suites
swift test --filter "QuickIntegrationTests"
swift test --filter "ComprehensiveIntegrationTests"
```

### Test Coverage

The library includes comprehensive tests:

- ✅ 31 total tests covering all functionality
- ✅ Multi-app synchronization scenarios  
- ✅ Batch operation handling
- ✅ Concurrent stress testing
- ✅ Memory leak detection
- ✅ Swift 6 concurrency compliance

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

### Development

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Run tests with concurrency checks: `./run_tests_with_concurrency_checks.sh`
4. Commit your changes (`git commit -m 'Add some amazing feature'`)
5. Push to the branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request

### Testing Guidelines

- All new features must include tests
- Tests must pass with Swift 6 strict concurrency checking enabled
- Use the Swift Testing framework for new tests
- Ensure no memory leaks or retain cycles

## 📚 Related Resources

- [Core Data Persistent History Tracking Guide](https://fatbobman.com/en/posts/persistenthistorytracking/)
- [Swift 6 Concurrency Documentation](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)
- [Core Data Programming Guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreData/)

## 🙏 Acknowledgments

- Special thanks to the Swift community for the evolution towards safer concurrency
- Core Data team at Apple for providing the persistent history tracking foundation
- All contributors who helped improve this library

## Support the project

- [🎉 Subscribe to my Swift Weekly](https://weekly.fatbobman.com)
- [☕️ Buy Me A Coffee](https://buymeacoffee.com/fatbobman)

## License

This library is released under the MIT license. See [LICENSE](https://github.com/fatbobman/persistentHistoryTrackingKit/blob/main/LICENSE) for details.

---

**Made with ❤️ for the Swift community**
