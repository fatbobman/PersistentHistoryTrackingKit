# 迁移指南：从 V1 到 V2

本文档面向从 PersistentHistoryTrackingKit V1 迁移到 V2 的项目。

V2 不是兼容性小版本，而是一次完整重写。它引入了新的并发模型、扩展点，以及不同的清理语义。

## 你是否应该迁移？

满足以下条件时，建议迁移到 V2：

- 目标平台已经是 iOS 17+、macOS 14+、tvOS 17+ 或 watchOS 10+
- 准备切换到 Swift 6
- 希望使用 actor 架构和 async Hook API
- 希望获得 Observer Hook、Merge Hook 与 tombstone 支持

以下情况建议继续留在 V1：

- 仍需支持旧系统
- 暂时不准备迁移到 Swift 6
- 更希望保留 V1 的 fetch / merge / cleaner 定制模型

## 核心差异

### V1

- 以 fetcher / merger / cleaner 管线为核心
- 主要通过协议注入进行自定义，例如 `TransactionMergerProtocol`
- 提供 deduplicator 扩展点
- 通过任务管理处理通知监听
- 提供可直接调用的 manual cleaner

### V2

- 基于 actor 完全重写
- 以 `HookRegistryActor` 和 `TransactionProcessorActor` 为核心
- 使用 async Observer Hook 和 Merge Hook 取代协议注入
- 新增分组 observer 回调与 tombstone 支持
- 使用 `ManualCleanerActor` 执行手动清理

## 运行环境变化

### V1

- 面向 Swift 5 时代的 API 设计
- 具体支持平台取决于你正在使用的 V1 发布版本

### V2

- Swift 6
- iOS 17+
- macOS 14+
- macCatalyst 17+
- tvOS 17+
- watchOS 10+

## 包和依赖变化

### V1

- 依赖 `swift-async-algorithms`

### V2

- 依赖 `CoreDataEvolution`
- 通过 `@NSModelActor` 使用 actor 化的 Core Data 辅助能力

## API 对照

| V1 概念 | V2 对应方式 |
|---|---|
| 协议式 merger | `registerMergeHook` |
| 协议式 deduplicator | `registerMergeHook` |
| 合并流程中的只读副作用 | `registerObserver` |
| 可调用 manual cleaner | `cleanerBuilder()` 返回 `ManualCleanerActor` |
| 通知驱动的任务管理 | 内部 actor 驱动处理 |
| `performAndWaitWithResult` 辅助方法 | 在常规 V2 用法里通常不再需要 |

## 初始化方式变化

### V2 典型写法

```swift
let kit = PersistentHistoryTrackingKit(
    container: container,
    contexts: [container.viewContext],
    currentAuthor: "MainApp",
    allAuthors: ["MainApp", "WidgetExtension"],
    userDefaults: userDefaults,
    cleanStrategy: .byDuration(seconds: 60 * 60 * 24 * 7),
    logLevel: 1
)
```

## 自定义合并逻辑

### V1

如果你在 V1 中定制过 merge 行为，通常是通过实现 `TransactionMergerProtocol`。

### V2

请改为注册 Merge Hook：

```swift
let hookID = await kit.registerMergeHook { input in
    for context in input.contexts {
        await context.perform {
            // 自定义 merge 逻辑
        }
    }
    return .goOn
}
```

如果你的 Hook 已经完整处理了合并流程，并且不希望再执行默认 merge，请返回 `.finish`。

## 去重逻辑

### V1

V1 提供了独立的 deduplicator 协议。

### V2

V2 不再提供单独的 deduplicator 协议。请把去重逻辑放进 Merge Hook：

```swift
await kit.registerMergeHook { input in
    for context in input.contexts {
        await context.perform {
            // 去重逻辑
        }
    }
    return .goOn
}
```

## 只读监控能力

### V1

V1 没有 V2 这种 observer hook 模型。

### V2

可以使用 Observer Hook 做日志、统计、缓存失效、通知派发等只读操作：

```swift
let id = await kit.registerObserver(entityName: "Person", operation: .insert) { contexts in
    for context in contexts {
        print(context.objectIDURL)
    }
}
```

Observer 回调会按照“事务 + 实体名 + 操作类型”分组。

## 删除处理与 Tombstone

这是 V2 相对 V1 的一个明确能力升级。

如果模型中的属性启用了 `preservesValueInHistoryOnDeletion`，删除类 observer hook 可以通过
`HookContext.tombstone` 读取这些保留下来的值。

## 清理语义变化

这是迁移时最重要的行为差异之一。

### V1

- `maximumDuration` 会参与清理就绪判断
- 即便有些 author 还没 merge，只要超过设定时长，也可能被强制清理

### V2

- 自动清理采用保守策略
- 只有当前 `cleanStrategy` 允许时才会尝试清理
- 只有所有非 batch author 都记录了 merge 时间戳后才会执行自动清理
- 只要任何一个必要 author 缺失时间戳，就会跳过自动清理

这种设计对多 author、App Group、扩展场景更安全。

### 那 `maximumDuration` 现在做什么？

在当前 V2 实现里，`maximumDuration` 被保留给未来的清理就绪策略，不再作为隐式的强制清理回退逻辑。

如果你以前依赖 V1 的强制清理行为，现在建议改为：

- 显式使用手动清理
- 重新审视 `allAuthors` 的组成
- 把只写不读的参与者放进 `batchAuthors`

## CloudKit 注意事项

V1 关于 CloudKit 的使用建议在方向上仍然成立，但 V2 的边界更清晰：

- 当 CloudKit 依赖 persistent history 时，不要激进清理
- 除非你非常明确该工作流，否则不要开启 `includingCloudKitMirroring`
- 有 CloudKit 时优先使用时间跨度足够长的 duration 策略

## 手动清理迁移

### V1

```swift
let cleaner = kit.cleanerBuilder()
cleaner()
```

### V2

```swift
let cleaner = kit.cleanerBuilder()

Task {
    await cleaner.clean()
}
```

## 日志

`logLevel` 在 V2 里仍然保留，但日志行为更简单，并且在初始化时固定。

如果你在 V1 里使用了自定义 logger，迁移通常比较直接：

```swift
struct MyLogger: PersistentHistoryTrackingKitLoggerProtocol {
    func log(type: PersistentHistoryTrackingKitLogType, message: String) {
        Logger.log(type, message)
    }
}
```

## 迁移检查清单

1. 确认部署目标和 Swift 版本满足 V2 要求。
2. 把 V1 的 merger / deduplicator 定制迁移到 Merge Hook。
3. 把只读监控逻辑迁移到 Observer Hook。
4. 重新审视 `allAuthors` 和 `batchAuthors`。
5. 如果之前依赖强制清理，重新设计清理策略。
6. App Group 场景使用共享 `UserDefaults`。
7. 测试时使用串行执行，不要并行跑全量测试。

## 测试说明

当前仓库的全量测试应视为串行测试。

- 命令行：`swift test --no-parallel`
- 或直接使用：`./test.sh`
- Xcode 中请关闭 package 的并行测试

## 相关文档

- [Hook 机制指南](HookMechanismCN.md)
- [README 中文版](../READMECN.md)
- [English Migration Guide](MigrationGuide.md)
