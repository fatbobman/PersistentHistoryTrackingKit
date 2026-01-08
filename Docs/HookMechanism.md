# Hook Mechanism Guide

## Overview

PersistentHistoryTrackingKit V2 provides a powerful Hook system for monitoring and customizing persistent history transaction processing. The Hook system is divided into two types:

1. **Observer Hooks**: Read-only notification callbacks for monitoring data changes
2. **Merge Hooks**: Pipeline-based callbacks that can customize merge logic and modify data

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                  PersistentHistoryTrackingKit                       │
│                                                                     │
│  ┌────────────────────┐         ┌─────────────────────────────┐   │
│  │ HookRegistryActor  │         │  TransactionProcessorActor  │   │
│  │                    │         │                             │   │
│  │ • Observer Hooks   │         │  • Merge Hooks              │   │
│  │   Registration     │         │    Registration             │   │
│  │ • Observer Hooks   │         │  • Merge Hooks              │   │
│  │   Triggering       │         │    Triggering (Pipeline)    │   │
│  └────────────────────┘         │  • Transaction Processing   │   │
│           │                     │  • Default Merge Logic      │   │
│           │                     └─────────────────────────────┘   │
│           │                                  │                     │
│           │                                  │                     │
│           └──────────────┬───────────────────┘                     │
│                          │                                         │
└──────────────────────────┼─────────────────────────────────────────┘
                           │
                           ▼
                   ┌───────────────┐
                   │  Your App     │
                   │  Callbacks    │
                   └───────────────┘
```

## Transaction Processing Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Transaction Processing Pipeline                  │
└─────────────────────────────────────────────────────────────────────┘

  ┌──────────────────────┐
  │  1. Fetch            │  Fetch new transactions from authors
  │     Transactions     │  (exclude current author)
  └──────────┬───────────┘
             │
             ▼
  ┌──────────────────────┐
  │  2. Trigger          │  Notify all registered Observer Hooks
  │     Observer Hooks   │  (read-only, sequential execution)
  └──────────┬───────────┘
             │
             ▼
  ┌──────────────────────┐
  │  3. Trigger          │  Execute Merge Hook pipeline
  │     Merge Hooks      │  (serial execution in registration order)
  │     Pipeline         │
  └──────────┬───────────┘
             │
             ├─────────────────────────────────────────────────────┐
             │                                                     │
             ▼                                                     ▼
  ┌──────────────────────┐                          ┌─────────────────────┐
  │  Hook 1              │                          │  No hooks           │
  │  return .goOn        │                          │  registered         │
  └──────────┬───────────┘                          └─────────┬───────────┘
             │                                                 │
             ▼                                                 │
  ┌──────────────────────┐                                    │
  │  Hook 2              │                                    │
  │  return .finish ────────────────┐                         │
  └──────────┬───────────┘           │                        │
             │                       │                        │
             │                       │                        │
  ┌──────────▼───────────┐           │                        │
  │  Hook 3 (SKIPPED)    │           │                        │
  └──────────────────────┘           │                        │
             │                       │                        │
             └───────────────────────┼────────────────────────┘
                                     │
                                     ▼
                          ┌──────────────────────┐
                          │  4. Default Merge    │  Merge changes into contexts
                          │     (if not finished)│  (NSManagedObjectContext)
                          └──────────┬───────────┘
                                     │
                                     ▼
                          ┌──────────────────────┐
                          │  5. Update           │  Save last transaction timestamp
                          │     Timestamp        │  for current author
                          └──────────┬───────────┘
                                     │
                                     ▼
                          ┌──────────────────────┐
                          │  6. Cleanup          │  Delete old transaction history
                          │     Old History      │  based on cleanup strategy
                          └──────────────────────┘
```

## Hook Types

### 1. Observer Hooks (Read-Only Notifications)

Observer Hooks are designed for **monitoring and notification purposes only**. They should NOT modify data.

#### Characteristics:
- **Thread-Safe**: Managed by `HookRegistryActor`
- **UUID-Based Management**: Each hook returns a UUID for individual removal
- **Multiple Callbacks Supported**: You can register multiple Observer Hooks for the same entity + operation combination
- **Sequential Execution**: Multiple hooks for the same entity/operation execute sequentially in registration order
- **Read-Only**: Should not modify Core Data objects
- **Sendable Context**: Receives `[HookContext]` (grouped by transaction + entity + operation). Each element contains only Sendable types.

#### Registration:

