# Hook 机制指南（中文）

PersistentHistoryTrackingKit V2 将 Hook 分成两类：用于观察事务的 Observer Hook，以及用于介入合并流水线的 Merge Hook。两者解决的问题不同，执行位置也不同。选择正确的 Hook，是安全使用 persistent history transaction 的前提。

## 概览

| 你想做什么 | 选择 | 原因 |
| --- | --- | --- |
| 记录日志、发送统计、触发通知、让缓存失效 | Observer Hook | 只读、按事务变更分组回调，不参与合并 |
| 调整合并策略、处理冲突、去重、修改 Core Data 对象 | Merge Hook | 位于合并流水线中，可在正确 context 内修改数据 |
| 已完整实现自定义合并并希望跳过默认合并 | Merge Hook 并返回 `.finish` | `.finish` 会停止后续 Hook，并跳过默认合并 |
| 只想知道某个实体发生了插入、更新或删除 | Observer Hook | `HookContext` 提供 entity、operation、objectID、timestamp、author 与 tombstone |

简单规则：

- Observer Hook 只观察，不修改 Core Data 数据。
- Merge Hook 可修改数据，但必须在正确的 `NSManagedObjectContext` 执行队列或调用方自己的 actor 隔离中完成。
- Hook 回调会被 Kit 顺序 `await`，但当前版本不启用 Swift 6.2 的 `NonisolatedNonsendingByDefault`，回调体不承诺隔离在 Kit 的内部 actor 上。

## 事务处理流程

一次远程或其他 author 产生的 history transaction 被处理时，Kit 按以下顺序执行：

```text
1. 抓取事务
   读取其他 author 的新 transaction，排除 currentAuthor。

2. 触发 Observer Hook
   按 entity + operation 分组，只读通知所有匹配的 observer。

3. 运行 Merge Hook 流水线
   按注册顺序串行执行 merge hook。

4. 默认合并
   如果没有 Merge Hook 返回 .finish，Kit 会执行默认合并。

5. 更新时间戳
   为 currentAuthor 记录最后处理到的 transaction timestamp。

6. 清理历史
   根据 cleanStrategy，在满足所有必要 author timestamp 前提后清理旧 history。
```

这意味着 Observer Hook 总是在 merge 前完成；Merge Hook 则决定默认合并是否继续。

## Hook 类型对比

| 能力 | Observer Hook | Merge Hook |
| --- | --- | --- |
| 主要用途 | 监控、通知、审计、缓存失效 | 自定义合并、冲突处理、去重、验证 |
| 是否应修改数据 | 否 | 可以 |
| 输入类型 | `[HookContext]` | `MergeHookInput` |
| Core Data 类型 | 不直接暴露对象，只暴露 objectID 与 tombstone | 暴露 `[NSPersistentHistoryTransaction]` 与 `[NSManagedObjectContext]` |
| 执行顺序 | 同一 entity + operation 下按注册顺序执行 | 按流水线顺序串行执行 |
| 是否可终止后续处理 | 否 | 可返回 `.finish` |
| 单个移除 | `removeObserver(id:)` | `removeMergeHook(id:)` |
| 批量移除 | `removeObserver(entityName:operation:)`、`removeAllObservers()` | `removeAllMergeHooks()` |
| 典型场景 | 新建统计、删除日志、通知节流 | undoManager 保护、CloudKit 去重、条件合并 |

## Observer Hook

