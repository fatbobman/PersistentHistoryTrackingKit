# Persistent History Tracking Kit

兼容 Swift 6 的 Core Data 持久性历史跟踪库，具备完整的并发安全性和线程安全操作。

![os](https://img.shields.io/badge/Platform%20Compatibility-iOS%20|%20macOS%20|%20tvOS%20|%20watchOS-blue) ![swift](https://img.shields.io/badge/Swift%20Compatibility-5.5%20|%206.0-green) ![concurrency](https://img.shields.io/badge/Concurrency-Safe-brightgreen) ![sendable](https://img.shields.io/badge/Sendable-Compliant-orange) [![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/fatbobman/PersistentHistoryTrackingKit)

[English Version](https://github.com/fatbobman/PersistentHistoryTrackingKit/blob/main/README.md)

## ✨ 主要特性

- 🚀 **Swift 6 就绪**: 完全兼容 Swift 6 的严格并发检查
- 🔒 **线程安全**: 真正的 `Sendable` 合规，具备适当的同步机制
- 🔄 **自动同步**: 在应用目标和扩展之间无缝同步数据
- 🧹 **智能清理**: 具备多种策略的智能事务清理
- 📱 **多目标支持**: 非常适合带有扩展、小组件和后台任务的应用
- ⚡ **高性能**: 针对最小开销和快速操作进行了优化
- 🛡️ **内存安全**: 无保留循环或内存泄漏
- 🧪 **充分测试**: 包含 31 个通过测试的综合测试套件

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

## 🚀 Swift 6 兼容性

本库完全兼容 Swift 6 的严格并发检查：

- ✅ **真正的 Sendable 合规**: 不仅仅是 `@unchecked Sendable` - 正确实现了线程安全
- ✅ **Actor 隔离**: 遵循 Swift 的 actor 隔离规则
- ✅ **无数据竞争**: 全面的并发测试确保无数据竞争
- ✅ **内存安全**: 无保留循环或内存泄漏
- ✅ **Async/Await 就绪**: 现代 Swift 并发模式

### 并发测试

本库包含全面的并发测试，可以通过以下方式运行：

```bash
# 启用 Core Data 并发调试
export NSDebugConcurrencyType=1
export NSCoreDataConcurrencyDebug=1

# 运行带有并发检查的测试
swift test --package-path .
```

## 使用方法

### 基本设置

```swift
import PersistentHistoryTrackingKit

class CoreDataStack {
    private var kit: PersistentHistoryTrackingKit?
    
    init() {
        container = NSPersistentContainer(name: "DataModel")
        
        // 配置持久存储以支持历史跟踪
        let description = container.persistentStoreDescriptions.first!
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Core Data 加载失败: \(error.localizedDescription)")
            }
        }
        
        // 设置事务作者
        container.viewContext.transactionAuthor = "MainApp"
        
        // 初始化 kit
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

### App Groups 的高级配置

```swift
// 对于具有多个目标（主应用 + 扩展）的应用
class AppGroupCoreDataStack {
    private let kit: PersistentHistoryTrackingKit
    
    init() {
        // 使用 App Group 容器
        let container = NSPersistentContainer(name: "SharedDataModel")
        
        // 配置共享访问
        let storeURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.example.app")?
            .appendingPathComponent("SharedData.sqlite")
        
        let description = NSPersistentStoreDescription(url: storeURL!)
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, _ in }
        
        // 使用正确的配置初始化
        kit = PersistentHistoryTrackingKit(
            container: container,
            currentAuthor: "MainApp",
            allAuthors: ["MainApp", "ShareExtension", "WidgetExtension", "BackgroundSync"],
            batchAuthors: ["BackgroundSync"], // 用于批处理操作
            userDefaults: UserDefaults(suiteName: "group.com.example.app")!,
            cleanStrategy: .byNotification(times: 2),
            maximumDuration: 60 * 60 * 24 * 7, // 7 天
            logLevel: 2
        )
    }
}
```

### Swift Testing 框架

本库使用现代的 Swift Testing 框架。以下是如何测试您的集成：

```swift
import Testing
import PersistentHistoryTrackingKit

@Test("多应用同步正常工作")
func testMultiAppSync() async throws {
    // 您的测试实现
    let kit1 = PersistentHistoryTrackingKit(/* app1 的配置 */)
    let kit2 = PersistentHistoryTrackingKit(/* app2 的配置 */)
    
    // 测试应用间的数据同步
    // ...
    
    kit1.stop()
    kit2.stop()
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
// 不自动清理
cleanStrategy: .none,
```

### ⚠️ 重要：清理策略建议

**避免频繁的清理操作**以保持最佳性能：

#### 推荐策略

1. **`.byDuration()` - 适用于大多数应用的首选方案**

   ```swift
   // 每几个小时清理一次（推荐）
   cleanStrategy: .byDuration(seconds: 60 * 60 * 4) // 4 小时
   
   // 或者对于低活跃度应用，每天清理一次
   cleanStrategy: .byDuration(seconds: 60 * 60 * 24) // 24 小时
   ```

2. **`.none` 配合手动清理 - 最佳的完全控制方案**

   ```swift
   // 设置为不自动清理
   cleanStrategy: .none
   
   // 在最佳时机执行手动清理
   let cleaner = kit.cleanerBuilder()
   
   // 示例：当应用进入后台时清理
   NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
       cleaner()
   }
   ```

3. **`.byNotification()` - 谨慎使用**

   ```swift
   // 避免过于频繁的清理
   cleanStrategy: .byNotification(times: 50) // 每 50 个通知清理一次，而不是 1 次
   ```

#### 为什么要避免频繁清理？

- **性能影响**: 频繁的清理操作会影响数据库性能
- **不必要的开销**: 大多数应用程序不需要在每次更改后立即清理
- **电池寿命**: 减少不必要的后台处理
- **资源优化**: 允许系统更高效地批处理操作

#### 最佳实践

- 使用 `.byDuration()` 配合**几小时到几天**的间隔
- 考虑您应用的使用模式（高活跃度 vs 低活跃度）
- 在开发过程中监控日志中的清理频率
- 对于可预测使用模式的应用使用手动清理

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

## 🎯 最佳实践

### 1. Swift 6 迁移

迁移到 Swift 6 时，本库提供完全兼容性：

- 在项目中启用严格并发检查
- 本库是真正的 `Sendable` 合规（不仅仅是 `@unchecked`）
- 您现有的使用方式无需更改代码

### 2. 内存管理

```swift
class DataManager {
    private var kit: PersistentHistoryTrackingKit?
    
    deinit {
        // 始终停止 kit 以防止内存泄漏
        kit?.stop()
    }
}
```

### 3. App Group 配置

```swift
// 在所有目标中使用一致的标识符
let groupDefaults = UserDefaults(suiteName: "group.com.yourapp.shared")!
let kit = PersistentHistoryTrackingKit(
    container: container,
    currentAuthor: "MainApp", // 每个目标唯一
    allAuthors: ["MainApp", "ShareExtension", "WidgetExtension"],
    userDefaults: groupDefaults, // 共享的 UserDefaults
    cleanStrategy: .byNotification(times: 1)
)
```

### 4. 并发测试

```bash
# 运行提供的并发测试脚本
./run_tests_with_concurrency_checks.sh

# 或者手动使用环境变量
export NSDebugConcurrencyType=1
export NSCoreDataConcurrencyDebug=1
swift test --package-path .
```

### 5. 事务清理策略

选择合适的清理策略以获得最佳性能：

```swift
// ✅ 推荐：每几个小时清理一次
let kit = PersistentHistoryTrackingKit(
    container: container,
    currentAuthor: "MainApp",
    allAuthors: ["MainApp", "Extension"],
    userDefaults: userDefaults,
    cleanStrategy: .byDuration(seconds: 60 * 60 * 6), // 6 小时
    logLevel: 1
)

// ✅ 也不错：手动清理以获得完全控制
let kitWithManualCleanup = PersistentHistoryTrackingKit(
    // ... 其他配置
    cleanStrategy: .none
)

// 在适当时候清理（例如，应用进入后台）
let cleaner = kitWithManualCleanup.cleanerBuilder()
// 在需要时调用 cleaner()

// ⚠️ 避免：过于频繁的自动清理
// cleanStrategy: .byNotification(times: 1) // 这太频繁了！
```

### 6. 错误处理

```swift
// kit 内部处理大多数错误，但要监控日志
let kit = PersistentHistoryTrackingKit(
    // ... 配置
    logLevel: 2 // 启用详细日志用于调试
)
```

## 系统需求

### 最低平台版本

- iOS 13.0+
- macOS 10.15+
- macCatalyst 13.0+
- tvOS 13.0+
- watchOS 6.0+

### Swift 版本

- Swift 5.5+（基本功能）
- Swift 6.0+（完整并发特性）

### Xcode

- Xcode 14.0+（支持 Swift 5.5）
- Xcode 16.0+（支持 Swift 6.0）

## 📦 安装

### Swift Package Manager

将此包添加到您的 `Package.swift` 文件中：

```swift
dependencies: [
    .package(url: "https://github.com/fatbobman/PersistentHistoryTrackingKit.git", from: "1.0.0")
]
```

### Xcode 集成

1. 在 Xcode 中，选择 **File > Add Package Dependencies...**
2. 输入仓库 URL：`https://github.com/fatbobman/PersistentHistoryTrackingKit.git`
3. 选择 **Up to Next Major Version** 并点击 **Add Package**

### Swift 6 特定设置

对于 Swift 6 项目，您可以使用 Swift 6 特定的包清单：

```swift
// 使用 Swift 6 构建时会自动使用 Package@swift-6.swift
```

## 🔄 迁移指南

### 从 Swift 6 之前的版本

如果您要从早期版本升级：

1. **无需 API 更改**：公共 API 保持不变
2. **增强的安全性**：您现有的代码现在受益于真正的 `Sendable` 合规
3. **更好的性能**：内存泄漏和保留循环已被消除
4. **改进的测试**：切换到 Swift Testing 框架以获得更好的异步支持

### 迁移示例

```swift
// 之前（仍然可以工作）
let kit = PersistentHistoryTrackingKit(/* 您的配置 */)

// 之后（相同的 API，增强的安全性）
let kit = PersistentHistoryTrackingKit(/* 您的配置 */)
// 现在具有真正的 Sendable 合规和内存安全！
```

## 🧪 测试

### 运行测试

```bash
# 基本测试运行
swift test

# 带有并发调试
./run_tests_with_concurrency_checks.sh

# 特定测试套件
swift test --filter "QuickIntegrationTests"
swift test --filter "ComprehensiveIntegrationTests"
```

### 测试覆盖

本库包含全面的测试：

- ✅ 31 个测试覆盖所有功能
- ✅ 多应用同步场景
- ✅ 批处理操作处理
- ✅ 并发压力测试
- ✅ 内存泄漏检测
- ✅ Swift 6 并发合规

## 🤝 贡献

欢迎贡献！请随时提交 Pull Request。对于重大更改，请先开启 issue 讨论您想要更改的内容。

### 开发

1. Fork 仓库
2. 创建您的特性分支（`git checkout -b feature/amazing-feature`）
3. 运行带有并发检查的测试：`./run_tests_with_concurrency_checks.sh`
4. 提交您的更改（`git commit -m 'Add some amazing feature'`）
5. 推送到分支（`git push origin feature/amazing-feature`）
6. 开启 Pull Request

### 测试指南

- 所有新功能都必须包含测试
- 测试必须在启用 Swift 6 严格并发检查的情况下通过
- 新测试使用 Swift Testing 框架
- 确保没有内存泄漏或保留循环

## 📚 相关资源

- [Core Data 持久历史跟踪指南](https://fatbobman.com/zh/posts/persistenthistorytracking/)
- [Swift 6 并发文档](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)
- [Core Data 编程指南](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreData/)

## 🙏 致谢

- 特别感谢 Swift 社区向更安全并发的演进
- 感谢 Apple 的 Core Data 团队提供持久历史跟踪基础
- 感谢所有帮助改进本库的贡献者

## 支持项目

- [🎉 订阅我的 Swift 周报](https://weekly.fatbobman.com)
- [☕️ 请我喝咖啡](https://buymeacoffee.com/fatbobman)

## License

This library is released under the MIT license. See [LICENSE](https://github.com/fatbobman/persistentHistoryTrackingKit/blob/main/LICENSE) for details.

---

**为 Swift 社区用❤️制作**
