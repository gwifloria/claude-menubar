#!/bin/bash

# Claude-Swift 更新脚本
# 仅更新 SwiftBar 插件，不重新安装应用

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFTBAR_PLUGINS_DIR="$HOME/Library/Application Support/SwiftBar"

echo "🔄 Claude-Swift 插件更新"
echo "=========================="

# 检查 SwiftBar 是否安装
if ! brew list --cask | grep -q swiftbar; then
    echo "❌ SwiftBar 未安装，请先运行 install.sh"
    exit 1
fi

# 备份现有插件
if [[ -f "$SWIFTBAR_PLUGINS_DIR/claude-swift.1s.swift" ]]; then
    echo "📦 备份现有插件..."
    cp "$SWIFTBAR_PLUGINS_DIR/claude-swift.1s.swift" "$SWIFTBAR_PLUGINS_DIR/claude-swift.1s.swift.backup.$(date +%Y%m%d-%H%M%S)"
fi

# 更新插件
echo "🔄 更新 SwiftBar 插件..."
mkdir -p "$SWIFTBAR_PLUGINS_DIR"
cp "$SCRIPT_DIR/lib/swiftbar-plugin.swift" "$SWIFTBAR_PLUGINS_DIR/claude-swift.1s.swift"
chmod +x "$SWIFTBAR_PLUGINS_DIR/claude-swift.1s.swift"

# 刷新 SwiftBar
echo "🔄 刷新 SwiftBar..."
if pgrep -x "SwiftBar" > /dev/null; then
    osascript -e 'tell application "SwiftBar" to quit' 2>/dev/null || true
    sleep 1
    open -a SwiftBar
    echo "✅ SwiftBar 已刷新"
else
    echo "ℹ️  SwiftBar 未运行，请手动启动"
fi

echo ""
echo "🎉 插件更新完成！"
echo ""
echo "💡 提示："
echo "   • 查看状态: ./bin/status.sh"
echo "   • 重启监控: ./bin/stop.sh && ./bin/start.sh"