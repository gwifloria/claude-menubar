#!/bin/bash

# Claude-Swift 清理脚本
# 完全移除所有安装的组件和配置

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
LOCAL_BIN_DIR="$HOME/.local/bin"
GLOBAL_BIN_DIR="/usr/local/bin"

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

# 确认清理操作
confirm_cleanup() {
    echo "🗑️  Claude-Swift Cleanup Utility"
    echo "================================"
    echo ""
    echo_warning "This will completely remove all Claude-Swift components:"
    echo "  • SwiftBar plugin"
    echo "  • Background monitoring service"
    echo "  • Configuration files and logs"
    echo "  • Convenience commands"
    echo "  • Launch agents"
    echo ""
    echo_info "SwiftBar application itself will NOT be removed."
    echo ""

    read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cleanup cancelled."
        exit 0
    fi
}

# 停止并卸载Launch Agent
remove_launch_agent() {
    echo_info "Removing launch agent..."

    local plist_file="$LAUNCHD_DIR/com.claude-swift.monitor.plist"

    # 停止服务
    if launchctl list | grep -q "com.claude-swift.monitor"; then
        echo_info "Stopping background monitoring service..."
        launchctl unload "$plist_file" 2>/dev/null || true
        echo_success "Background service stopped"
    fi

    # 删除plist文件
    if [[ -f "$plist_file" ]]; then
        rm "$plist_file"
        echo_success "Launch agent removed"
    else
        echo_warning "Launch agent not found"
    fi
}

# 移除SwiftBar插件
remove_swiftbar_plugin() {
    echo_info "Removing SwiftBar plugin..."

    local plugin_file="$SWIFTBAR_PLUGINS_DIR/claude-swift.1s.swift"

    if [[ -f "$plugin_file" ]]; then
        rm "$plugin_file"
        echo_success "SwiftBar plugin removed"

        # 尝试刷新SwiftBar
        osascript -e 'tell application "SwiftBar" to refresh' 2>/dev/null || true
    else
        echo_warning "SwiftBar plugin not found"
    fi
}

# 移除配置目录
remove_config_directory() {
    echo_info "Removing configuration directory..."

    if [[ -d "$CONFIG_DIR" ]]; then
        # 显示即将删除的文件
        echo_info "Files to be removed:"
        find "$CONFIG_DIR" -type f | sed 's/^/  • /'

        rm -rf "$CONFIG_DIR"
        echo_success "Configuration directory removed"
    else
        echo_warning "Configuration directory not found"
    fi
}

# 移除便捷命令
remove_convenience_commands() {
    echo_info "Removing convenience commands..."

    local commands=("claude-status" "claude-monitor")
    local removed_count=0

    for cmd in "${commands[@]}"; do
        # 检查全局bin目录
        if [[ -f "$GLOBAL_BIN_DIR/$cmd" ]]; then
            rm "$GLOBAL_BIN_DIR/$cmd" 2>/dev/null && {
                echo_success "Removed $GLOBAL_BIN_DIR/$cmd"
                ((removed_count++))
            } || echo_warning "Failed to remove $GLOBAL_BIN_DIR/$cmd (permission denied)"
        fi

        # 检查本地bin目录
        if [[ -f "$LOCAL_BIN_DIR/$cmd" ]]; then
            rm "$LOCAL_BIN_DIR/$cmd"
            echo_success "Removed $LOCAL_BIN_DIR/$cmd"
            ((removed_count++))
        fi
    done

    if [[ $removed_count -eq 0 ]]; then
        echo_warning "No convenience commands found"
    else
        echo_success "Removed $removed_count convenience commands"
    fi
}

# 清理PATH设置（可选）
cleanup_path_settings() {
    echo_info "Checking PATH settings..."

    local profile_files=("$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile")
    local cleaned=false

    for profile_file in "${profile_files[@]}"; do
        if [[ -f "$profile_file" ]] && grep -q "$LOCAL_BIN_DIR" "$profile_file"; then
            echo_warning "Found claude-swift PATH entry in $profile_file"
            read -p "Remove PATH entry from $profile_file? (y/N): " -n 1 -r
            echo

            if [[ $REPLY =~ ^[Yy]$ ]]; then
                # 创建备份
                cp "$profile_file" "$profile_file.backup.$(date +%Y%m%d_%H%M%S)"

                # 移除PATH条目
                grep -v "$LOCAL_BIN_DIR" "$profile_file.backup"* > "$profile_file" || {
                    echo_error "Failed to clean PATH from $profile_file"
                    mv "$profile_file.backup"* "$profile_file"
                }

                echo_success "PATH entry removed from $profile_file"
                cleaned=true
            fi
        fi
    done

    if [[ $cleaned == true ]]; then
        echo_warning "Please restart your terminal or run 'source ~/.zshrc' to apply changes"
    fi
}

