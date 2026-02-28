# PersistentHistoryTrackingKit Agent Notes

## Repository Overview

- This is a Swift Package for Core Data persistent history tracking.
- The main target is `PersistentHistoryTrackingKit`.
- Tests use Swift Testing and heavily exercise Core Data, SQLite-backed stores, background contexts, and persistent history.

## Working Expectations

- Prefer small, targeted changes.
- Keep Swift 6 concurrency rules in mind.
- Avoid changing test timing or adding arbitrary sleeps unless there is a reproducible failure that requires it.
- Do not assume flaky behavior is code-related until build cache, Xcode test settings, and toolchain state are ruled out.

## Test Guidance

- Command-line full test runs should use serial execution:
  - `swift test --no-parallel`
  - or `./test.sh`
- `./test.sh` is the preferred full-suite command because it enables Core Data concurrency assertions via `com.apple.CoreData.ConcurrencyDebug=1`.
- In Xcode, disable parallel testing for this package before running the full suite.
- When debugging failures, prefer running a single test file or a filtered suite first.
- This repository's tests are currently treated as serial-only at the full-suite level.
- For new Core Data tests, do not write directly through `viewContext` or a raw background context from the test body.
- Prefer `Tests/PersistentHistoryTrackingKitTests/TestAppDataHandler.swift` and actor-isolated helper methods for creating, updating, deleting, and reading test data.
- If a test needs direct inspection of a handler-owned context, use the handler's `withContext` API rather than `context.perform` from the test body.

## Known Test Constraints

- Full-suite parallel execution in Xcode can hang before any individual test completes.
- Serial full-suite execution has been verified to pass repeatedly.
- Repeated Xcode runs of `cleanTransactionsByTimestampAndAuthors` have been observed to pass.
- Repeated Xcode serial full-suite runs have also been observed to pass.

## Failure Triage

If a crash or hang appears again, collect the following before changing code:

- The exact test name or suite name
- Whether the run was serial or parallel
- Whether the run happened in Xcode or from the command line
- The crash stack, exception type, or final console output
- Whether `.build` or Xcode DerivedData had just been reused after a toolchain/Xcode change

## Build and Cache Notes

- If SwiftPM reports compiler/module version mismatches, clear `.build` and rerun.
- If Xcode behaves inconsistently while command-line serial runs are stable, suspect DerivedData or Xcode test execution settings before changing repository code.

## Version Tag Rule

- Git tags for releases should use the format `x.x.x`.
- Examples:
  - `1.0.0`
  - `2.1.3`

## Files Worth Checking First

- `Sources/PersistentHistoryTrackingKit/PersistentHistoryTrackingKit.swift`
- `Sources/PersistentHistoryTrackingKit/TransactionProcessorActor.swift`
- `Sources/PersistentHistoryTrackingKit/TransactionTimestampManager.swift`
- `Tests/PersistentHistoryTrackingKitTests/TestModels.swift`
- `test.sh`