Observer Hook 面向只读监听。它由 `HookRegistryActor` 管理注册和触发；每次注册返回一个 `UUID`，便于之后单独移除。

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
```

### Context batching

Observer 回调接收的是 `[HookContext]`，而不是单个变更。Kit 会按「同一 transaction + entityName + operation」分组：

- 同一事务插入 5 个 `Person`，对应 Hook 触发 1 次，`contexts.count == 5`。
- 同一事务同时插入 `Person`、更新 `Item`，会分别触发匹配的 Hook。
- 这适合批量写日志、批量发送统计或一次性刷新缓存。

### `HookContext`

```swift
public struct HookContext: Sendable {
    public let entityName: String
    public let operation: HookOperation
    public let objectID: NSManagedObjectID
    public let objectIDURL: URL
    public let tombstone: Tombstone?
    public let timestamp: Date
    public let author: String
}
```

`HookContext` 本身是 `Sendable`，适合跨 actor 传递。但它不携带可直接修改的 managed object。需要读取或修改对象时，应通过自己的 Core Data context 和 actor/context 队列完成。

### Tombstone

`Tombstone` 只会出现在 `.delete` 操作中，用于保存删除对象的部分属性值：

```swift
public struct Tombstone: Sendable, Codable {
    public let attributes: [String: String]
    public let deletedDate: Date?
}
```

使用限制：

- `.insert` 和 `.update` 的 `tombstone` 为 `nil`。
- 只有 Core Data model 中启用了 `preservesValueInHistoryOnDeletion` 的属性才会进入 tombstone。
- 为了满足并发传递要求，属性值会转换为 `String`。常见转换包括 UUID 的 `uuidString`、URL 的 `absoluteString`、Date 的 ISO8601 字符串，以及数字的 `stringValue`。

删除审计示例：

```swift
let deleteHookId = await kit.registerObserver(
    entityName: "Person",
    operation: .delete
) { contexts in
    for context in contexts {
        guard let tombstone = context.tombstone else { continue }
        await AuditLog.record(
            entityName: context.entityName,
            objectID: context.objectIDURL.absoluteString,
            values: tombstone.attributes
        )
    }
}
```

### 移除 Observer Hook

```swift
await kit.removeObserver(id: hookId)
await kit.removeObserver(entityName: "Person", operation: .insert)
await kit.removeAllObservers()
```

- `removeObserver(id:)` 只移除指定 Hook。
- `removeObserver(entityName:operation:)` 会移除该实体和操作下的所有 Observer Hook。
- `removeAllObservers()` 会移除全部 Observer Hook。

## Merge Hook

Merge Hook 位于事务合并流水线中。它可以读取 transaction，也可以在给定的 Core Data context 中修改数据。

```swift
let hookId = await kit.registerMergeHook { input in
    for transaction in input.transactions {
        print("处理来自 \(transaction.author ?? "unknown") 的事务")
    }

    for context in input.contexts {
        await context.perform {
            // 自定义合并、冲突处理或数据修正
        }
    }

    return .goOn
}
```

### `MergeHookInput`

```swift
public struct MergeHookInput: @unchecked Sendable {
    public let transactions: [NSPersistentHistoryTransaction]
    public let contexts: [NSManagedObjectContext]
}
```

`MergeHookInput` 使用 `@unchecked Sendable`，因为它封装了 Core Data 的非 Sendable 类型。这不代表可以随意跨队列访问 Core Data 对象；修改工作仍必须放在 `await context.perform { ... }` 或调用方自己的 actor 隔离中。

### `MergeHookResult`

```swift
public enum MergeHookResult: Sendable {
    case goOn
    case finish
}
```

- `.goOn`：继续执行下一个 Merge Hook；如果流水线结束，则进入默认合并。
- `.finish`：停止后续 Merge Hook，并跳过默认合并。只有当你已经完成必要合并，或明确要拒绝这批 transaction 时才应返回。

### 插入顺序与移除

Merge Hook 使用 UUID 管理流水线。默认追加到末尾，也可以插入到某个 Hook 之前：

```swift
let validationId = await kit.registerMergeHook { input in
    guard input.transactions.allSatisfy({ $0.author != "BANNED_USER" }) else {
        return .finish
    }
    return .goOn
}

let mergeId = await kit.registerMergeHook { input in
    for context in input.contexts {
        await context.perform {
            // 核心合并逻辑
        }
    }
    return .goOn
}

let preprocessId = await kit.registerMergeHook(before: mergeId) { input in
    // 在核心合并前执行
    return .goOn
}