```swift
let kit = PersistentHistoryTrackingKit(...)

// Register first Observer Hook for Person.insert
// Returns UUID for individual removal
let hookId1 = await kit.registerObserver(
    entityName: "Person",
    operation: .insert
) { contexts in
    for context in contexts {
        // context.entityName: "Person"
        // context.operation: .insert
        // context.objectIDURL: URL representation of the object
        // context.timestamp: Transaction timestamp
        // context.author: Transaction author
        // context.tombstone: Tombstone data (for .delete only)

        print("Person inserted: \(context.objectIDURL)")

        // ✅ DO: Logging, notifications, analytics
        // ❌ DON'T: Modify Core Data objects
    }
}

// Register second Observer Hook for the same entity + operation
// Both hooks will be called sequentially when a Person is inserted
let hookId2 = await kit.registerObserver(
    entityName: "Person",
    operation: .insert
) { contexts in
    for context in contexts {
        // Send analytics
        await Analytics.track(event: "person_created")
    }
}

// Register third Observer Hook for the same entity + operation
let hookId3 = await kit.registerObserver(
    entityName: "Person",
    operation: .insert
) { contexts in
    for context in contexts {
        // Send push notification
        await NotificationService.send(title: "New Person")
    }
}

// When a Person is inserted, all three callbacks will execute in registration order
// (once per entity+operation group within that transaction):
// 1. Print log (hookId1)
// 2. Track analytics (hookId2)
// 3. Send notification (hookId3)

> ℹ️ **Context batching**: A single callback receives an array of `HookContext` objects
> representing every change for the same transaction + entity + operation. If a transaction
> inserts 5 `Person` objects, your hook runs **once** with an array of 5 contexts (rather than
> 5 separate invocations).
```

#### HookContext Structure:

```swift
public struct HookContext: Sendable {
    public let entityName: String           // Entity name (e.g., "Person")
    public let operation: HookOperation     // .insert, .update, or .delete
    public let objectID: NSManagedObjectID  // Core Data object ID
    public let objectIDURL: URL             // URL representation of objectID
    public let tombstone: Tombstone?        // Tombstone data (only for .delete)
    public let timestamp: Date              // Transaction timestamp
    public let author: String               // Transaction author
}
```

#### Tombstone Structure:

Tombstone contains preserved attribute values for deleted objects (only available when `operation == .delete`).

```swift
public struct Tombstone: Sendable, Codable {
    public let attributes: [String: String]  // Preserved attributes as String dictionary
    public let deletedDate: Date?            // Deletion timestamp
}
```

**How Tombstone Works:**

1. **Only for Delete Operations**: Tombstone is `nil` for `.insert` and `.update` operations
2. **Requires `preservesValueInHistoryOnDeletion`**: Only attributes with this flag set in the Core Data model will be included
3. **All Values Converted to String**: All attribute values are automatically converted to String format for `Sendable` compliance

**Type Conversion Rules:**

| Original Type | Conversion Method | Example |
|---------------|------------------|---------|
| `String` | Preserved as-is | `"John"` → `"John"` |
| `UUID` | `.uuidString` | `UUID()` → `"123E4567-E89B-12D3-A456-426614174000"` |
| `URL` | `.absoluteString` | `URL(string: "https://example.com")` → `"https://example.com"` |
| `Date` | ISO8601 format | `Date()` → `"2025-01-07T10:30:00Z"` |
| `NSNumber` / `Int` / `Double` | `.stringValue` | `42` → `"42"`, `3.14` → `"3.14"` |
| Other types | `String(describing:)` | Fallback conversion |

**Example:**

```swift
// Core Data model with preservesValueInHistoryOnDeletion = true
person.id = UUID("123e4567-e89b-12d3-a456-426614174000")
person.name = "John Doe"
person.age = 30
person.createdAt = Date()
person.website = URL(string: "https://example.com")

// After deletion, tombstone.attributes contains:
[
    "id": "123E4567-E89B-12D3-A456-426614174000",  // UUID → uuidString
    "name": "John Doe",                            // String → preserved
    "age": "30",                                   // Int → "30"
    "createdAt": "2025-01-07T10:30:00Z",          // Date → ISO8601
    "website": "https://example.com"               // URL → absoluteString
]
```

**Recovering Original Types:**

```swift
if let tombstone = context.tombstone {
    // Recover UUID
    if let uuidString = tombstone.attributes["id"] {
        let id = UUID(uuidString: uuidString)
    }

    // Recover URL
    if let urlString = tombstone.attributes["website"] {
        let url = URL(string: urlString)
    }

    // Recover Date
    if let dateString = tombstone.attributes["createdAt"] {
        let date = ISO8601DateFormatter().date(from: dateString)
    }

    // Recover Int
    if let ageString = tombstone.attributes["age"] {
        let age = Int(ageString)
    }
}
```

#### Removal:

