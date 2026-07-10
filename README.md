# PersistentHistoryTrackingKit

A Swift package that processes Core Data persistent history so apps and extensions can observe, merge, and clean transactions consistently.

![Swift](https://img.shields.io/badge/Swift-6.2+-orange?style=flat)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2013+%20%7C%20macOS%2010.15+%20%7C%20macCatalyst%2013+%20%7C%20tvOS%2013+%20%7C%20watchOS%206+%20%7C%20visionOS%201+-blue?style=flat)
![License](https://img.shields.io/badge/License-MIT-green?style=flat)
[![DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/fatbobman/PersistentHistoryTrackingKit)

English | [中文](README_zh.md)

## Motivation

Core Data persistent history records changes made by an app, its extensions, background contexts, and optional CloudKit synchronization. Turning those records into a reliable merge and cleanup flow requires coordinating authors, contexts, and lifecycle events.

PersistentHistoryTrackingKit provides that coordination with an actor-based processing pipeline and hooks for app-specific observation or merge behavior. For the underlying Core Data model, read [Using Persistent History Tracking in Core Data](https://fatbobman.com/en/posts/persistenthistorytracking/).

## Features

- Processes persistent-history transactions from configured authors and merges them into chosen contexts.
- Provides Observer Hooks for monitoring entity operations and Merge Hooks for custom merge pipelines.
- Supports automatic, manual, or disabled history cleanup and optional CloudKit mirroring authors.
- Uses Swift concurrency throughout and exposes explicit start/stop lifecycle control.

## Quick Start

Add PersistentHistoryTrackingKit with Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/fatbobman/PersistentHistoryTrackingKit.git", from: "2.1.0")
]
```

Enable persistent history and create the kit with the authors that share the store:

```swift
import CoreData
import PersistentHistoryTrackingKit

let container = NSPersistentContainer(name: "Model")
let description = container.persistentStoreDescriptions.first!
description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
container.loadPersistentStores { _, error in
    if let error { fatalError("Failed to load store: \(error)") }
}

container.viewContext.transactionAuthor = "MainApp"
let kit = PersistentHistoryTrackingKit(
    container: container,
    currentAuthor: "MainApp",
    allAuthors: ["MainApp", "WidgetExtension"],
    userDefaults: .standard
)
```

## Documentation

- Want to understand Observer Hooks, Merge Hooks, and their execution constraints? Read the [Hook Mechanism Guide](Docs/HookMechanism.md).
- Want to move an existing V1 integration to V2? Read the [Migration Guide](Docs/MigrationGuide.md).
- Want to look up initializer parameters, hook methods, cleanup options, and public types? Read the [API Reference](Docs/APIReference.md).
- Want to learn the Core Data fundamentals behind this package? Read [Using Persistent History Tracking in Core Data](https://fatbobman.com/en/posts/persistenthistorytracking/).

## Contributing & Testing

Contributions are welcome through pull requests. Run the full suite with `./test.sh`; it enables Core Data concurrency assertions and parallel execution.

## License

PersistentHistoryTrackingKit is available under the MIT license. See the [LICENSE](LICENSE) file for more info.

## Author

**Fatbobman (肘子)** — Blog: [fatbobman.com](https://fatbobman.com) · X: [@fatbobman](https://x.com/fatbobman)

## Support

If this project helps you, please consider supporting my work:

- 📮 Subscribe to [Fatbobman's Swift Weekly](https://weekly.fatbobman.com) — fresh Swift and Apple-ecosystem insights every week
- ☕️ [Buy Me a Coffee](https://buymeacoffee.com/fatbobman)