await kit.removeMergeHook(id: validationId)
await kit.removeAllMergeHooks()
```

## 执行流对比

Observer Hook 是顺序通知模型：

```text
Transaction detected
        |
        v
HookRegistryActor
        |
        +--> Observer 1 callback
        +--> Observer 2 callback
        +--> Observer 3 callback
        |
        v
Merge phase
```

Merge Hook 是串行流水线模型：

```text
Transaction detected
        |
        v
TransactionProcessorActor
        |
        +--> Merge Hook 1 -- .goOn --> Merge Hook 2 -- .goOn --> default merge
        |
        +--> any hook returns .finish --> skip remaining hooks and default merge
```

没有注册 Merge Hook 时，Kit 直接执行默认合并。所有 Merge Hook 都返回 `.goOn` 时，默认合并继续执行。任一 Merge Hook 返回 `.finish` 时，后续 Hook 与默认合并都会被跳过。

## 使用示例

### 监控新增对象

```swift
let observerId = await kit.registerObserver(
    entityName: "Person",
    operation: .insert
) { contexts in
    for context in contexts {
        await NotificationService.send(
            title: "新增联系人",
            body: context.objectIDURL.absoluteString
        )
    }
}
```

### 记录删除操作

```swift
var deleteHookIds: [UUID] = []

for entityName in ["Person", "Item", "Order"] {
    let hookId = await kit.registerObserver(
        entityName: entityName,
        operation: .delete
    ) { contexts in
        for context in contexts {
            await AuditLog.record(
                entityName: context.entityName,
                objectID: context.objectIDURL.absoluteString,
                author: context.author,
                tombstone: context.tombstone
            )
        }
    }
    deleteHookIds.append(hookId)
}
```

### 自定义冲突处理

```swift
await kit.registerMergeHook { input in
    for context in input.contexts {
        await context.perform {
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

            for transaction in input.transactions {
                for change in transaction.changes ?? [] where change.changeType == .update {
                    if let object = try? context.existingObject(with: change.changedObjectID) {
                        print("处理更新冲突: \(object)")
                    }
                }
            }
        }
    }

    return .goOn
}
```

### 替换默认合并

```swift
await kit.registerMergeHook { input in
    for context in input.contexts {
        await context.perform {
            for transaction in input.transactions {
                let notification = transaction.objectIDNotification()
                context.mergeChanges(fromContextDidSave: notification)
            }
            try? context.save()
        }
    }

    return .finish
}
```

这里返回 `.finish`，因为 Hook 已经完成合并。如果返回 `.goOn`，Kit 之后还会执行默认合并，可能造成重复工作或行为冲突。

### 多阶段流水线

```swift
let validationId = await kit.registerMergeHook { input in
    guard input.transactions.allSatisfy({ $0.author != "BANNED_USER" }) else {
        return .finish
    }
    return .goOn
}

let preprocessId = await kit.registerMergeHook { input in
    for context in input.contexts {
        await context.perform {
            // 预处理：规范化字段、填充默认值等
        }
    }
    return .goOn
}

let mergeId = await kit.registerMergeHook { input in
    for context in input.contexts {
        await context.perform {
            // 核心合并逻辑
        }
    }
    return .goOn
}