```swift
// Option 1: Remove a specific Observer Hook by its UUID
let removed = await kit.removeObserver(id: hookId2)
// Returns true if successfully removed, false if not found
// After this, only hookId1 and hookId3 will execute

// Option 2: Remove ALL Observer Hooks for a specific entity + operation
// This removes all callbacks registered for Person.insert
await kit.removeObserver(entityName: "Person", operation: .insert)
// After this, hookId1, hookId2, and hookId3 are all removed

// Option 3: Remove all Observer Hooks for all entities and operations
await kit.removeAllObservers()
```

**Observer Hook Removal Options**:

- **Individual removal**: `removeObserver(id: UUID)` - Removes a specific hook by its UUID, leaving other hooks for the same entity + operation intact
- **Batch removal**: `removeObserver(entityName:operation:)` - Removes **ALL** hooks for that entity + operation combination
- **Global removal**: `removeAllObservers()` - Removes all Observer Hooks across all entities and operations

### 2. Merge Hooks (Custom Merge Logic)

Merge Hooks allow **custom merge logic** and can modify data. They execute in a **pipeline pattern** with serial execution.

#### Characteristics:
- **Pipeline Pattern**: Hooks execute in registration order
- **Serial Execution**: Guaranteed sequential execution
- **Can Modify Data**: Full access to `NSPersistentHistoryTransaction` and `NSManagedObjectContext`
- **Short-Circuit Support**: Returning `.finish` stops the pipeline and skips default merge
- **Actor Isolation**: Managed inside `TransactionProcessorActor` to handle non-Sendable Core Data types

#### Registration:

```swift
let kit = PersistentHistoryTrackingKit(...)

// Register a Merge Hook - returns UUID for later reference
let hookId = await kit.registerMergeHook { input in
    // input.transactions: [NSPersistentHistoryTransaction]
    // input.contexts: [NSManagedObjectContext]

    for transaction in input.transactions {
        print("Processing transaction from: \(transaction.author ?? "unknown")")

        for change in transaction.changes ?? [] {
            // Access change details
            print("  - Changed object: \(change.changedObjectID)")
        }
    }

    // Perform custom merge logic
    for context in input.contexts {
        await context.perform {
            // Custom merge implementation
            // You can modify objects here
        }
    }

    // Return .goOn to continue to next hook
    // Return .finish to skip remaining hooks (including default merge)
    return .goOn
}

// hookId is a UUID that can be used for:
// - Removing this specific hook
// - Inserting new hooks before this one
print("Registered hook with ID: \(hookId)")
```

#### MergeHookInput Structure:

```swift
public struct MergeHookInput: @unchecked Sendable {
    public let transactions: [NSPersistentHistoryTransaction]
    public let contexts: [NSManagedObjectContext]
}
```

#### MergeHookResult:

```swift
public enum MergeHookResult: Sendable {
    case goOn      // Continue to next hook in pipeline
    case finish    // Stop pipeline, skip remaining hooks and default merge
}
```

#### Hook Ordering and Management

Merge Hooks use **UUID-based management** for precise control over the pipeline.

```swift
// 1. Append to the end (default behavior)
let hookId1 = await kit.registerMergeHook { input in
    print("Hook 1")
    return .goOn
}
// Returns: UUID (e.g., "A1B2C3D4-...")

let hookId2 = await kit.registerMergeHook { input in
    print("Hook 2")
    return .goOn
}
// Returns: UUID (e.g., "E5F6G7H8-...")

// Current pipeline: [Hook 1] → [Hook 2]

// 2. Insert before a specific hook using its UUID
let hookId3 = await kit.registerMergeHook(before: hookId2) { input in
    print("Hook 1.5")
    return .goOn
}
// Returns: UUID (e.g., "I9J0K1L2-...")

// New pipeline: [Hook 1] → [Hook 1.5] → [Hook 2]

// 3. Store UUIDs for later management
class MyHookManager {
    var validationHookId: UUID?
    var preprocessHookId: UUID?
    var mergeHookId: UUID?

    func setupHooks(kit: PersistentHistoryTrackingKit) async {
        // Register hooks and store their UUIDs
        validationHookId = await kit.registerMergeHook { input in
            // Validation logic
            return .goOn
        }

        preprocessHookId = await kit.registerMergeHook { input in
            // Preprocessing logic
            return .goOn
        }

        mergeHookId = await kit.registerMergeHook { input in
            // Merge logic
            return .goOn
        }
    }

    func updateHooks(kit: PersistentHistoryTrackingKit) async {
        // Insert a new hook before preprocessing
        if let preprocessId = preprocessHookId {
            let newHookId = await kit.registerMergeHook(before: preprocessId) { input in
                print("Extra validation")
                return .goOn
            }
            print("Inserted new hook: \(newHookId)")
        }
    }

    func cleanupHooks(kit: PersistentHistoryTrackingKit) async {
        // Remove specific hooks by UUID
        if let hookId = validationHookId {
            await kit.removeMergeHook(id: hookId)
        }
        if let hookId = preprocessHookId {
            await kit.removeMergeHook(id: hookId)
        }
    }
}
```

