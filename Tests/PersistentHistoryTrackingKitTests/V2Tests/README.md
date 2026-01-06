# V2 测试套件

## 测试清单

### ✅ 已创建的测试文件

1. **TestModels.swift** - 测试基础设施
   - 纯代码创建 NSManagedObjectModel
   - Person Entity（尝试设置墓碑属性）
   - Item Entity（普通属性）
   - In-Memory Container 创建

2. **HookRegistryActorTests.swift** - Hook 注册表测试
   - 注册和触发 Hook
   - 移除 Hook
   - 多个 Hook 并发触发
   - 不同 Entity 的 Hook 互不干扰

3. **TransactionProcessorActorTests.swift** - 事务处理器测试
   - Fetch transactions（排除当前 author）
   - Clean transactions（按时间戳和 authors）
   - Process new transactions（完整流程）
   - Trigger hooks during processing
   - Get last transaction timestamp

4. **ManualCleanerActorTests.swift** - 手动清理器测试
   - 执行清理 - 正常流程
   - 获取最后共同时间戳
   - 空时间戳处理
   - 清理后验证事务数量

5. **IntegrationTests.swift** - 集成测试
   - 两个 App 简单同步
   - Hook 触发测试
   - 手动清理器测试
   - 批量操作同步
   - 多 Context 同步

6. **ConcurrencyTests.swift** - 并发安全测试
   - 多线程并发写入
   - 多 Actor 并发访问
   - Clean 和 Fetch 并发
   - Hook 并发触发
   - 多个 Kit 实例并发运行
   - Cleaner 并发执行

## ⚠️ 需要修复的问题

### 1. 墓碑属性设置（TestModels.swift）

**问题：** `NSAttributeDescription` 没有 `isPreservedWhenTombstone` 属性

**解决方案：**
- 这个属性可能是 SwiftData 特有的，或者需要不同的 API
- 可以移除墓碑设置，或者使用 `valueTransformer` 等其他方式

### 2. HookCallback 类型不支持 async（多个测试文件）

**问题：** `HookCallback` 被定义为同步的 `@Sendable (HookContext) -> Void`，但测试中使用了 `async` 闭包

**当前定义（HookTypes.swift）：**
```swift
public typealias HookCallback = @Sendable (HookContext) -> Void
```

**需要改为：**
```swift
public typealias HookCallback = @Sendable (HookContext) async -> Void
```

**影响的测试：**
- HookRegistryActorTests.swift (3 处)
- IntegrationTests.swift (3 处)
- ConcurrencyTests.swift (1 处)

### 3. transactionProcessor 访问权限（IntegrationTests.swift）

**问题：** `transactionProcessor` 是 `private`，测试无法访问

**解决方案：**
1. 改为 `internal`（推荐）
2. 或者添加公开的测试 API

### 4. Hook 并发安全问题（HookRegistryActorTests.swift）

**问题：** 在 `@Sendable` 闭包中修改捕获的变量

**解决方案：** 使用 Actor 包装可变状态（部分测试已经这样做了）

### 5. NSMergeByPropertyObjectTrumpMergePolicy 并发安全（TestModels.swift）

**问题：** 这是一个全局可变状态

**解决方案：** 使用 `NSMergeByPropertyObjectTrumpMergePolicy` 替代

## 📝 推荐的修复顺序

1. **修复 HookCallback 类型** - 这会解决大部分测试编译错误
2. **移除墓碑属性设置** - 或者找到正确的 API
3. **暴露 transactionProcessor** - 用于测试
4. **修复 Hook 并发安全问题** - 使用 Actor 包装
5. **修复 merge policy 问题** - 使用正确的 API

## 🎯 测试覆盖范围

### 单元测试
- ✅ HookRegistryActor（4 个测试）
- ✅ TransactionProcessorActor（5 个测试）
- ✅ ManualCleanerActor（4 个测试）

### 集成测试
- ✅ 基本同步（2 个测试）
- ✅ Hook 系统（1 个测试）
- ✅ 批量操作（1 个测试）
- ✅ 多 Context（1 个测试）

### 并发测试
- ✅ 多线程安全（6 个测试）

**总计：24 个测试用例**

## 🚀 运行测试

```bash
# 运行所有 V2 测试（修复后）
swift test --filter V2Tests

# 运行特定测试套件
swift test --filter HookRegistryActorTests
swift test --filter TransactionProcessorActorTests
swift test --filter ManualCleanerActorTests
swift test --filter IntegrationTests
swift test --filter ConcurrencyTests
```

## 📚 测试架构

```
V2Tests/
├── TestModels.swift          # 测试基础设施
├── HookRegistryActorTests.swift
├── TransactionProcessorActorTests.swift
├── ManualCleanerActorTests.swift
├── IntegrationTests.swift
├── ConcurrencyTests.swift
└── README.md (本文件)
```

所有测试使用 Swift Testing 框架（`@Suite` 和 `@Test` 宏）。