let postprocessId = await kit.registerMergeHook { input in
    for context in input.contexts {
        await context.perform {
            // 后处理：更新派生值、刷新状态等
        }
    }
    return .goOn
}
```

## 真实场景

### 合并时临时禁用 `undoManager`

当目标 context 启用了 `undoManager`，合并 history transaction 时可能产生不需要的 undo 记录。可以用 Merge Hook 接管合并，并在合并期间临时关闭 `undoManager`：

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

适用条件：

- 你的 context 启用了 `undoManager`。
- 你不希望 history merge 写入 undo 栈。
- 你已经在 Hook 中完成合并，因此返回 `.finish` 跳过默认合并。

### CloudKit / 多设备同步中的去重

CloudKit 或多设备写入可能让业务上同一条记录被创建多次。如果实体有稳定唯一键，可以在 Merge Hook 中处理插入事务并删除重复对象：

```swift
await kit.registerMergeHook { input in
    for context in input.contexts {
        await context.perform {
            for transaction in input.transactions {
                for change in transaction.changes ?? [] where change.changeType == .insert {
                    guard
                        let inserted = try? context.existingObject(with: change.changedObjectID),
                        let uniqueID = inserted.value(forKey: "uniqueID") as? String,
                        let entityName = inserted.entity.name
                    else {
                        continue
                    }

                    let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
                    request.predicate = NSPredicate(format: "uniqueID == %@", uniqueID)

                    guard let objects = try? context.fetch(request), objects.count > 1 else {
                        continue
                    }

                    let sorted = objects.sorted {
                        ($0.value(forKey: "createdAt") as? Date ?? .distantPast)
                            < ($1.value(forKey: "createdAt") as? Date ?? .distantPast)
                    }

                    for duplicate in sorted.dropFirst() {
                        context.delete(duplicate)
                    }
                }
            }

            try? context.save()
        }
    }

    return .goOn
}
```

这个模式适合存在业务唯一键的实体。去重策略应按业务需求决定保留最早、最新，或把重复对象内容合并到保留对象。

## 最佳实践

### 建议

- 用 Observer Hook 做日志、统计、通知、审计和缓存失效。
- 用 Merge Hook 做冲突处理、数据转换、自定义合并、合并前验证和去重。
- 在 Merge Hook 中始终等待 Core Data 工作完成：`await context.perform { ... }`。
- 把相关逻辑合并在少量 Hook 中，减少串行流水线开销。
- 记录注册返回的 UUID，便于运行时插拔或释放 Hook。
- 只有完整接管合并或明确拒绝 transaction 时才返回 `.finish`。

### 避免

- 不要在 Observer Hook 中修改 Core Data 对象。
- 不要在 Merge Hook 中漏掉 `await context.perform { ... }`。
- 不要在 Hook 中启动不受等待的 `Task { ... }` 后立即返回；这会让流水线以为工作已完成。
- 不要把长耗时网络请求直接放进 Hook；Hook 会阻塞 transaction 处理。
- 不要过度拆分 Hook。多个串行 Hook 会放大延迟，也会增加执行顺序的理解成本。

## 常见模式

### 审计日志

为敏感实体的插入、更新、删除注册 Observer Hook，将 `entityName`、`operation`、`objectIDURL`、`timestamp`、`author` 与 `tombstone` 写入审计系统。

### 缓存失效

对影响缓存的实体注册 Observer Hook，在回调中通知缓存 actor 失效指定 key。若需要合并后再刷新，可改用 Merge Hook 或在 Observer 中只发出轻量信号。

### 跨上下文刷新

在 Merge Hook 中对只读 UI context 调用 `refreshAllObjects()`，确保界面读取到最新状态：

```swift
await kit.registerMergeHook { input in
    for context in input.contexts {
        await context.perform {
            context.refreshAllObjects()
        }
    }
    return .goOn
}
```

### 条件合并

在 Merge Hook 中检查 author、实体或业务标记。若本轮 transaction 不应继续处理，可返回 `.finish`；若只是过滤部分业务逻辑但仍希望默认合并执行，应返回 `.goOn`。

### 通知节流

使用自定义 actor 记录上次通知时间，在 Observer Hook 中集中判断是否发送通知。这样既避免共享静态状态，也避免并发测试下的数据竞争。

## 线程安全与回调上下文

Observer Hook：

- 注册与触发由 `HookRegistryActor` 管理。
- 匹配的回调按注册顺序被 `await`。
- `HookContext` 是 `Sendable`，适合交给应用自己的 actor。
- 回调体不隔离在内部 registry actor 上；修改应用状态时应切换到自己的 actor。

Merge Hook：

- 流水线由 `TransactionProcessorActor` 按注册顺序串行 `await`。
- `MergeHookInput` 携带 Core Data 类型，因此使用 `@unchecked Sendable`。
- 回调体不隔离在内部 processor actor 上。
- 任何 Core Data 对象读取或修改都应放进 `await context.perform { ... }`，或由调用方明确的 actor / context 队列保护。

当前版本不启用 Swift 6.2 的 `NonisolatedNonsendingByDefault`。不要把“由 actor 顺序 await”误解为“回调体运行在该 actor 隔离内”。

## 性能与生命周期约束

- Observer Hook 会在 Merge 阶段之前完成。耗时 Observer 会推迟后续合并。
- Merge Hook 串行阻塞后续 Hook、默认合并、timestamp 更新与 cleanup。
- 典型项目应保持少量核心 Hook；若多个 Hook 总是一起工作，优先合并为一个更清晰的 Hook。
- `Task { ... }` 或 `Task.detached { ... }` 不应被用来绕过流水线等待。若必须触发后台工作，Hook 内应只提交轻量信号，并让外部组件负责生命周期。
- 保存 Hook UUID，组件销毁或功能关闭时及时移除，避免已经失效的回调继续参与处理。

## 测试建议

建议通过真实 transaction 路径测试 Hook，而不是手工构造 `HookContext`、`NSManagedObjectID` 或 Core Data artifact：

- 使用 actor-isolated tracker 记录 Observer 或 Merge Hook 的触发结果。
- 使用 `TestAppDataHandler` 这类 actor-isolated helper 创建、更新、删除测试数据。
- 需要检查 handler 持有的 context 时，使用它提供的 `withContext` API，而不是在测试体中直接对 raw context 调用 `perform`。
- Swift Testing 的并行运行是同进程并发，不是每个 test case 的进程隔离；避免依赖共享 `static` 可变状态。
- 不要为了 Hook 测试把整个 suite 全局串行化。当前测试基础设施已经支持并行运行，并在内部串行化 Core Data container 创建。

Observer Hook 测试形状：

```swift
actor CallbackTracker {
    private var contexts: [HookContext] = []

    func record(_ newContexts: [HookContext]) {
        contexts.append(contentsOf: newContexts)
    }

    func snapshot() -> [HookContext] {
        contexts
    }
}

