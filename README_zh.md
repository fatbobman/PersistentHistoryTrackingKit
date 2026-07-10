# PersistentHistoryTrackingKit

一个用于处理 Core Data 持久化历史的 Swift Package，让 App 与扩展可以一致地观察、合并并清理事务。

![Swift](https://img.shields.io/badge/Swift-6.2+-orange?style=flat)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2013+%20%7C%20macOS%2010.15+%20%7C%20macCatalyst%2013+%20%7C%20tvOS%2013+%20%7C%20watchOS%206+%20%7C%20visionOS%201+-blue?style=flat)
![License](https://img.shields.io/badge/License-MIT-green?style=flat)
[![DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/fatbobman/PersistentHistoryTrackingKit)

[English](README.md) | 中文

## Motivation

Core Data 持久化历史会记录 App、扩展、后台上下文以及可选 CloudKit 同步产生的变更。要把这些记录转化为可靠的合并与清理流程，需要协调 author、context 与生命周期事件。

PersistentHistoryTrackingKit 提供了这一协调能力：以 actor 为基础处理事务，并允许你按应用需求加入观察或合并逻辑。关于底层 Core Data 机制，请阅读[在 CoreData 中使用持久化历史跟踪](https://fatbobman.com/zh/posts/persistenthistorytracking/)。

## Features

- 处理来自已配置 author 的持久化历史事务，并将其合并至指定 context。
- 提供 Observer Hook 用于观察实体操作，也提供 Merge Hook 用于定制合并管线。
- 支持自动、手动或禁用历史清理，并可选择纳入 CloudKit mirroring author。
- 全面采用 Swift 并发模型，并提供明确的 start/stop 生命周期控制。

## Quick Start

使用 Swift Package Manager 添加 PersistentHistoryTrackingKit：

```swift
dependencies: [
    .package(url: "https://github.com/fatbobman/PersistentHistoryTrackingKit.git", from: "2.1.0")
]
```

启用持久化历史，并以共享同一 store 的 author 创建 kit：

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

- 想了解 Observer Hook、Merge Hook 及其执行约束？请阅读 [Hook 机制指南](Docs/HookMechanismCN.md)。
- 想将既有 V1 集成迁移到 V2？请阅读[迁移指南](Docs/MigrationGuideCN.md)。
- 想查询初始化参数、Hook 方法、清理选项与公开类型？请阅读英文版 [API Reference](Docs/APIReference.md)。
- 想了解本库依赖的 Core Data 基础机制？请阅读[在 CoreData 中使用持久化历史跟踪](https://fatbobman.com/zh/posts/persistenthistorytracking/)。

## Contributing & Testing

欢迎通过 Pull Request 参与贡献。使用 `./test.sh` 运行完整测试套件；该脚本会启用 Core Data 并发断言和并行执行。

## License

PersistentHistoryTrackingKit is available under the MIT license. See the [LICENSE](LICENSE) file for more info.

## Author

**Fatbobman (肘子)** — Blog: [fatbobman.com](https://fatbobman.com) · X: [@fatbobman](https://x.com/fatbobman)

## Support

If this project helps you, please consider supporting my work:

- 📮 Subscribe to [Fatbobman's Swift Weekly](https://weekly.fatbobman.com) — fresh Swift and Apple-ecosystem insights every week
- ☕️ [Buy Me a Coffee](https://buymeacoffee.com/fatbobman)

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=fatbobman/PersistentHistoryTrackingKit&type=Date)](https://www.star-history.com/#fatbobman/PersistentHistoryTrackingKit&Date)