#### Removal:

```swift
// Remove specific Merge Hook by UUID
let hookId = await kit.registerMergeHook { input in
    // Hook logic
    return .goOn
}

// Later, remove this specific hook
let wasRemoved = await kit.removeMergeHook(id: hookId)
if wasRemoved {
    print("Hook removed successfully")
} else {
    print("Hook not found (already removed?)")
}

// Remove all Merge Hooks at once
await kit.removeAllMergeHooks()
```

**Key Points**:

- Every `registerMergeHook` call returns a unique UUID
- UUIDs can be used to remove specific hooks via `removeMergeHook(id:)`
- UUIDs can be used to insert new hooks before existing ones via `registerMergeHook(before:callback:)`
- Unlike Observer Hooks (which are identified by entity name + operation), Merge Hooks use UUIDs for finer control
- Store UUIDs if you need to dynamically manage the pipeline at runtime

## Usage Examples

### Example 1: Monitoring All Person Insertions

```swift
// Register Observer Hook for monitoring
let observerHookId = await kit.registerObserver(
    entityName: "Person",
    operation: .insert
) { contexts in
    for context in contexts {
        // Send analytics event
        Analytics.track(event: "person_created", properties: [
            "timestamp": context.timestamp,
            "author": context.author
        ])

        // Send push notification
        await NotificationService.send(
            title: "New Person Created",
            body: "A new person was added to the database"
        )
    }
}
```

### Example 2: Logging All Delete Operations

```swift
// Monitor all entity deletions
var deleteHookIds: [UUID] = []
for entityName in ["Person", "Item", "Order"] {
    let hookId = await kit.registerObserver(
        entityName: entityName,
        operation: .delete
    ) { contexts in
        for context in contexts {
            // Access tombstone data for deleted objects
            if let tombstone = context.tombstone {
                print("Deleted \(context.entityName): \(tombstone.attributes)")
                print("Deleted at: \(tombstone.deletedDate ?? Date())")
            }

            // Log to external service
            await Logger.log(
                level: .info,
                message: "Entity deleted",
                metadata: [
                    "entity": context.entityName,
                    "objectID": context.objectIDURL.absoluteString,
                    "author": context.author
                ]
            )
        }
    }
    deleteHookIds.append(hookId)
}

// Later, you can remove specific hooks if needed
// await kit.removeObserver(id: deleteHookIds[0])
```

### Example 3: Custom Conflict Resolution with Merge Hooks

```swift
// Implement custom conflict resolution
await kit.registerMergeHook { input in
    for context in input.contexts {
        await context.perform {
            // Set merge policy for this context
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

            // Process each transaction
            for transaction in input.transactions {
                if let changes = transaction.changes {
                    for change in changes {
                        // Custom conflict resolution logic
                        if change.changeType == .update {
                            // Handle update conflicts
                            if let object = try? context.existingObject(with: change.changedObjectID) {
                                // Your custom logic here
                                print("Resolving conflict for: \(object)")
                            }
                        }
                    }
                }
            }
        }
    }

    return .goOn  // Continue to default merge
}
```

### Example 4: Implementing Custom Merge Logic

```swift
// Replace default merge with custom implementation
await kit.registerMergeHook { input in
    for context in input.contexts {
        await context.perform {
            for transaction in input.transactions {
                // Build a notification describing objectID changes
                let notification = transaction.objectIDNotification()

                // Apply your custom merge rules here
                context.mergeChanges(fromContextDidSave: notification)

                // ... additional custom logic ...
            }

            // Save changes
            try? context.save()
        }
    }

    return .finish  // Skip default merge (we handled it ourselves)
}
```

### Example 5: Pipeline Pattern - Multi-Stage Processing

```swift
// Stage 1: Validation
let validationHookId = await kit.registerMergeHook { input in
    for transaction in input.transactions {
        // Validate transaction data
        guard let author = transaction.author else {
            print("Invalid transaction: missing author")
            return .finish  // Abort pipeline
        }

        if author == "BANNED_USER" {
            print("Rejected transaction from banned user")
            return .finish
        }
    }
    return .goOn
}

// Stage 2: Preprocessing
let preprocessHookId = await kit.registerMergeHook { input in
    for context in input.contexts {
        await context.perform {
            // Preprocess data before merge
            // e.g., normalize values, set defaults
        }
    }
    return .goOn
}

// Stage 3: Custom merge
let mergeHookId = await kit.registerMergeHook { input in
    // Implement custom merge logic
    for context in input.contexts {
        await context.perform {
            // Your merge implementation
        }
    }
    return .goOn  // Or .finish to skip default merge
}

// Stage 4: Post-processing
let postprocessHookId = await kit.registerMergeHook { input in
    for context in input.contexts {
        await context.perform {
            // Post-merge processing
            // e.g., update computed properties, trigger side effects
        }
    }
    return .goOn
}
```

