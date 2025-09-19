#!/bin/bash

# Claude-Swift 停止脚本
# 用于停止 Claude 监控服务

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFTBAR_PLUGINS_DIR="$HOME/Library/Application Support/SwiftBar"
CONFIG_DIR="$HOME/.claude-swift"

echo "🛑 Claude-Swift 停止脚本"
echo "================================"

# 检查当前运行状态
MONITOR_RUNNING=$(launchctl list | grep claude-swift.monitor > /dev/null && echo "yes" || echo "no")
PLUGIN_EXISTS=$(test -f "$SWIFTBAR_PLUGINS_DIR/claude-swift.1s.swift" && echo "yes" || echo "no")

echo "当前状态："
echo "   • 监控服务：$(test "$MONITOR_RUNNING" = "yes" && echo "✅ 运行中" || echo "❌ 已停止")"
echo "   • SwiftBar 插件：$(test "$PLUGIN_EXISTS" = "yes" && echo "✅ 已安装" || echo "❌ 未安装")"
echo ""

# 停止 Launch Agent
if [ "$MONITOR_RUNNING" = "yes" ]; then
    echo "🔄 停止后台监控服务..."
    launchctl unload "$HOME/Library/LaunchAgents/com.claude-swift.monitor.plist" 2>/dev/null || true
    echo "✅ 后台监控服务已停止"
else
    echo "ℹ️  后台监控服务已经是停止状态"
fi

# 自动关闭 SwiftBar 以刷新插件
if pgrep -x "SwiftBar" > /dev/null; then
    echo "🔄 关闭 SwiftBar 以刷新插件..."
    osascript -e 'tell application "SwiftBar" to quit' 2>/dev/null || true
    sleep 2
    echo "✅ SwiftBar 已关闭"
fi

# 移除插件（避免显示过期数据）
if [ "$PLUGIN_EXISTS" = "yes" ]; then
    echo "🗑️ 临时移除 SwiftBar 插件..."
    rm -f "$SWIFTBAR_PLUGINS_DIR/claude-swift.1s.swift"
    echo "✅ SwiftBar 插件已移除"
fi

# 询问是否清理配置
echo ""
read -p "🤔 是否清理配置文件和日志？(y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🧹 清理配置文件..."
    rm -rf "$CONFIG_DIR"
    echo "✅ 配置文件已清理"
else
    echo "ℹ️  保留配置文件和日志"
fi

# 停止可能正在运行的手动监控进程
MANUAL_MONITORS=$(ps aux | grep "claude-monitor.sh" | grep -v grep | awk '{print $2}' || true)
if [ -n "$MANUAL_MONITORS" ]; then
    echo ""
    echo "🔍 发现手动启动的监控进程，正在停止..."
    echo "$MANUAL_MONITORS" | xargs kill 2>/dev/null || true
    echo "✅ 手动监控进程已停止"
fi

echo ""
echo "🎉 Claude-Swift 停止完成！"
echo ""
echo "💡 提示："
echo "   • 使用 start.sh 重新启动监控"
echo "   • 使用 deploy/install.sh 重新完整安装"
echo "   • SwiftBar 应用本身仍在运行（如需完全移除请手动卸载）"