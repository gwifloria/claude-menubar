#!/bin/bash

# Claude-Swift 状态查看脚本
# 统一的状态查看接口

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$HOME/.claude-swift/status-config.json"

echo "📊 Claude-Swift 状态概览"
echo "==============================="

# 检查配置文件是否存在
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "❌ 未找到配置文件"
    echo "   请先启动监控: ./bin/start.sh"
    exit 1
fi

# 使用 updater.sh 的功能显示状态
"$SCRIPT_DIR/lib/updater.sh" list

echo ""
echo "🔧 管理命令:"
echo "   ./bin/start.sh    - 启动监控"
echo "   ./bin/stop.sh     - 停止监控"
echo "   ./tools/debug-processes.sh - 调试进程检测"