## Hook Execution Flow Comparison

### Observer Hooks Flow

```
Transaction Detected
       │
       ▼
┌──────────────────┐
│ HookRegistryActor│
│                  │
│  ┌─────────┐    │     ┌─────────────┐
│  │ Hook 1  │────┼────▶│  Callback 1 │
│  └─────────┘    │     └─────────────┘
│                  │
│  ┌─────────┐    │     ┌─────────────┐
│  │ Hook 2  │────┼────▶│  Callback 2 │
│  └─────────┘    │     └─────────────┘
│                  │
│  ┌─────────┐    │     ┌─────────────┐
│  │ Hook 3  │────┼────▶│  Callback 3 │
│  └─────────┘    │     └─────────────┘
└──────────────────┘
```

### Merge Hooks Pipeline Flow

```
Transaction Detected
       │
       ▼
┌──────────────────────────┐
│ TransactionProcessorActor│
│                          │
│  ┌─────────┐            │     ┌─────────────┐
│  │ Hook 1  │────────────┼────▶│  Callback 1 │─── .goOn
│  └─────────┘            │     └─────────────┘      │
│       ▲                 │                          │
│       │ Serial          │     ┌─────────────┐      │
│       └─────────────────┼─────│  Callback 2 │◀─────┘
│  ┌─────────┐            │     └─────────────┘
│  │ Hook 2  │            │            │
│  └─────────┘            │            ├─── .goOn
│                         │            │        │
│  ┌─────────┐            │            │        ▼
│  │ Hook 3  │            │            │   ┌─────────────┐
│  └─────────┘            │            │   │  Callback 3 │
│                         │            │   └─────────────┘
│                         │            │          │
│                         │            │          ├─── .goOn
│                         │            │          │
│                         │            │          ▼
│                         │            │   ┌──────────────┐
│                         │            │   │Default Merge │
│                         │            │   └──────────────┘
│                         │            │
│                         │            └─── .finish (skip remaining)
└──────────────────────────┘
```

## Best Practices

### ✅ DO

1. **Use Observer Hooks for Read-Only Operations**
   - Logging
   - Analytics
   - Notifications
   - Monitoring

2. **Use Merge Hooks for Custom Merge Logic**
   - Conflict resolution
   - Data transformation
   - Custom merge policies
   - Validation before merge

3. **Always Await Async Operations in Merge Hooks**
   ```swift
   await kit.registerMergeHook { input in
       for context in input.contexts {
           await context.perform {  // ✅ Has await
               // Operations...
           }
       }
       return .goOn
   }
   ```

4. **Use Pipeline Pattern for Multi-Stage Processing**
   - Validation → Preprocessing → Merge → Post-processing

5. **Return `.finish` to Skip Default Merge**
   - When you implement complete custom merge logic
   - When you want to reject/abort a transaction

6. **Store Hook IDs for Later Removal**
   ```swift
   let hookId = await kit.registerMergeHook { ... }
   // Later...
   await kit.removeMergeHook(id: hookId)
   ```

### ❌ DON'T

1. **DON'T Modify Data in Observer Hooks**
   ```swift
   // ❌ Wrong
   await kit.registerObserver(entityName: "Person", operation: .insert) { contexts in
       for context in contexts {
           // This won't work - context only has URL, not the object
           // Use Merge Hooks instead
       }
   }
   ```

2. **DON'T Forget to Await in Merge Hooks**
   ```swift
   // ❌ Wrong - breaks pipeline seriality
   await kit.registerMergeHook { input in
       context.perform {  // Missing await
           // Operations...
       }
       return .goOn  // Returns before perform completes!
   }
   ```

3. **DON'T Launch Independent Tasks in Merge Hooks**
   ```swift
   // ❌ Wrong
   await kit.registerMergeHook { input in
       Task {  // Launches independent task
           await someOperation()
       }
       return .goOn  // Returns immediately, doesn't wait
   }
   ```

4. **DON'T Register Too Many Hooks**
   - Each hook adds processing overhead
   - Merge hooks execute serially
   - Consider combining related logic into a single hook

5. **DON'T Perform Long-Running Operations in Hooks**
   - Hooks block transaction processing
   - Move heavy operations to background tasks
   - Use Observer Hooks to trigger async work

## Common Patterns

### Pattern 1: Audit Trail