let tracker = CallbackTracker()

await kit.registerObserver(entityName: "Person", operation: .insert) { contexts in
    await tracker.record(contexts)
}

// 通过真实 Core Data 写入触发 Kit 处理

let contexts = await tracker.snapshot()
#expect(contexts.contains { $0.entityName == "Person" && $0.operation == .insert })
```

Merge Hook 测试形状：

```swift
actor OrderTracker {
    private var values: [Int] = []

    func append(_ value: Int) {
        values.append(value)
    }

    func snapshot() -> [Int] {
        values
    }
}

let tracker = OrderTracker()

await kit.registerMergeHook { _ in
    await tracker.append(1)
    return .goOn
}

await kit.registerMergeHook { _ in
    await tracker.append(2)
    return .goOn
}

// 通过真实事务触发处理

#expect(await tracker.snapshot() == [1, 2])
```

## 从 V1 迁移

V1 的扩展点不是统一的 Hook API，而是围绕 fetcher / merger / cleaner 组成的处理管线，并通过协议注入定制行为。迁移到 V2 时，重点不是寻找 V1 的同名 Hook，而是判断旧定制点在 V2 中应该落到 Observer Hook、Merge Hook，还是新的手动清理 actor。

| V1 定制点 | V2 对应 |
| --- | --- |
| `TransactionMergerProtocol` 自定义合并 | 使用 Merge Hook |
| `TransactionDeduplicatorProtocol` 去重 | 在 Merge Hook 中实现去重 |
| 合并流程中夹带的只读副作用 | 拆到 Observer Hook，并按 entity + operation 注册 |
| 删除后读取保留字段 | 在 Observer Hook 中读取 `Tombstone` |
| `cleanerBuilder()` 手动清理 | `cleanerBuilder()` 返回 `ManualCleanerActor` 后调用 `await cleaner.clean()` |
| 依赖 `maximumDuration` 强制清理 | 选择 `.none` 后手动清理，或重新设计宽松的 `.byDuration` 策略 |

V1 典型定制形态：

```swift
struct CustomMerger: TransactionMergerProtocol {
    func callAsFunction(
        merge transactions: [NSPersistentHistoryTransaction],
        into contexts: [NSManagedObjectContext]
    ) {
        // 自定义合并逻辑
    }
}

