# Persistent History Tracking Kit 2

**适配 Swift 6** • **Actor 架构** • **并发安全** • **类型安全**

面向生产环境的 Core Data 持久化历史跟踪解决方案，完整支持 Swift 6 并发。

![Platform](https://img.shields.io/badge/Platform-iOS%2017%2B%20|%20macOS%2014%2B%20|%20tvOS%2017%2B%20|%20watchOS%2010%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.0-orange)
![License](https://img.shields.io/badge/License-MIT-green)[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/fatbobman/ObservableDefaults)

[English Version](README.md)

---

## V2 有哪些变化 🎉

V2 是一次基于现代 Swift 并发的完全重写：

- ✅ **全面支持 Swift 6** —— 以并发安全为目标设计
- ✅ **Actor 架构** —— `HookRegistryActor` 与 `TransactionProcessorActor` 确保线程安全
- ✅ **零内存泄漏** —— 没有保留环，生命周期清晰
- ✅ **数据竞争防护** —— 使用 Swift Testing 进行并发测试
- ✅ **Hook 系统** —— 支持 Observer Hook 与 Merge Hook
- ✅ **现代 API** —— 全面 async/await，Hook 使用 UUID 管理

**迁移提示**：V2 需要 iOS 17+/macOS 14+/Swift 6，迁移步骤与行为变化详见
[迁移指南](Docs/MigrationGuideCN.md)。

---

## 什么是 Persistent History Tracking？

> Use persistent history tracking to determine what changes have occurred in the store since the enabling of persistent history tracking. — Apple Documentation

启用 Persistent History Tracking 后，Core Data 会为以下来源的所有更改生成事务：

- 主应用
- 各类扩展（Widget、Share Extension 等）
- 自定义后台上下文
- CloudKit 同步（如启用）

**PersistentHistoryTrackingKit** 会自动：

1. 📥 获取其他 author 的新事务
2. 🔄 合并到指定 NSManagedObjectContext
3. 🧹 清理过期事务
4. 🎣 触发 Hook 供监控或自定义合并

**想了解原理？**

- 📖 [在 CoreData 中使用持久化历史跟踪](https://fatbobman.com/zh/posts/persistenthistorytracking/)

---

## 版本选择

### V2（当前分支）

- **最低要求**：iOS 17+ / macOS 14+ / Swift 6.0+
- **特点**：Actor 架构、Hook 系统、全面并发安全
- **适用场景**：面向现代系统的新项目

### V1（稳定分支）

- **最低要求**：iOS 13+ / macOS 10.15+ / Swift 5.5+
- **特点**：成熟稳定，支持旧平台
- **适用场景**：需要兼顾旧系统、暂未迁移 Swift 6

**安装 V1**

```swift
dependencies: [
    .package(url: "https://github.com/fatbobman/PersistentHistoryTrackingKit.git", from: "1.0.0")
]
```

或直接使用 `version-1` 分支：[查看文档](https://github.com/fatbobman/PersistentHistoryTrackingKit/tree/version-1)

如果你准备把已有的 V1 项目迁移到 V2，请先阅读[迁移指南](Docs/MigrationGuideCN.md)。

---

## 快速开始

### 安装

```swift
dependencies: [
    .package(url: "https://github.com/fatbobman/PersistentHistoryTrackingKit.git", from: "2.0.0")
]
```

### 基本配置

```swift
import CoreData
import PersistentHistoryTrackingKit

// 1. 打开 Persistent History Tracking
let container = NSPersistentContainer(name: "MyApp")
let description = container.persistentStoreDescriptions.first!
description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
container.loadPersistentStores { _, error in
    if let error { fatalError("Failed to load store: \(error)") }
}

// 2. 设置本端 author
container.viewContext.transactionAuthor = "MainApp"

// 3. 初始化 Kit
let kit = PersistentHistoryTrackingKit(
    container: container,
    contexts: [container.viewContext],
    currentAuthor: "MainApp",
    allAuthors: ["MainApp", "WidgetExtension", "ShareExtension"],
    userDefaults: .standard,
    cleanStrategy: .byDuration(seconds: 60 * 60 * 24 * 7),
    logLevel: 1
)
```

完成后 Kit 会自动监听远程通知、合并外部事务并清理历史。

---

## 核心概念

### Authors

为 App 与扩展设置唯一 author：

```swift
container.viewContext.transactionAuthor = "MainApp"
widgetContext.transactionAuthor = "WidgetExtension"
batchContext.transactionAuthor = "BatchProcessor"
```

然后在 Kit 中列出所有 author：

```swift
allAuthors: ["MainApp", "WidgetExtension", "BatchProcessor"]
```

### 清理策略

**重要提示**: 交易清理是可选的且开销很低。旧交易不会显著影响性能,无需激进清理 - 选择适合你应用的宽松间隔即可。

```swift
// 选项 1: 基于时间的清理(推荐)
// 每隔指定时间最多清理一次
cleanStrategy: .byDuration(seconds: 60 * 60 * 24 * 7) // 7 天

// 选项 2: 基于通知次数的清理
// 每隔 N 次通知清理一次(较少使用)
cleanStrategy: .byNotification(times: 10)

// 选项 3: 不自动清理(手动控制)
cleanStrategy: .none
```

**推荐策略**:

- **大多数应用**: 使用 `.byDuration(seconds: 60 * 60 * 24 * 7)` (7 天) - 提供良好平衡
- **CloudKit 用户**: **必须**使用 `.byDuration(seconds: 60 * 60 * 24 * 7)` 或更长间隔,避免 `NSPersistentHistoryTokenExpiredError`
- **频繁交易**: 考虑 `.byDuration(seconds: 60 * 60 * 24 * 3)` (3 天)
- **手动控制**: 使用 `.none`,在特定事件时清理(App 进入后台等)

自动清理采用保守策略: 只有所有非 batch author 都已在共享 `UserDefaults` 中记录各自的
merge 时间戳后,Kit 才会执行清理。只要有任何一个必要 author 尚未完成 merge,自动清理就会跳过。

**⚠️ CloudKit 用户特别注意**:

CloudKit 内部依赖持久化历史记录。如果历史清理过于激进,CloudKit 可能丢失其追踪标记,导致 `NSPersistentHistoryTokenExpiredError`(错误代码 134301),这可能会造成本地数据库清除和强制从 iCloud 重新同步。

**使用 CloudKit 时务必使用足够长时间的基于时间的清理**(7 天以上):

```swift
let kit = PersistentHistoryTrackingKit(
    container: container,
    currentAuthor: "MainApp",
    allAuthors: ["MainApp", "WidgetExtension"],
    cleanStrategy: .byDuration(seconds: 60 * 60 * 24 * 7),  // CloudKit 至少 7 天
    userDefaults: userDefaults
)
```

**注意**: 默认情况下,Kit **不会**清理由 `NSPersistentCloudKitContainer`(CloudKit 镜像)生成的交易,避免干扰 CloudKit 的内部同步。

### 手动清理

如需最大灵活性,你可以完全控制清理时机:

```swift
let kit = PersistentHistoryTrackingKit(
    // ... 其他参数
    cleanStrategy: .none,  // 禁用自动清理
    autoStart: false
)

// 创建手动清理器
let cleaner = kit.cleanerBuilder()

// 在你选择的时间进行清理
// 例如:App 进入后台、使用量低时等
Task {
    await cleaner.clean()
}

// 准备好后启动 Kit
kit.start()
```

---

## Hook 系统 🎣

### Observer Hook（只读）

```swift
let hookId = await kit.registerObserver(
    entityName: "Person",
    operation: .insert
) { contexts in
    for context in contexts {
        print("新建 Person: \(context.objectIDURL)")
        await Analytics.track(event: "person_created", properties: [
            "timestamp": context.timestamp,
            "author": context.author
        ])
    }
}

await kit.removeObserver(id: hookId)
await kit.removeObserver(entityName: "Person", operation: .insert)

> ℹ️ 同一事务中若多次对同一实体执行同一操作，回调只触发一次，
> 但 `contexts` 数组会包含该事务中所有对应的 `HookContext`，可一次性处理。
```

适合日志、统计、推送、缓存失效等场景。

### Merge Hook（自定义合并）

```swift
await kit.registerMergeHook { input in
    for transaction in input.transactions {
        for context in input.contexts {
            await context.perform {
                // 自定义合并逻辑
            }
        }
    }
    return .goOn // 或 .finish 跳过默认合并
}
```

**实战示例：去重**

```swift
await kit.registerMergeHook { input in
    for context in input.contexts {
        await context.perform {
            for transaction in input.transactions {
                guard let changes = transaction.changes else { continue }
                for change in changes where change.changeType == .insert {
                    guard let object = try? context.existingObject(with: change.changedObjectID),
                          let uniqueID = object.value(forKey: "uniqueID") as? String else { continue }
                    // 根据 uniqueID 查找重复项并删除
                }
            }
            try? context.save()
        }
    }
    return .goOn
}
```

完整 Hook 指南：[`Docs/HookMechanismCN.md`](Docs/HookMechanismCN.md)

---

## API 参考

### 初始化参数

| 参数 | 类型 | 说明 | 默认值 |
| --- | --- | --- | --- |
| `container` | `NSPersistentContainer` | Core Data 容器 | 必填 |
| `contexts` | `[NSManagedObjectContext]?` | 需要合并的上下文 | `viewContext` |
| `currentAuthor` | `String` | 当前 author | 必填 |
| `allAuthors` | `[String]` | 参与合并的 author | 必填 |
| `includingCloudKitMirroring` | `Bool` | 是否包含 CloudKit author | `false` |
| `batchAuthors` | `[String]` | 只写入不合并的 author | `[]` |
| `userDefaults` | `UserDefaults` | 存储时间戳 | 必填 |
| `cleanStrategy` | `TransactionCleanStrategy` | 清理策略 | `.none` |
| `maximumDuration` | `TimeInterval` | 为未来清理就绪策略预留 | 7 天 |
| `uniqueString` | `String` | UserDefaults key 前缀 | 自动生成 |
| `logger` | `PersistentHistoryTrackingKitLoggerProtocol?` | 自定义日志 | `DefaultLogger` |
| `logLevel` | `Int` | 日志级别 (0-2) | `1` |
| `autoStart` | `Bool` | 是否自动启动 | `true` |

### Hook API

```swift
// Observer Hook
func registerObserver(...) async -> UUID
func removeObserver(id:) async -> Bool
func removeObserver(entityName:operation:) async
func removeAllObservers() async

// Merge Hook
func registerMergeHook(before:callback:) async -> UUID
func removeMergeHook(id:) async -> Bool
func removeAllMergeHooks() async
```

### 运行控制

```swift
func start()
func stop()
func cleanerBuilder() -> ManualCleanerActor
```

---

## 高级用法

### App Group

```swift
let defaults = UserDefaults(suiteName: "group.com.yourapp")!
let kit = PersistentHistoryTrackingKit(
    container: container,
    currentAuthor: "MainApp",
    allAuthors: ["MainApp", "WidgetExtension"],
    userDefaults: defaults,
    cleanStrategy: .byDuration(seconds: 60 * 60 * 24 * 7)
)
```

### 自定义 Logger

```swift
struct MyLogger: PersistentHistoryTrackingKitLoggerProtocol {
    func log(type: PersistentHistoryTrackingKitLogType, message: String) {
        Logger.log(type, message)
    }
}
```

### 多个 Hook 的执行顺序

```swift
let hook1 = await kit.registerObserver(entityName: "Person", operation: .insert) { _ in print("Hook 1") }
let hook2 = await kit.registerObserver(entityName: "Person", operation: .insert) { _ in print("Hook 2") }
await kit.removeObserver(id: hook2) // 仅移除第二个

let hookA = await kit.registerMergeHook { _ in print("Hook A"); return .goOn }
let hookB = await kit.registerMergeHook(before: hookA) { _ in print("Hook B"); return .goOn }
// 执行顺序：Hook B → Hook A
```

---

## 系统需求

- iOS 17.0+
- macOS 14.0+
- tvOS 17.0+
- watchOS 10.0+
- Swift 6.0+
- Xcode 16.0+

---

## 文档

- [Hook 机制指南](Docs/HookMechanism.md)
- [迁移指南](Docs/MigrationGuideCN.md)
- [持久化历史跟踪原理](https://fatbobman.com/zh/posts/persistenthistorytracking/)

---

## 测试

> 测试现已验证可并行执行。测试基础设施会在内部串行化 `NSPersistentContainer` 的创建，以规避 Core Data 在并发加载存储时的崩溃，同时保留 suite 级并行执行。

```bash
./test.sh   # 推荐脚本，自动启用并行测试
```

如需手动运行，建议使用：

```bash
swift test --parallel
swift test --filter HookRegistryActorTests
```

---

## 贡献

欢迎 PR！

```bash
git clone https://github.com/fatbobman/PersistentHistoryTrackingKit.git
cd PersistentHistoryTrackingKit
swift build
./test.sh
```

---

## 协议

MIT，详见 [LICENSE](LICENSE)。

---

## 作者

**Fatbobman (肘子)**

- Blog: [fatbobman.com](https://fatbobman.com)
- Newsletter: [Fatbobman's Swift Weekly](https://weekly.fatbobman.com)
- Twitter: [@fatbobman](https://twitter.com/fatbobman)

---

## 致谢

感谢 Swift 与 Core Data 社区对 V2 的反馈与贡献，特别感谢修复 undo manager、去重策略及 Swift 6 迁移的贡献者。

---

## 赞助

如果你觉得这个库对你有帮助，欢迎支持我的工作：

<a href="https://buymeacoffee.com/fatbobman" target="_blank">
<img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" >
</a>

**[☕ 请我喝杯咖啡](https://buymeacoffee.com/fatbobman)**

你的支持将帮助我继续维护和改进开源 Swift 库。谢谢！🙏