```swift
// Track all changes for audit purposes
var auditHookIds: [UUID] = []
for operation in [HookOperation.insert, .update, .delete] {
    let hookId = await kit.registerObserver(
        entityName: "SensitiveData",
        operation: operation
    ) { contexts in
        for context in contexts {
            await AuditLog.record(
                entityName: context.entityName,
                operation: context.operation.rawValue,
                objectID: context.objectIDURL.absoluteString,
                timestamp: context.timestamp,
                author: context.author,
                tombstone: context.tombstone
            )
        }
    }
    auditHookIds.append(hookId)
}
```

### Pattern 2: Cache Invalidation

```swift
// Invalidate cache when data changes
let cacheHookId = await kit.registerObserver(entityName: "Product", operation: .update) { contexts in
    for context in contexts {
        await CacheManager.invalidate(key: "product_\(context.objectIDURL.absoluteString)")
    }
}
```

### Pattern 3: Cross-Context Synchronization

```swift
// Sync changes to a read-only UI context
await kit.registerMergeHook { input in
    for context in input.contexts {
        await context.perform {
            // Refresh all objects to get latest state
            context.refreshAllObjects()
        }
    }
    return .goOn
}
```

### Pattern 4: Conditional Merge

```swift
// Only merge specific transaction types
await kit.registerMergeHook { input in
    let validTransactions = input.transactions.filter { transaction in
        // Filter logic
        transaction.author != "SYSTEM"
    }

    if validTransactions.isEmpty {
        return .finish  // Skip merge
    }

    // Process valid transactions only
    // ...

    return .goOn
}
```

### Pattern 5: Notification Throttling

```swift
// Throttle notifications to avoid spam
actor NotificationThrottle {
    private var lastNotificationTime: Date = .distantPast
    private let minimumInterval: TimeInterval = 60 // 1 minute

    func shouldNotify() -> Bool {
        let now = Date()
        if now.timeIntervalSince(lastNotificationTime) >= minimumInterval {
            lastNotificationTime = now
            return true
        }
        return false
    }
}

let throttle = NotificationThrottle()

let throttleHookId = await kit.registerObserver(entityName: "Message", operation: .insert) { contexts in
    if await throttle.shouldNotify() {
        await NotificationService.send(title: "New Messages", body: "You have new messages (\(contexts.count))")
    }
}
```

## Thread Safety

### Observer Hooks
- Managed by `HookRegistryActor` - fully thread-safe
- `HookContext` is `Sendable` - safe to pass across actors
- Callbacks marked `@Sendable` - must be thread-safe

### Merge Hooks
- Managed by `TransactionProcessorActor` - fully thread-safe
- Callbacks execute serially within the actor
- Direct access to non-Sendable Core Data types
- `MergeHookInput` uses `@unchecked Sendable` - safe only within the actor

## Performance Considerations

1. **Observer Hook Overhead**
   - Minimal overhead per hook
   - Runs sequentially in registration order
   - Completes before merge processing begins

2. **Merge Hook Overhead**
   - Executes serially before default merge
   - Each hook blocks the next
   - Consider combining hooks to reduce overhead

3. **Hook Count**
   - More hooks = more processing time
   - Typical: 1-5 hooks per entity/operation
   - Recommended max: 10 hooks per entity/operation

4. **Async Operations**
   - Always await async operations in Merge Hooks
   - Use `Task.detached` for fire-and-forget work in Observer Hooks
   - Move heavy processing to background queues

## Real-World Examples

### Example from Community: Disabling Undo Manager During Merge

**Problem**: When merging transactions into contexts with `undoManager` enabled, the default merge can cause crashes or unwanted undo registrations.

**Solution**: Use a Merge Hook to temporarily disable undo manager during merge.

```swift
// Based on: https://github.com/fatbobman/PersistentHistoryTrackingKit/pull/8

await kit.registerMergeHook { input in
    for transaction in input.transactions {
        let notification = transaction.objectIDNotification()

        for context in input.contexts {
            await context.perform {
                // Save current undo manager
                let undoManager = context.undoManager

                // Temporarily disable undo manager
                context.undoManager = nil

                // Merge changes
                context.mergeChanges(fromContextDidSave: notification)

                // Restore undo manager
                context.undoManager = undoManager
            }
        }
    }

    // Return .finish to skip default merge (we handled it ourselves)
    return .finish
}
```

**When to use this pattern**:

- You have contexts with `undoManager` enabled
- You want to prevent merge operations from being recorded in undo history
- You need fine-grained control over undo behavior

### Example from Community: Deduplication During Merge

**Problem**: When syncing via CloudKit or across multiple devices, duplicate records can be created. You need to identify and remove duplicates during the merge process.

**Solution**: Use a Merge Hook to deduplicate records before merging.

