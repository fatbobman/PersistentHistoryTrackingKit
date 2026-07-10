# API Reference

This reference collects the public surface of PersistentHistoryTrackingKit 2. For lifecycle and hook execution guidance, see the [Hook Mechanism Guide](HookMechanism.md).

## Create the Kit

```swift
PersistentHistoryTrackingKit(
    container: NSPersistentContainer,
    contexts: [NSManagedObjectContext]? = nil,
    currentAuthor: String,
    allAuthors: [String],
    includingCloudKitMirroring: Bool = false,
    batchAuthors: [String] = [],
    userDefaults: UserDefaults,
    cleanStrategy: TransactionCleanStrategy = .none,
    mergeBehavior: TransactionMergeBehavior = .automatic,
    maximumDuration: TimeInterval = 60 * 60 * 24 * 7,
    uniqueString: String = "PersistentHistoryTrackingKit.lastToken.",
    logger: PersistentHistoryTrackingKitLoggerProtocol? = nil,
    logLevel: Int = 1,
    autoStart: Bool = true
)
```

| Parameter | Purpose |
|---|---|
| `container` | The Core Data container that owns the persistent store. |
| `contexts` | Contexts receiving default merges; defaults to `container.viewContext`. |
| `currentAuthor` / `allAuthors` | The local author and every author participating in history tracking. |
| `includingCloudKitMirroring` | Includes CloudKit mirroring transactions; use only when its cleanup implications are understood. |
| `batchAuthors` | Authors that write but do not merge, excluded from cleanup thresholds. |
| `userDefaults` / `uniqueString` | Storage and key prefix for persistent history checkpoints. |
| `cleanStrategy` | Automatic cleanup policy. |
| `mergeBehavior` | Whether to run the merge phase. |
| `maximumDuration` | Reserved for cleanup-readiness policies. |
| `logger` / `logLevel` | Optional logger and verbosity from 0 to 2. |
| `autoStart` | Starts processing immediately when `true`. |

## Lifecycle and Cleanup

```swift
kit.start()
kit.stop()
let cleaner = kit.cleanerBuilder()
await cleaner.clean()
```

`TransactionCleanStrategy` provides `.none`, `.byDuration(seconds:)`, and `.byNotification(times:)`. `TransactionMergeBehavior` provides `.automatic` and `.disabled`; disabled mode still observes and timestamps transactions but skips Merge Hooks and default context merges.

## Observer Hooks

```swift
let id = await kit.registerObserver(entityName: "Person", operation: .insert) { contexts in
    // Observe [HookContext].
}
let removed = await kit.removeObserver(id: id)
await kit.removeObserver(entityName: "Person", operation: .insert)
await kit.removeAllObservers()
```

`HookOperation` is `.insert`, `.update`, or `.delete`. An observer receives `[HookContext]`, grouped by transaction, entity, and operation. `HookContext` exposes the entity name, operation, object ID and URL, optional `Tombstone`, timestamp, and author.

The deprecated `registerHook(entityName:operation:callback:)` and `removeHook(entityName:operation:)` remain available for source compatibility; use the async Observer Hook APIs for new integrations.

## Merge Hooks

```swift
let id = await kit.registerMergeHook { input in
    for context in input.contexts {
        await context.perform {
            // Apply custom merge work.
        }
    }
    return .goOn
}
let removed = await kit.removeMergeHook(id: id)
await kit.removeAllMergeHooks()
```

`MergeHookInput` contains persistent-history transactions and merge contexts. Return `.goOn` to continue the pipeline or `.finish` to skip remaining hooks and the default merge. Hook callbacks are awaited in registration order, but callback bodies are not isolated to the package actors; mutable Core Data work must use `await context.perform { ... }` or caller-owned actor isolation.

## Supporting Types

- `TransactionInfo` represents a transaction timestamp, author, and its `ChangeInfo` values; `ChangeType` is `.insert`, `.update`, or `.delete`.
- `Tombstone` contains deleted-object attributes and an optional deletion date.
- `PersistentHistoryTrackingKitLoggerProtocol` accepts `PersistentHistoryTrackingKitLogType` values: `.debug`, `.info`, `.notice`, `.error`, and `.fault`.

The source declarations remain the definitive API contract.
