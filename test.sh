#!/bin/bash

# 串行运行所有测试
# 使用 --no-parallel 强制禁用并行

set -e

echo "🧪 Running tests in serial mode..."
echo "🔒 Core Data concurrency debugging enabled (-com.apple.CoreData.ConcurrencyDebug 1)"
echo ""

env "com.apple.CoreData.ConcurrencyDebug=1" swift test --no-parallel "$@"

echo ""
echo "✅ All tests completed!"
