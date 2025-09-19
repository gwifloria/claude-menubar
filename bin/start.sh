#!/bin/bash

# Claude-Swift 日常启动脚本
# 用于启动 Claude 监控，不重新安装应用

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFTBAR_PLUGINS_DIR="$HOME/Library/Application Support/SwiftBar"
CONFIG_DIR="$HOME/.claude-swift"

echo "🚀 Claude-Swift 启动脚本"
echo "================================"

# 检查 SwiftBar 是否已安装
if ! command -v brew >/dev/null 2>&1; then
    echo "❌ 未发现 Homebrew，请先运行 install.sh 进行初始化安装"
    exit 1
fi

if ! brew list --cask | grep -q swiftbar; then
    echo "❌ 未发现 SwiftBar，请先运行 install.sh 进行初始化安装"
    exit 1
fi

echo "✅ SwiftBar 已安装"

# 创建配置目录
mkdir -p "$CONFIG_DIR"
mkdir -p "$SWIFTBAR_PLUGINS_DIR"

# 部署/更新 SwiftBar 插件
echo "📝 部署 SwiftBar 插件..."
cp "$SCRIPT_DIR/lib/swiftbar-plugin.swift" "$SWIFTBAR_PLUGINS_DIR/claude-swift.1s.swift"
chmod +x "$SWIFTBAR_PLUGINS_DIR/claude-swift.1s.swift"
echo "✅ SwiftBar 插件已更新"

# 创建 Launch Agent
echo "⚙️ 配置后台监控服务..."
cat > "$HOME/Library/LaunchAgents/com.claude-swift.monitor.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claude-swift.monitor</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$SCRIPT_DIR/lib/monitor.sh</string>
        <string>monitor</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$CONFIG_DIR/monitor.log</string>
    <key>StandardErrorPath</key>
    <string>$CONFIG_DIR/monitor-error.log</string>
</dict>
</plist>
EOF

# 加载 Launch Agent
launchctl load "$HOME/Library/LaunchAgents/com.claude-swift.monitor.plist"
echo "✅ 后台监控服务已启动"

# 刷新 SwiftBar
echo "🔄 刷新 SwiftBar..."
if pgrep -x "SwiftBar" > /dev/null; then
    # 发送刷新信号给 SwiftBar
    osascript -e 'tell application "SwiftBar" to quit' 2>/dev/null || true
    sleep 1
fi

open -a SwiftBar
echo "✅ SwiftBar 已刷新"

# 等待一下让服务启动
sleep 2

# 显示状态
echo ""
echo "📊 当前状态："
echo "   • 监控服务：$(launchctl list | grep claude-swift > /dev/null && echo "✅ 运行中" || echo "❌ 未运行")"
echo "   • SwiftBar 插件：$(test -f "$SWIFTBAR_PLUGINS_DIR/claude-swift.1s.swift" && echo "✅ 已安装" || echo "❌ 未安装")"

echo ""
echo "🎉 Claude-Swift 启动完成！"
echo "📱 请查看菜单栏的 Claude 状态指示器"
echo ""
echo "💡 使用说明："
echo "   • stop.sh - 停止监控服务"
echo "   • claude-status - 查看状态"
echo "   • claude-monitor update - 手动更新一次"