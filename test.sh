#!/bin/bash

# 并行运行所有测试
# 保留 Core Data 并发断言

set -e

echo "🧪 Running tests in parallel mode..."
echo "🔒 Core Data concurrency debugging enabled (-com.apple.CoreData.ConcurrencyDebug 1)"
echo ""

env "com.apple.CoreData.ConcurrencyDebug=1" swift test --parallel "$@"

echo ""
echo "✅ All tests completed!"