```swift
// Based on: https://github.com/fatbobman/PersistentHistoryTrackingKit/pull/3
// Reference: https://developer.apple.com/documentation/coredata/sharing_core_data_objects_between_icloud_users

await kit.registerMergeHook { input in
    for context in input.contexts {
        await context.perform {
            // Process each transaction for deduplication
            for transaction in input.transactions {
                guard let changes = transaction.changes else { continue }

                for change in changes {
                    // Only process inserts (where duplicates typically occur)
                    guard change.changeType == .insert else { continue }

                    // Get the inserted object
                    guard let insertedObject = try? context.existingObject(with: change.changedObjectID) else {
                        continue
                    }

                    // Deduplication logic based on your unique identifiers
                    // Example: Find duplicates by a unique property (e.g., "uniqueID")
                    if let uniqueID = insertedObject.value(forKey: "uniqueID") as? String {
                        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: change.changedObjectID.entity.name!)
                        fetchRequest.predicate = NSPredicate(format: "uniqueID == %@", uniqueID)

                        let existingObjects = try? context.fetch(fetchRequest)

                        // If we found duplicates (more than 1 object with same uniqueID)
                        if let objects = existingObjects, objects.count > 1 {
                            // Choose which object to keep (e.g., oldest, newest, or merge data)
                            let sortedObjects = objects.sorted { obj1, obj2 in
                                let date1 = obj1.value(forKey: "createdAt") as? Date ?? .distantPast
                                let date2 = obj2.value(forKey: "createdAt") as? Date ?? .distantPast
                                return date1 < date2
                            }

                            // Keep the first (oldest), delete the rest
                            let objectsToDelete = sortedObjects.dropFirst()
                            for duplicate in objectsToDelete {
                                context.delete(duplicate)
                            }
                        }
                    }
                }
            }

            // Save the context after deduplication
            try? context.save()
        }
    }

    // Continue to default merge (or return .finish if you handled merge completely)
    return .goOn
}
```

**When to use this pattern**:

- Syncing with CloudKit or other cloud services
- Multi-device environments where duplicate creation is possible
- You have unique identifiers that can detect duplicates
- You need to implement custom merge/deduplication logic

#### Advanced: Flexible Deduplication Strategy

You can make the deduplication logic reusable and configurable:

```swift
// Define a deduplication strategy protocol
protocol DeduplicationStrategy {
    func deduplicate(insertedObject: NSManagedObject, in context: NSManagedObjectContext) async throws
}

// Example: Deduplicate by unique ID
class UniqueIDDeduplicationStrategy: DeduplicationStrategy {
    let uniqueKeyPath: String
    let keepStrategy: KeepStrategy

    enum KeepStrategy {
        case oldest
        case newest
        case mergeIntoOldest
    }

    init(uniqueKeyPath: String, keepStrategy: KeepStrategy = .oldest) {
        self.uniqueKeyPath = uniqueKeyPath
        self.keepStrategy = keepStrategy
    }

    func deduplicate(insertedObject: NSManagedObject, in context: NSManagedObjectContext) async throws {
        guard let uniqueValue = insertedObject.value(forKey: uniqueKeyPath) as? String else {
            return
        }

        let entityName = insertedObject.entity.name!
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: entityName)
        fetchRequest.predicate = NSPredicate(format: "%K == %@", uniqueKeyPath, uniqueValue)

        let existingObjects = try context.fetch(fetchRequest)

        guard existingObjects.count > 1 else { return }

        switch keepStrategy {
        case .oldest:
            let sortedObjects = existingObjects.sorted {
                let date1 = $0.value(forKey: "createdAt") as? Date ?? .distantPast
                let date2 = $1.value(forKey: "createdAt") as? Date ?? .distantPast
                return date1 < date2
            }
            sortedObjects.dropFirst().forEach { context.delete($0) }

        case .newest:
            let sortedObjects = existingObjects.sorted {
                let date1 = $0.value(forKey: "createdAt") as? Date ?? .distantPast
                let date2 = $1.value(forKey: "createdAt") as? Date ?? .distantPast
                return date1 > date2
            }
            sortedObjects.dropFirst().forEach { context.delete($0) }

        case .mergeIntoOldest:
            let sortedObjects = existingObjects.sorted {
                let date1 = $0.value(forKey: "createdAt") as? Date ?? .distantPast
                let date2 = $1.value(forKey: "createdAt") as? Date ?? .distantPast
                return date1 < date2
            }
            let keeper = sortedObjects.first!
            let duplicates = sortedObjects.dropFirst()

            // Merge attributes from duplicates into keeper
            for duplicate in duplicates {
                for (key, _) in duplicate.entity.attributesByName {
                    if let value = duplicate.value(forKey: key), keeper.value(forKey: key) == nil {
                        keeper.setValue(value, forKey: key)
                    }
                }
                context.delete(duplicate)
            }
        }
    }
}

// Usage in Merge Hook
let deduplicationStrategy = UniqueIDDeduplicationStrategy(
    uniqueKeyPath: "uniqueID",
    keepStrategy: .mergeIntoOldest
)

await kit.registerMergeHook { input in
    for context in input.contexts {
        await context.perform {
            for transaction in input.transactions {
                guard let changes = transaction.changes else { continue }

                for change in changes {
                    guard change.changeType == .insert else { continue }
                    guard let insertedObject = try? context.existingObject(with: change.changedObjectID) else {
                        continue
                    }

                    // Apply deduplication strategy
                    try? await deduplicationStrategy.deduplicate(
                        insertedObject: insertedObject,
                        in: context
                    )
                }
            }

            try? context.save()
        }
    }

    return .goOn
}
```