struct CustomDeduplicator: TransactionDeduplicatorProtocol {
    func callAsFunction(
        deduplicate transactions: [NSPersistentHistoryTransaction],
        in contexts: [NSManagedObjectContext]
    ) {
        // 去重逻辑
    }
}

let kit = PersistentHistoryTrackingKit(
    container: container,
    currentAuthor: "MainApp",
    allAuthors: ["MainApp", "WidgetExtension"],
    userDefaults: userDefaults,
    merger: CustomMerger(),
    deduplicator: CustomDeduplicator()
)
```

V2 形状：

```swift
let observerId = await kit.registerObserver(
    entityName: "Person",
    operation: .insert
) { contexts in
    // 只读监听
}

let mergeId = await kit.registerMergeHook { input in
    // 自定义合并或去重；如需修改 Core Data，请使用 await context.perform
    return .goOn
}
```

迁移时先判断旧定制点的职责：

- 只是记录日志、统计、通知或缓存失效：迁移到 Observer Hook。
- 修改 Core Data、调整合并策略、处理冲突或去重：迁移到 Merge Hook。
- 旧 `TransactionMergerProtocol` 已完整处理合并：在 Merge Hook 中返回 `.finish`。
- 仍希望 Kit 执行默认合并：在 Merge Hook 中返回 `.goOn`。
- 以前依赖 V1 的强制清理：重新审视 `allAuthors` / `batchAuthors`，并优先选择手动清理或足够宽松的时间清理策略。

更完整的迁移说明见 [`Docs/MigrationGuideCN.md`](MigrationGuideCN.md)。

## 总结

- Observer Hook 是只读通知层，适合监控与副作用信号。
- Merge Hook 是合并流水线层，适合修改数据与控制默认合并是否继续。
- Observer 先于 Merge 执行；Merge Hook 返回 `.finish` 会跳过后续 Hook 与默认合并。
- Hook 回调会被顺序 `await`，但不承诺隔离在 Kit 内部 actor 上。
- CloudKit、多 author 与 cleanup 场景中，应避免激进清理，并理解所有必要 author timestamp 对共同清理点的影响。

## 参考

- [`Sources/PersistentHistoryTrackingKit/HookTypes.swift`](../Sources/PersistentHistoryTrackingKit/HookTypes.swift)
- [`Sources/PersistentHistoryTrackingKit/HookRegistryActor.swift`](../Sources/PersistentHistoryTrackingKit/HookRegistryActor.swift)
- [`Sources/PersistentHistoryTrackingKit/TransactionProcessorActor.swift`](../Sources/PersistentHistoryTrackingKit/TransactionProcessorActor.swift)
- [`Tests/PersistentHistoryTrackingKitTests/HookRegistryActorTests.swift`](../Tests/PersistentHistoryTrackingKitTests/HookRegistryActorTests.swift)
- [`Tests/PersistentHistoryTrackingKitTests/MergeHookTests.swift`](../Tests/PersistentHistoryTrackingKitTests/MergeHookTests.swift)
- [`Tests/PersistentHistoryTrackingKitTests/TombstoneTests.swift`](../Tests/PersistentHistoryTrackingKitTests/TombstoneTests.swift)
- [`Docs/MigrationGuideCN.md`](MigrationGuideCN.md)
