# Hook 机制指南（中文）

## 概览

PersistentHistoryTrackingKit V2 提供两类 Hook：

1. **Observer Hook**：只读回调，用于监控数据变化
2. **Merge Hook**：流水线式回调，可自定义合并逻辑并修改数据

下图展示整体架构：

```
┌─────────────────────────────────────────────────────────────────────┐
│                  PersistentHistoryTrackingKit                       │
│                                                                     │
│  ┌────────────────────┐         ┌─────────────────────────────┐    │
│  │ HookRegistryActor  │         │  TransactionProcessorActor  │    │
│  │ • Observer 注册/触发 │         │  • Merge 注册/流水线触发        │    │
│  │                    │         │  • 事务抓取与默认合并             │    │
│  └────────────────────┘         └─────────────────────────────┘    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### 事务处理流程

```
1. 抓取其他 author 的新事务（排除当前 author）
2. 顺序触发 Observer Hook（只读）
3. 运行 Merge Hook 流水线（按注册顺序串行）
4. 若流水线未返回 .finish，则执行默认合并
5. 更新当前 author 的最后事务时间戳
6. 根据策略清理历史事务
```

## Observer Hook（读取通知）

特点：

- 由 `HookRegistryActor` 管理，线程安全
- 每个 hook 返回 UUID，便于移除
- 相同实体+操作的回调按注册顺序串行触发
- 回调签名：`@Sendable ([HookContext]) async -> Void`
- `HookContext` 数组按「同一事务 + 实体名 + 操作」分组，每次触发提供该组内的全部上下文
- 单个 `HookContext` 包含实体名、操作类型、对象 ID、URL、tombstone、时间戳和 author

注册示例：

```swift
let hookId = await kit.registerObserver(
    entityName: "Person",
    operation: .insert
) { contexts in
    for context in contexts {
        print("新建 Person: \(context.objectIDURL)")
    }
}

// 若在同一事务内新增 3 个 Person，对应 Hook 只触发一次，
// contexts 数组长度为 3，可在一次回调中完成批处理。
```

移除方式：

```swift
await kit.removeObserver(id: hookId)                                 // 单个移除
await kit.removeObserver(entityName: "Person", operation: .insert)   // 批量移除
await kit.removeAllObservers()                                       // 全部移除
```

**注意**：Observer Hook 只能读取数据，不可修改 Core Data 对象。如需变更数据，请使用 Merge Hook。

## Merge Hook（自定义合并）

特点：

- 由 `TransactionProcessorActor` 管理，确保非 Sendable Core Data 类型在同一 actor 内访问
- 回调按注册顺序串行执行
- 回调签名：`@Sendable (MergeHookInput) async throws -> MergeHookResult`
- `MergeHookInput` 封装 `[NSPersistentHistoryTransaction]` 与 `[NSManagedObjectContext]`
- 返回 `.goOn` 继续下一 Hook，返回 `.finish` 停止流水线并跳过默认合并

注册示例：

```swift
let hookId = await kit.registerMergeHook { input in
    for transaction in input.transactions {
        for context in input.contexts {
            await context.perform {
                // 自定义合并
            }
        }
    }
    return .goOn
}
```

流水线插入/移除：

```swift
let hookA = await kit.registerMergeHook { _ in .goOn }
let hookB = await kit.registerMergeHook(before: hookA) { _ in .goOn } // 插入到 hookA 之前
await kit.removeMergeHook(id: hookA)
await kit.removeAllMergeHooks()
```

## 示例

### 监控 Person 新增

```swift
let observerId = await kit.registerObserver(entityName: "Person", operation: .insert) { contexts in
    for context in contexts {
        await NotificationService.send(title: "新增联系人", body: context.objectIDURL.absoluteString)
    }
}
```

### 记录删除操作

```swift
for entity in ["Person", "Item", "Order"] {
    await kit.registerObserver(entityName: entity, operation: .delete) { contexts in
        for context in contexts {
            if let tombstone = context.tombstone {
                print("删除 \(context.entityName): \(tombstone.attributes)")
            }
        }
    }
}
```

### 自定义冲突解决

```swift
await kit.registerMergeHook { input in
    for context in input.contexts {
        await context.perform {
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            for transaction in input.transactions {
                for change in transaction.changes ?? [] where change.changeType == .update {
                    if let object = try? context.existingObject(with: change.changedObjectID) {
                        // 自定义处理
                    }
                }
            }
        }
    }
    return .goOn
}
```

### 自定义合并逻辑

```swift
await kit.registerMergeHook { input in
    for context in input.contexts {
        await context.perform {
            for transaction in input.transactions {
                let notification = transaction.objectIDNotification()
                context.mergeChanges(fromContextDidSave: notification)
                // ... 额外逻辑 ...
            }
            try? context.save()
        }
    }
    return .finish
}
```

### 多阶段流水线

```swift
let validationId = await kit.registerMergeHook { input in
    guard input.transactions.allSatisfy({ $0.author != "BANNED" }) else { return .finish }
    return .goOn
}

let preprocessId = await kit.registerMergeHook { input in
    for context in input.contexts { await context.perform { /* 预处理 */ } }
    return .goOn
}

let mergeId = await kit.registerMergeHook { input in
    // 核心合并
    return .goOn
}

await kit.registerMergeHook { _ in
    // 后处理
    return .goOn
}
```

## 最佳实践

### ✅ 建议
- 使用 Observer Hook 做日志/通知/监控
- 使用 Merge Hook 处理冲突、数据转换、验证等逻辑
- 在 Merge Hook 中务必 `await context.perform { ... }`
- 利用流水线实现「验证 → 预处理 → 合并 → 后处理」
- 自行实现完整合并后可以返回 `.finish`
- 记录 hook 的 UUID，方便插拔

### ❌ 避免
- 在 Observer Hook 中修改数据
- 在 Merge Hook 中忘记 `await`，导致顺序无法保证
- 通过 `Task {}` 启动独立任务后立即返回
- 过度拆分 Hook 或在 Hook 中执行耗时操作

## 常见模式

- **审计日志**：为敏感实体的增删改注册 Observer Hook 并存入日志
- **缓存失效**：收到更新后调用缓存管理器
- **跨上下文同步**：在 Merge Hook 中对只读 UI context 调用 `refreshAllObjects()`
- **条件合并**：过滤掉来自特定 author 的事务后再决定 `.goOn` / `.finish`
- **通知节流**：通过 actor 维护发送节奏

## 线程安全

- Observer Hook：`HookRegistryActor` 负责注册和触发，`HookContext` 为 `Sendable`
- Merge Hook：全部逻辑在 `TransactionProcessorActor` 内串行执行，`MergeHookInput` 使用 `@unchecked Sendable` 封装 Core Data 类型

## 性能提示

1. Observer Hook 会顺序执行，完成后才进入 Merge 阶段
2. Merge Hook 按流水线串行运行，每个 Hook 都会阻塞下一个
3. Hook 越多，处理时间越长，建议控制在 1–5 个核心 Hook
4. Merge Hook 中的异步操作必须 `await`，避免悬挂任务

## 测试建议

- 使用 Swift Testing 或 XCTest，确保测试串行运行
- Observer Hook 可通过 actor 记录触发顺序
- Merge Hook 流水线可验证 `.goOn` / `.finish` 行为

## 参考

- `Sources/PersistentHistoryTrackingKit/HookTypes.swift`
- `Sources/PersistentHistoryTrackingKit/HookRegistryActor.swift`
- `Sources/PersistentHistoryTrackingKit/TransactionProcessorActor.swift`
- `Tests/PersistentHistoryTrackingKitTests/*Hook*Tests.swift`