# 检查残留进程
check_remaining_processes() {
    echo_info "Checking for remaining processes..."

    local claude_processes
    claude_processes=$(ps aux | grep -v grep | grep "claude-monitor" || true)

    if [[ -n "$claude_processes" ]]; then
        echo_warning "Found running claude-monitor processes:"
        echo "$claude_processes"

        read -p "Kill these processes? (y/N): " -n 1 -r
        echo

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            pkill -f "claude-monitor" || true
            echo_success "Processes terminated"
        fi
    else
        echo_success "No remaining processes found"
    fi
}

# 显示清理总结
show_cleanup_summary() {
    echo ""
    echo_success "🧹 Claude-Swift cleanup completed!"
    echo ""
    echo "📋 What was removed:"
    echo "  • SwiftBar plugin"
    echo "  • Background monitoring service"
    echo "  • Configuration files and logs"
    echo "  • Convenience commands"
    echo "  • Launch agents"
    echo ""
    echo_info "SwiftBar application itself was not removed."
    echo_info "You can reinstall Claude-Swift anytime by running ./deploy/install.sh"
    echo ""

    if command -v swiftbar &> /dev/null; then
        echo_warning "SwiftBar is still installed. To remove it completely run:"
        echo "  brew uninstall --cask swiftbar"
    fi
}

# 验证清理是否完成
verify_cleanup() {
    echo_info "Verifying cleanup..."

    local remaining_items=()

    # 检查各种残留文件
    [[ -f "$SWIFTBAR_PLUGINS_DIR/claude-swift.1s.swift" ]] && remaining_items+=("SwiftBar plugin")
    [[ -f "$LAUNCHD_DIR/com.claude-swift.monitor.plist" ]] && remaining_items+=("Launch agent")
    [[ -d "$CONFIG_DIR" ]] && remaining_items+=("Configuration directory")
    [[ -f "$LOCAL_BIN_DIR/claude-status" ]] && remaining_items+=("claude-status command")
    [[ -f "$LOCAL_BIN_DIR/claude-monitor" ]] && remaining_items+=("claude-monitor command")
    [[ -f "$GLOBAL_BIN_DIR/claude-status" ]] && remaining_items+=("global claude-status command")
    [[ -f "$GLOBAL_BIN_DIR/claude-monitor" ]] && remaining_items+=("global claude-monitor command")

    if [[ ${#remaining_items[@]} -eq 0 ]]; then
        echo_success "Cleanup verification passed - all components removed"
        return 0
    else
        echo_warning "Some items were not completely removed:"
        for item in "${remaining_items[@]}"; do
            echo "  • $item"
        done
        return 1
    fi
}

# 主清理流程
main() {
    # 检查是否已安装
    if [[ ! -f "$CONFIG_DIR/installed" ]] && [[ ! -d "$CONFIG_DIR" ]]; then
        echo_warning "Claude-Swift doesn't appear to be installed."
        exit 0
    fi

    # 确认清理
    confirm_cleanup

    # 执行清理步骤
    echo ""
    echo_info "Starting cleanup process..."

    remove_launch_agent
    remove_swiftbar_plugin
    remove_convenience_commands
    check_remaining_processes
    remove_config_directory
    cleanup_path_settings

    # 验证和总结
    echo ""
    verify_cleanup
    show_cleanup_summary
}

# 处理参数
case "${1:-}" in
    "--force"|"-f")
        # 跳过确认，强制清理
        SKIP_CONFIRMATION=true
        ;;
    "--help"|"-h")
        echo "Claude-Swift Cleanup Script"
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  -f, --force    Skip confirmation prompt"
        echo "  -h, --help     Show this help message"
        echo ""
        echo "This script will remove all Claude-Swift components including:"
        echo "  • SwiftBar plugin"
        echo "  • Configuration files"
        echo "  • Background services"
        echo "  • Convenience commands"
        exit 0
        ;;
esac

# 运行主程序
if [[ "${SKIP_CONFIRMATION:-}" == "true" ]]; then
    # 重写确认函数为空操作
    confirm_cleanup() {
        echo_info "Running cleanup in force mode..."
    }
fi

main "$@"