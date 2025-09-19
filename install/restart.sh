#!/bin/bash

# Claude-Swift 重启脚本
# 重启监听服务和刷新SwiftBar插件

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置路径
CONFIG_DIR="$HOME/.claude-swift"
SWIFTBAR_PLUGINS_DIR="$HOME/Library/Application Support/SwiftBar"
LAUNCHD_DIR="$HOME/Library/LaunchAgents"
CLAUDE_SWIFT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

echo_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

echo_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

echo_error() {
    echo -e "${RED}❌ $1${NC}"
}

# 检查安装状态
check_installation() {
    echo_info "Checking Claude-Swift installation..."

    if [[ ! -f "$CONFIG_DIR/installed" ]] && [[ ! -d "$CONFIG_DIR" ]]; then
        echo_error "Claude-Swift is not installed. Please run ./deploy/install.sh first."
        exit 1
    fi

    local missing_components=()

    [[ ! -f "$SWIFTBAR_PLUGINS_DIR/claude-swift.1s.swift" ]] && missing_components+=("SwiftBar plugin")
    [[ ! -f "$LAUNCHD_DIR/com.claude-swift.monitor.plist" ]] && missing_components+=("Launch agent")

    if [[ ${#missing_components[@]} -gt 0 ]]; then
        echo_warning "Missing components detected:"
        for component in "${missing_components[@]}"; do
            echo "  • $component"
        done
        echo_warning "Consider running ./deploy/install.sh to fix missing components."
    else
        echo_success "Installation check passed"
    fi
}

# 重启Launch Agent
restart_launch_agent() {
    echo_info "Restarting background monitoring service..."

    local plist_file="$LAUNCHD_DIR/com.claude-swift.monitor.plist"

    if [[ ! -f "$plist_file" ]]; then
        echo_warning "Launch agent not found. Creating new one..."

        # 重新创建launch agent
        cat > "$plist_file" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claude-swift.monitor</string>
    <key>ProgramArguments</key>
    <array>
        <string>$CLAUDE_SWIFT_DIR/scripts/claude-monitor.sh</string>
        <string>monitor</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$CONFIG_DIR/monitor.log</string>
    <key>StandardErrorPath</key>
    <string>$CONFIG_DIR/monitor.error.log</string>
    <key>WorkingDirectory</key>
    <string>$HOME</string>
    <key>ProcessType</key>
    <string>Background</string>
</dict>
</plist>
EOF
    fi

    # 停止现有服务
    if launchctl list | grep -q "com.claude-swift.monitor"; then
        echo_info "Stopping existing service..."
        launchctl unload "$plist_file" 2>/dev/null || true
        sleep 1
    fi

    # 启动服务
    echo_info "Starting monitoring service..."
    launchctl load "$plist_file"

    # 验证服务状态
    sleep 2
    if launchctl list | grep -q "com.claude-swift.monitor"; then
        echo_success "Background monitoring service restarted successfully"
    else
        echo_error "Failed to start monitoring service"
        return 1
    fi
}

# 刷新SwiftBar插件
refresh_swiftbar_plugin() {
    echo_info "Refreshing SwiftBar plugin..."

    local plugin_file="$SWIFTBAR_PLUGINS_DIR/claude-swift.1s.swift"

    if [[ ! -f "$plugin_file" ]]; then
        echo_warning "SwiftBar plugin not found. Copying from source..."
        local plugin_source="$CLAUDE_SWIFT_DIR/scripts/swiftbar-plugin.swift"

        if [[ -f "$plugin_source" ]]; then
            cp "$plugin_source" "$plugin_file"
            chmod +x "$plugin_file"
            echo_success "SwiftBar plugin restored"
        else
            echo_error "Plugin source not found: $plugin_source"
            return 1
        fi
    fi

    # 更新插件时间戳以触发刷新
    touch "$plugin_file"

    # 尝试通知SwiftBar刷新
    if pgrep -f "SwiftBar" > /dev/null; then
        osascript -e 'tell application "SwiftBar" to refresh' 2>/dev/null || {
            echo_warning "Failed to send refresh command to SwiftBar"
        }
        echo_success "SwiftBar plugin refreshed"
    else
        echo_warning "SwiftBar is not running. Starting SwiftBar..."
        open -a SwiftBar || {
            echo_error "Failed to start SwiftBar. Please start it manually."
            return 1
        }
        echo_success "SwiftBar started"
    fi
}

# 清理旧日志
cleanup_logs() {
    echo_info "Cleaning up old logs..."

    local log_files=(
        "$CONFIG_DIR/monitor.log"
        "$CONFIG_DIR/monitor.error.log"
    )

    for log_file in "${log_files[@]}"; do
        if [[ -f "$log_file" ]]; then
            # 保留最后100行
            if [[ -s "$log_file" ]]; then
                tail -n 100 "$log_file" > "$log_file.tmp" && mv "$log_file.tmp" "$log_file"
                echo_success "Cleaned up $(basename "$log_file")"
            fi
        fi
    done
}

# 验证服务状态
verify_services() {
    echo_info "Verifying service status..."

    local issues=()

    # 检查Launch Agent
    if ! launchctl list | grep -q "com.claude-swift.monitor"; then
        issues+=("Background monitoring service is not running")
    fi

    # 检查SwiftBar
    if ! pgrep -f "SwiftBar" > /dev/null; then
        issues+=("SwiftBar is not running")
    fi

    # 检查插件文件
    if [[ ! -f "$SWIFTBAR_PLUGINS_DIR/claude-swift.1s.swift" ]]; then
        issues+=("SwiftBar plugin file is missing")
    fi

    if [[ ${#issues[@]} -eq 0 ]]; then
        echo_success "All services are running properly"
        return 0
    else
        echo_warning "Found ${#issues[@]} issues:"
        for issue in "${issues[@]}"; do
            echo "  • $issue"
        done
        return 1
    fi
}

# 显示服务状态
show_status() {
    echo ""
    echo "📊 Service Status:"
    echo "=================="

    # Launch Agent状态
    if launchctl list | grep -q "com.claude-swift.monitor"; then
        echo_success "Background Monitoring: Running"
    else
        echo_error "Background Monitoring: Stopped"
    fi

    # SwiftBar状态
    if pgrep -f "SwiftBar" > /dev/null; then
        echo_success "SwiftBar: Running"
    else
        echo_error "SwiftBar: Not Running"
    fi

    # 插件状态
    if [[ -f "$SWIFTBAR_PLUGINS_DIR/claude-swift.1s.swift" ]]; then
        echo_success "Plugin: Installed"
    else
        echo_error "Plugin: Missing"
    fi

    # 配置状态
    if [[ -f "$CONFIG_DIR/status-config.json" ]]; then
        echo_success "Configuration: Available"

        # 显示当前项目数量
        local project_count
        project_count=$(python3 -c "
import json
try:
    with open('$CONFIG_DIR/status-config.json', 'r') as f:
        config = json.load(f)
    print(len(config.get('projects', [])))
except:
    print(0)
" 2>/dev/null || echo "0")
        echo_info "Active Projects: $project_count"
    else
        echo_error "Configuration: Missing"
    fi

    echo ""
}

# 显示重启完成信息
show_completion_info() {
    echo_success "🔄 Claude-Swift restart completed!"
    echo ""
    echo "✨ What was restarted:"
    echo "  • Background monitoring service"
    echo "  • SwiftBar plugin"
    echo "  • Log files cleaned up"
    echo ""
    echo "🚀 You can now:"
    echo "  • Check status with: claude-status list"
    echo "  • Update status with: claude-status executing"
    echo "  • Monitor manually with: claude-monitor monitor"
    echo ""
    echo "📁 Logs location: $CONFIG_DIR/"
}

# 处理命令行参数
handle_arguments() {
    case "${1:-}" in
        "--status"|"-s")
            show_status
            exit 0
            ;;
        "--logs"|"-l")
            echo "📋 Recent Monitor Logs:"
            echo "======================"
            if [[ -f "$CONFIG_DIR/monitor.log" ]]; then
                tail -n 20 "$CONFIG_DIR/monitor.log"
            else
                echo "No logs found"
            fi
            echo ""
            echo "📋 Recent Error Logs:"
            echo "===================="
            if [[ -f "$CONFIG_DIR/monitor.error.log" ]]; then
                tail -n 20 "$CONFIG_DIR/monitor.error.log"
            else
                echo "No error logs found"
            fi
            exit 0
            ;;
        "--help"|"-h")
            echo "Claude-Swift Restart Script"
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -s, --status    Show current service status"
            echo "  -l, --logs      Show recent logs"
            echo "  -h, --help      Show this help message"
            echo ""
            echo "This script will restart all Claude-Swift services including:"
            echo "  • Background monitoring service"
            echo "  • SwiftBar plugin refresh"
            echo "  • Log cleanup"
            exit 0
            ;;
        "")
            # 默认重启操作
            ;;
        *)
            echo_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
}

# 主重启流程
main() {
    echo "🔄 Claude-Swift Restart Utility"
    echo "==============================="
    echo ""

    # 处理参数
    handle_arguments "$@"

    # 执行重启步骤
    check_installation
    cleanup_logs
    restart_launch_agent
    refresh_swiftbar_plugin

    # 验证和显示状态
    echo ""
    if verify_services; then
        show_completion_info
    else
        echo_warning "Restart completed with some issues. Check the status above."
        echo_info "Try running ./deploy/install.sh to fix any missing components."
    fi

    show_status
}

# 运行主程序
main "$@"