## Testing Hooks

### Testing Observer Hooks

```swift
@Test("Observer hook receives correct context")
func testObserverHook() async throws {
    let kit = PersistentHistoryTrackingKit(...)

    actor CallbackTracker {
        var receivedContexts: [HookContext] = []
        func record(_ contexts: [HookContext]) {
            receivedContexts = contexts
        }
        func get() -> [HookContext] { receivedContexts }
    }

    let tracker = CallbackTracker()

    let hookId = await kit.registerObserver(entityName: "Person", operation: .insert) { contexts in
        await tracker.record(contexts)
    }

    // Perform insert operation
    // ...

    let contexts = await tracker.get()
    #expect(contexts.count > 0)
    #expect(contexts.first?.entityName == "Person")
    #expect(contexts.first?.operation == .insert)
}
```

### Testing Merge Hooks

```swift
@Test("Merge hook pipeline executes in order")
func testMergeHookOrder() async throws {
    let kit = PersistentHistoryTrackingKit(...)

    actor OrderTracker {
        var order: [Int] = []
        func append(_ value: Int) { order.append(value) }
        func get() -> [Int] { order }
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

    // Trigger transaction
    // ...

    let executionOrder = await tracker.get()
    #expect(executionOrder == [1, 2])
}
```

## Migration from V1

If you're migrating from PersistentHistoryTrackingKit V1:

### V1 Hooks
```swift
// V1: Single callback for all operations
kit.registerHook { transaction, contexts in
    // Handle transaction
}
```

### V2 Hooks
```swift
// V2: Separate Observer and Merge Hooks

// For monitoring (replaces V1 read-only hooks)
let observerId = await kit.registerObserver(entityName: "Person", operation: .insert) { contexts in
    // Monitor only (array may contain multiple contexts)
    for context in contexts {
        // ...
    }
}

// For custom merge (replaces V1 merge hooks)
let mergeId = await kit.registerMergeHook { input in
    // Custom merge logic
    return .goOn
}
```

## Summary

| Feature | Observer Hooks | Merge Hooks |
|---------|---------------|-------------|
| Purpose | Monitoring, notifications | Custom merge logic |
| Data Modification | ❌ No | ✅ Yes |
| Execution | Parallel (may be) | Serial (guaranteed) |
| Context Type | `HookContext` (Sendable) | `MergeHookInput` (with Core Data types) |
| Callback Type | `@Sendable (HookContext) async -> Void` | `@Sendable (MergeHookInput) async throws -> MergeHookResult` |
| Registration | `registerObserver(...) async -> UUID` | `registerMergeHook(...) async -> UUID` |
| Individual Removal | `removeObserver(id: UUID) async -> Bool` | `removeMergeHook(id: UUID) async -> Bool` |
| Batch Removal | `removeObserver(entityName:operation:) async` | `removeAllMergeHooks() async` |
| Actor | `HookRegistryActor` | `TransactionProcessorActor` |
| Pipeline Support | ❌ No | ✅ Yes (.goOn/.finish) |
| Use Cases | Logging, analytics, notifications | Conflict resolution, custom merge, validation |

## References

- [HookTypes.swift](../Sources/PersistentHistoryTrackingKit/HookTypes.swift) - Type definitions
- [HookRegistryActor.swift](../Sources/PersistentHistoryTrackingKit/HookRegistryActor.swift) - Observer Hook management
- [TransactionProcessorActor.swift](../Sources/PersistentHistoryTrackingKit/TransactionProcessorActor.swift) - Merge Hook management
- [MergeHookTests.swift](../Tests/PersistentHistoryTrackingKitTests/MergeHookTests.swift) - Test examples
- [HookRegistryActorTests.swift](../Tests/PersistentHistoryTrackingKitTests/HookRegistryActorTests.swift) - Test examples
