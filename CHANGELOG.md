# Changelog

All notable changes to PersistentHistoryTrackingKit will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2025-06-27

### 🚀 Major Swift 6 Compatibility Update

#### Added
- ✅ **Full Swift 6 Compatibility**: Complete support for Swift 6's strict concurrency checking
- ✅ **True Sendable Compliance**: Properly implemented thread safety (not just `@unchecked Sendable`)
- ✅ **Memory Safety**: Eliminated all retain cycles and memory leaks
- ✅ **Swift Testing Framework**: Migrated from XCTest to modern Swift Testing
- ✅ **Comprehensive Concurrency Tests**: 31 tests covering all concurrency scenarios
- ✅ **Concurrency Debug Script**: Added `run_tests_with_concurrency_checks.sh` for validation
- ✅ **Package@swift-6.swift**: Dedicated Swift 6 package manifest

#### Changed
- 🔒 **Thread-Safe Task Management**: Replaced unsafe task handling with proper synchronization
- 🔧 **Sendable Property Access**: Changed `public var logLevel` to `public private(set) var logLevel`
- 🧹 **Batch Operation Fixes**: Fixed infinite loop issues in batch insertion tests
- 📚 **Enhanced Documentation**: Comprehensive README updates with Swift 6 migration guide

#### Fixed
- 🐛 **Retain Cycle Elimination**: Fixed memory leaks in `createTransactionProcessingTask()`
- 🧵 **Concurrency Race Conditions**: Eliminated data races through proper synchronization
- 🔄 **Batch Insert Logic**: Fixed batch operations to properly terminate instead of infinite loops
- 🧪 **Test Framework Migration**: Converted all tests to Swift Testing with proper serialization

#### Technical Details
- **Weak References**: Added `[weak self]` capture lists to prevent retain cycles
- **Synchronization**: Implemented `DispatchQueue` with barrier flags for thread safety
- **Task Management**: Used `sync(flags: .barrier)` for atomic task operations
- **Core Data Debugging**: Enhanced test infrastructure with concurrency debugging options

### 🔧 Migration Guide

#### For Existing Users
- **No Breaking Changes**: Public API remains identical
- **Enhanced Safety**: Existing code automatically benefits from improved thread safety
- **Swift 6 Ready**: Enable strict concurrency checking without code changes

#### For New Projects
```swift
// Same API, enhanced safety
let kit = PersistentHistoryTrackingKit(
    container: container,
    currentAuthor: "MainApp",
    allAuthors: ["MainApp", "Extension"],
    userDefaults: userDefaults
)
// Now with true Sendable compliance!
```

### 🧪 Testing Improvements

#### New Test Infrastructure
- **31 Total Tests**: Complete coverage of all functionality
- **Concurrency Validation**: Tests run with strict concurrency debugging enabled
- **Memory Leak Detection**: Automated detection of retain cycles
- **Multi-App Scenarios**: Comprehensive testing of app group synchronization
- **Stress Testing**: Concurrent operations under load

#### Test Categories
- Clean Strategy Tests (3 tests)
- Timestamp Manager Tests (6 tests)
- Logger Tests (1 test)
- Merger Tests (2 tests)
- Fetcher Tests (2 tests)
- Cleaner Tests (2 tests)
- Integration Tests (4 tests)
- Quick Integration Tests (4 tests)
- Comprehensive Integration Tests (6 tests)

### 📊 Performance Improvements

- **Zero Retain Cycles**: Eliminated all memory leaks
- **Optimal Synchronization**: Minimal performance impact from thread safety
- **Efficient Cleanup**: Improved transaction cleanup algorithms
- **Reduced Overhead**: Streamlined internal operations

### 🔍 Quality Assurance

- **Concurrency Debugging**: All tests pass with Core Data concurrency debugging enabled
- **Swift 6 Validation**: Full compliance with Swift 6's strict concurrency model
- **Memory Profiling**: Verified zero memory leaks and proper cleanup
- **Multi-Platform Testing**: Validated across iOS, macOS, tvOS, and watchOS

---

## [1.x.x] - Previous Versions

Previous versions maintained compatibility with Swift 5.5+ but lacked the comprehensive concurrency safety and Swift 6 compatibility introduced in v2.0.0.

---

**Note**: Version 2.0.0 represents a significant quality and safety improvement while maintaining full API compatibility. All existing users are encouraged to upgrade to benefit from enhanced thread safety and Swift 6 compatibility.