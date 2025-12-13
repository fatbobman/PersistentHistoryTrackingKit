# Persistent History Tracking Kit

帮助您轻松处理 Core Data 的持久性历史跟踪。

![os](https://img.shields.io/badge/Platform%20Compatibility-iOS%20|%20macOS%20|%20tvOS%20|%20watchOs-red) ![swift](https://img.shields.io/badge/Swift%20Compatibility-5.5-red)

[English Version](https://github.com/fatbobman/PersistentHistoryTrackingKit/blob/main/README.md)

## 🚀 Swift 6 分支现已可用

> **🎯 新的 Swift 6 兼容版本现已可用**
>
> 我们创建了一个全面的 **Swift 6 适配版本**，具备完整的并发安全性、真正的 Sendable 合规性和内存泄漏修复。新版本可在 `swift6-adaptation` 分支中使用。
>
> **✨ 主要改进：**
>
> - 🔒 **真正的 Sendable 合规** - 不仅仅是 `@unchecked Sendable`
> - 🧵 **无数据竞争** - 全面的并发测试
> - 🛡️ **内存安全** - 零保留循环或内存泄漏
> - 🧪 **Swift Testing 框架** - 现代测试基础设施
> - 📚 **增强文档** - 全面的指南和示例
>
> **🔄 试用方法：**
>
> ```swift
> dependencies: [
>     .package(url: "https://github.com/fatbobman/PersistentHistoryTrackingKit.git", branch: "swift6-adaptation")
> ]
> ```
>
> **📝 欢迎反馈：**  
> 请测试 Swift 6 版本并[**创建 issue**](https://github.com/fatbobman/PersistentHistoryTrackingKit/issues) 提供您的反馈。一旦我们获得足够的实际使用验证，就会将其合并到 main 分支。
>
> **📖 完整文档：** [Swift 6 分支 README](https://github.com/fatbobman/PersistentHistoryTrackingKit/blob/swift6-adaptation/READMECN.md)

## What's This？

> Use persistent history tracking to determine what changes have occurred in the store since the enabling of persistent history tracking.  —— Apple Documentation

启用持久历史记录跟踪（Persistent History Tracking）后，您的应用程序将开始为 Core Data 存储中发生的任何更改创建事务。无论它们来自应用程序扩展、后台上下文还是主应用程序。

您的应用程序的每个目标都可以获取自给定日期以来发生的事务，并将其合并到本地存储。这样，您可以随时了解其他持久化存储协调器的更改，让您的存储保持最新状态。合并所有事务后，您可以更新合并日期，这样您在下次合并时将只会获取到尚未处理的新事务。

**Persistent History Tracking Kit** 将为您自动完成上述的过程。

## 持久性历史跟踪是如何进行的？

在接收到 Core Data 发送的持久历史记录跟踪远程通知后，Persistent History Tracking Kit 将进行如下工作：

- 查询当前应用的（current author）上次合并事务的时间
- 获取从上次合并事务日期后，除了本应用程序外，由其他应用程序、应用程序扩展、后台上下文等（all authors）新创建的事务
- 将新的事务合并到指定的上下文中（通常是当前应用程序的视图上下文）
- 更新当前应用程序的合并事务时间
- 清理已被所有应用合并后的事务

更具体的工作原理和细节，可以阅读 [在 CoreData 中使用持久化历史跟踪](https://fatbobman.com/zh/posts/persistenthistorytracking/) 或者 [Using Persistent History Tracking in CoreData](https://fatbobman.com/en/posts/persistenthistorytracking/)。

## 使用方法

```swift
// in Core Data Stack
import PersistentHistoryTrackingKit

init() {
    container = NSPersistentContainer(name: "PersistentTrackBlog")
    // Prepare your Container
    let desc = container.persistentStoreDescriptions.first!
    // Turn on persistent history tracking in persistentStoreDescriptions
    desc.setOption(true as NSNumber,
                   forKey: NSPersistentHistoryTrackingKey)
    desc.setOption(true as NSNumber,
                   forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
    container.loadPersistentStores(completionHandler: { _, _ in })

    container.viewContext.transactionAuthor = "app1"
    // after loadPersistentStores
    let kit = PersistentHistoryTrackingKit(
        container: container,
        currentAuthor: "app1",
        allAuthors: ["app1", "app2", "app3"],
        userDefaults: userDefaults,
        logLevel: 3,
    )
}
```

## 配置参数

### currentAuthor

当前应用的 author 名称。名称通常与视图上下文的事务名称一致

```swift
container.viewContext.transactionAuthor = "app1"
```

### allAuthors

由 Persistent History Tracking Kit 管理的所有成员的 author 名称。

Persistent History Tracking Kit 应只用来管理由开发者创建的应用程序、应用程序扩展、后台上下文产生的事务，其他由系统生成的事务（例如 Core Data with CloudKit），系统会自行处理。

例如，您的应用程序 author 名称为：“appAuthor”，应用程序扩展 author 名称为：“extensionAuthor”，则：

```swift
allAuthors: ["appAuthor", "extensionAuthor"],
```

对于后台上下文中生成的事务，如果没有设置成自动合并的话，后台上下文也应该设置单独的 author 名称：

```swift
allAuthors: ["appAuthor", "extensionAuthor", "appBatchAuthor"],
```

### includingCloudKitMirroring

是否合并由 Core Data with CloudKit 导入的网络数据，仅用于需要实时切换 Core Data 云同步状态的场景。具体用法请参阅 [实时切换 Core Data 的云同步状态](https://fatbobman.com/zh/posts/real-time-switching-of-cloud-syncs-status/)

### batchAuthors

某些 author（例如用于批量更改的后台上下文）只会创建事务，并不会对其他 author 的产生事务进行合并和清理。通过将其设置在 batchAuthors 中，可以加速该类事务的清理。

```swift
batchAuthors: ["appBatchAuthor"],
```

即使不设定，这些事务也将在达到 maximumDuration 后被自动清除。

### maximumDuration

正常情况下，事务只有被所有的 author 都合并后才会被清理。但在某些情况下，个别 author 可能长期未运行或尚未实现，导致事务始终保持在 SQLite 中。长此以往，会造成数据库性能下降。

通过设置 maximumDuration ，Persistent History Tracking Kit 会强制清除已达到设定时长的事务。默认设置为 7 天。

```swift
maximumDuration: 60 * 60 * 24 * 7,
```

清除事务并不会对应用程序的数据造成损害。

### contexts

用于合并事务的上下文，通常情况下是应用程序的视图上下文。默认会自动设置为 container 的视图上下文。

```swift
contexts: [viewContext],
```

### userDefaults

用于保存时间戳的 UserDefaults。如果使用了 App Group，请使用可用于 group 的 UserDefaults。

```swift
let appGroupUserDefaults = UserDefaults(suiteName: "group.com.yourGroup")!

userDefaults: appGroupUserDefaults,
```

### cleanStrategy

Persistent History Tracking Kit 目前支持三种事务清理策略：

- none

  只合并，不清理

- byDuration

  设定两次清理之间的最小时间间隔

- byNotification

  设定两次清理之间的最小通知次数间隔

```swift
// 每个通知都清理
cleanStrategy: .byNotification(times: 1),
// 两次清理之间，至少间隔 60 秒
cleanStrategy: .byDuration(seconds: 60),
```

#### 推荐策略

根据 Apple 的文档建议，推荐使用 7 天的清理策略，以在性能和存储容量之间取得良好的平衡：

```swift
cleanStrategy: .byDuration(seconds: 60 * 60 * 24 * 7), // 7 天
```

这种策略允许所有 author（包括应用扩展和 CloudKit）有足够的时间来处理和合并事务，然后再进行清理。

#### 重要：与 NSPersistentCloudKitContainer 配合使用

**注意：** 默认的清理策略 `.byNotification(times: 1)` 在使用 CloudKit 同步时可能过于激进，可能导致 `NSPersistentHistoryTokenExpiredError`（错误代码 134301），从而导致本地数据库被清空并重新从 CloudKit 同步。

当使用 CloudKit 同步时，CloudKit 内部依赖 persistent history 来跟踪同步状态。如果历史记录清理过于频繁，CloudKit 可能会在完成其内部操作之前丢失其跟踪令牌。

**推荐策略：**

使用基于时间的清理策略，并设置足够的持续时间（如 7 天），以给 CloudKit 足够的时间来处理 persistent history：

```swift
let kit = PersistentHistoryTrackingKit(
    container: container,
    currentAuthor: "app1",
    allAuthors: ["app1", "app2"],
    cleanStrategy: .byDuration(seconds: 60 * 60 * 24 * 7),  // 7 天
    userDefaults: userDefaults
)
```

**重要提示：** 在此场景下，请勿设置 `includingCloudKitMirroring: true`，因为 CloudKit 会在内部处理自己的同步。将其设置为 true 会错误地将 CloudKit 的内部事务合并到您的应用上下文中。相反，应使用更长的清理间隔，以确保 CloudKit 在清理之前有足够的时间使用 persistent history。

当清理策略设置为 none 时，可以通过生成单独的清理实例，在合适的时机进行清理。

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

时间戳在 UserDefaults 中的字符串前缀。

### logger

Persistent History Tracking Kit 提供了默认的日志输出功能。如果想通过您正在使用的日志系统来输出 Persistent History Tracking Kit 的信息，只需让您的日志代码符合 PersistentHistoryTrackingKitLoggerProtocol 即可。

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

通过设定 logLevel 可以控制日志信息的输出：

- 0 关闭日志输出
- 1 仅重要状态
- 2 详细信息

### autoStart

是否在创建 Persistent History Tracking Kit 实例后，马上启动。

在应用程序的执行过程中，可以通过 start() 或 stop() 来改变运行状态。

```swift
kit.start()
kit.stop()
```

## 系统需求

​    .iOS(.v13),

​    .macOS(.v10_15),

​    .macCatalyst(.v13),

​    .tvOS(.v13),

​    .watchOS(.v6)

## 安装

```swift
dependencies: [
  .package(url: "https://github.com/fatbobman/PersistentHistoryTrackingKit.git", from: "1.0.0")
]
```

## License

This library is released under the MIT license. See [LICENSE](https://github.com/fatbobman/persistentHistoryTrackingKit/blob/main/LICENSE) for details.
