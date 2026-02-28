# Migration Guide: V1 to V2

This guide is for projects moving from PersistentHistoryTrackingKit V1 to V2.

V2 is not a compatibility release. It is a full rewrite with a new concurrency model,
new extension points, and different cleanup semantics.

## Should You Migrate?

Move to V2 if all of the following are true:

- You target iOS 13+, macOS 10.15+, macCatalyst 13+, tvOS 13+, watchOS 6+, or visionOS 1+
- You are ready to adopt Swift 6
- You want actor-based internals and async hook APIs
- You want Observer Hooks, Merge Hooks, and tombstone support

V2 now declares lower deployment targets than the initial V2 release, but current runtime
validation has only been performed on iOS 15+ with modern Xcode toolchains.

Stay on V1 if any of the following are true:

- You want to stay on a pre-Swift-6 toolchain
- You are not ready to move to Swift 6
- You prefer the existing V1 fetch / merge / cleaner customization model

## High-Level Differences

### V1

- Based on a fetcher / merger / cleaner pipeline
- Uses protocol-based customization such as `TransactionMergerProtocol`
- Includes a deduplicator extension point
- Uses task management around notification handling
- Exposes a callable manual cleaner

### V2

- Rewritten around actors
- Uses `HookRegistryActor` and `TransactionProcessorActor`
- Uses async Observer Hooks and Merge Hooks instead of protocol injection
- Adds grouped observer callbacks and tombstone support
- Uses `ManualCleanerActor` for manual cleanup

## Requirements Changes

### V1

- Swift 5-era API design
- Earlier platform support depending on the release you are using

### V2

- Swift 6
- iOS 13+
- macOS 10.15+
- macCatalyst 13+
- tvOS 13+
- watchOS 6+
- visionOS 1+

These are the declared deployment targets. In the current toolchain environment, runtime
validation has only been performed on iOS 15+.

## Package and Dependency Changes

### V1

- Depends on `swift-async-algorithms`

### V2

- Depends on `CoreDataEvolution`
- Uses actor-based Core Data helpers via `@NSModelActor`

## API Mapping

| V1 concept | V2 equivalent |
|---|---|
| Protocol-based merger | `registerMergeHook` |
| Protocol-based deduplicator | `registerMergeHook` |
| Read-only side effects in merge flow | `registerObserver` |
| Callable manual cleaner | `cleanerBuilder()` returning `ManualCleanerActor` |
| Notification-driven task handling | Internal actor-driven processing |
| `performAndWaitWithResult` helper | Usually no longer needed in normal V2 usage |

## Initialization Changes

### Typical V1 shape

V1 configuration was centered around fetch / merge / clean components and a more classical
threading model.

### Typical V2 shape

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

## Custom Merge Logic

### V1

If you customized merge behavior, you likely conformed to `TransactionMergerProtocol`.

### V2

Register a Merge Hook:

```swift
let hookID = await kit.registerMergeHook { input in
    for context in input.contexts {
        await context.perform {
            // Custom merge logic
        }
    }
    return .goOn
}
```

Use `.finish` when your hook has fully handled merging and the default merge should be skipped.

## Deduplication Logic

### V1

V1 exposed a dedicated deduplicator protocol.

### V2

There is no separate deduplicator protocol. Put deduplication inside a Merge Hook:

```swift
await kit.registerMergeHook { input in
    for context in input.contexts {
        await context.perform {
            // Deduplication logic here
        }
    }
    return .goOn
}
```

## Read-Only Observability

### V1

V1 did not have the V2 observer hook model.

### V2

Use Observer Hooks for logging, analytics, cache invalidation, and notifications:

```swift
let id = await kit.registerObserver(entityName: "Person", operation: .insert) { contexts in
    for context in contexts {
        print(context.objectIDURL)
    }
}
```

Observer callbacks are grouped by transaction, entity name, and operation.

## Delete Handling and Tombstones

V2 adds tombstone support for delete operations. This is a real feature upgrade from V1.

If your model marks attributes with `preservesValueInHistoryOnDeletion`, delete observer hooks can
inspect those values through `HookContext.tombstone`.

## Cleanup Semantics

This is one of the most important behavior changes.

### V1

- `maximumDuration` was part of the cleanup readiness calculation
- Old transactions could be force-cleaned after the configured duration even when some authors had
  not merged yet

### V2

- Automatic cleanup is conservative
- Cleanup runs only when the active `cleanStrategy` allows it
- Cleanup runs only after every non-batch author has recorded its merge timestamp
- If any required author is missing a timestamp, automatic cleanup is skipped

This makes V2 safer for multi-author setups, especially App Group and extension scenarios.

### What about `maximumDuration`?

In the current V2 implementation, `maximumDuration` is reserved for future cleanup readiness
policies. It is no longer used as an implicit force-delete fallback.

If you relied on V1's force-cleanup behavior, you should now choose one of these paths:

- Use manual cleanup deliberately
- Revisit which authors belong in `allAuthors`
- Mark write-only participants in `batchAuthors`

## CloudKit Guidance

The V1 guidance around CloudKit remains directionally valid, but V2 keeps the separation clearer:

- Do not aggressively clean persistent history when CloudKit relies on it
- Do not enable `includingCloudKitMirroring` unless you explicitly understand that workflow
- Prefer a long duration-based cleanup policy when CloudKit is involved

## Manual Cleanup Migration

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

## Logging

`logLevel` still exists, but V2 logging is simpler and fixed at initialization time.

If you used a custom logger in V1, the migration is usually straightforward:

```swift
struct MyLogger: PersistentHistoryTrackingKitLoggerProtocol {
    func log(type: PersistentHistoryTrackingKitLogType, message: String) {
        Logger.log(type, message)
    }
}
```

## Migration Checklist

1. Confirm your deployment targets and Swift version meet V2 requirements, and note that current runtime validation has only been performed on iOS 15+.
2. Replace any V1 merger or deduplicator customization with Merge Hooks.
3. Add Observer Hooks where you need read-only monitoring.
4. Re-evaluate `allAuthors` and `batchAuthors`.
5. Revisit cleanup expectations if you previously depended on forced cleanup.
6. Use shared `UserDefaults` for App Group setups.
7. Run tests with the current parallel test baseline and keep Core Data concurrency assertions enabled.

## Testing Notes

This repository's full test suite now runs in parallel.

- Command line: `swift test --parallel`
- Or use: `./test.sh`
- In Xcode: parallel execution is supported after the test infrastructure fixes
- `TestModelBuilder.createContainer` is intentionally serialized because concurrent
  `NSPersistentContainer` initialization can crash inside Core Data during store loading

## Related Docs

- [Hook Mechanism Guide](HookMechanism.md)
- [README](../README.md)
- [Chinese Migration Guide](MigrationGuideCN.md)
