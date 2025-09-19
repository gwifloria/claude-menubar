#!/bin/bash

# Claude-Swift 初始化安装脚本
# 用于首次安装 - 安装SwiftBar应用和初始化环境
# 日常启动请使用 ../start.sh

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置路径
CLAUDE_SWIFT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$HOME/.claude-swift"
SWIFTBAR_PLUGINS_DIR="$HOME/Library/Application Support/SwiftBar"
LAUNCHD_DIR="$HOME/Library/LaunchAgents"

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

# 检查系统要求
check_requirements() {
    echo_info "Checking system requirements..."

    # 检查macOS版本
    if [[ "$(uname)" != "Darwin" ]]; then
        echo_error "This script only works on macOS"
        exit 1
    fi

    # 检查Python3
    if ! command -v python3 &> /dev/null; then
        echo_error "Python3 is required but not installed"
        exit 1
    fi

    # 检查Homebrew
    if ! command -v brew &> /dev/null; then
        echo_warning "Homebrew not found. Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    echo_success "System requirements check passed"
}

# 安装SwiftBar
install_swiftbar() {
    echo_info "Installing SwiftBar..."

    if command -v swiftbar &> /dev/null; then
        echo_warning "SwiftBar is already installed"
        return
    fi

    # 使用Homebrew安装SwiftBar
    if brew list swiftbar &> /dev/null; then
        echo_warning "SwiftBar is already installed via Homebrew"
    else
        brew install --cask swiftbar
    fi

    echo_success "SwiftBar installed successfully"
}

# 创建配置目录
setup_config_directory() {
    echo_info "Setting up configuration directory..."

    mkdir -p "$CONFIG_DIR"
    mkdir -p "$SWIFTBAR_PLUGINS_DIR"
    mkdir -p "$LAUNCHD_DIR"

    # 创建初始配置文件
    if [[ ! -f "$CONFIG_DIR/status-config.json" ]]; then
        echo '{"projects": [], "lastUpdate": "'$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")'"}' > "$CONFIG_DIR/status-config.json"
    fi

    echo_success "Configuration directory setup completed"
}

# 安装SwiftBar插件
install_swiftbar_plugin() {
    echo_info "Installing SwiftBar plugin..."

    local plugin_source="$CLAUDE_SWIFT_DIR/lib/swiftbar-plugin.swift"
    local plugin_dest="$SWIFTBAR_PLUGINS_DIR/claude-swift.1s.swift"

    if [[ ! -f "$plugin_source" ]]; then
        echo_error "SwiftBar plugin source not found: $plugin_source"
        exit 1
    fi

    # 复制插件文件
    cp "$plugin_source" "$plugin_dest"
    chmod +x "$plugin_dest"

    echo_success "SwiftBar plugin installed"
}

# 创建LaunchAgent用于自动启动监听
create_launch_agent() {
    echo_info "Creating launch agent for auto-monitoring..."

    local plist_file="$LAUNCHD_DIR/com.claude-swift.monitor.plist"

    cat > "$plist_file" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claude-swift.monitor</string>
    <key>ProgramArguments</key>
    <array>
        <string>$CLAUDE_SWIFT_DIR/lib/monitor.sh</string>
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

    echo_success "Launch agent created"
}

# 启动服务
start_services() {
    echo_info "Starting services..."

    # 启动SwiftBar（如果未运行）
    if ! pgrep -f "SwiftBar" > /dev/null; then
        echo_info "Starting SwiftBar..."
        open -a SwiftBar || echo_warning "Failed to start SwiftBar automatically. Please start it manually."
    else
        echo_warning "SwiftBar is already running"
    fi

    # 加载launch agent
    local plist_file="$LAUNCHD_DIR/com.claude-swift.monitor.plist"
    if launchctl list | grep -q "com.claude-swift.monitor"; then
        echo_warning "Launch agent is already loaded"
        launchctl unload "$plist_file" 2>/dev/null || true
    fi

    launchctl load "$plist_file"

    echo_success "Services started successfully"
}

# 创建便捷命令
create_convenience_commands() {
    echo_info "Creating convenience commands..."

    # 创建全局命令链接
    local bin_dir="/usr/local/bin"
    if [[ ! -w "$bin_dir" ]]; then
        bin_dir="$HOME/.local/bin"
        mkdir -p "$bin_dir"

        # 添加到PATH（如果不存在）
        local profile_file="$HOME/.zshrc"
        if [[ ! -f "$profile_file" ]] || ! grep -q "$bin_dir" "$profile_file"; then
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$profile_file"
            echo_warning "Added $bin_dir to PATH in $profile_file. Please restart your terminal or run: source $profile_file"
        fi
    fi

    # 创建claude-status命令
    cat > "$bin_dir/claude-status" << EOF
#!/bin/bash
exec "$CLAUDE_SWIFT_DIR/lib/updater.sh" "\$@"
EOF
    chmod +x "$bin_dir/claude-status"

    # 创建claude-monitor命令
    cat > "$bin_dir/claude-monitor" << EOF
#!/bin/bash
exec "$CLAUDE_SWIFT_DIR/lib/monitor.sh" "\$@"
EOF
    chmod +x "$bin_dir/claude-monitor"

    echo_success "Convenience commands created:"
    echo "  • claude-status - Update Claude status"
    echo "  • claude-monitor - Monitor Claude directly"
}

# 显示安装完成信息
show_completion_info() {
    echo ""
    echo_success "🎉 Claude-Swift installation completed successfully!"
    echo ""
    echo "📊 What was installed:"
    echo "  • SwiftBar application"
    echo "  • Claude status monitoring plugin"
    echo "  • Automatic background monitoring service"
    echo "  • Convenience commands (claude-status, claude-monitor)"
    echo ""
    echo "🚀 Getting Started:"
    echo "  1. SwiftBar should now be running in your menu bar"
    echo "  2. Open a terminal in any project directory"
    echo "  3. Use these commands to update Claude status:"
    echo ""
    echo "     claude-status executing    # Set status to executing"
    echo "     claude-status waiting      # Set status to waiting"
    echo "     claude-status completed    # Set status to completed"
    echo "     claude-status list         # Show all project statuses"
    echo ""
    echo "🔧 Manual Control:"
    echo "  • Start monitoring: claude-monitor monitor [project-name]"
    echo "  • Check status: claude-monitor status [project-name]"
    echo ""
    echo "📁 Configuration:"
    echo "  • Config dir: $CONFIG_DIR"
    echo "  • Logs: $CONFIG_DIR/monitor.log"
    echo ""
    echo "⚠️  If you don't see the Claude icon in menu bar:"
    echo "  1. Open SwiftBar preferences"
    echo "  2. Make sure the plugin directory is: $SWIFTBAR_PLUGINS_DIR"
    echo "  3. Refresh plugins or restart SwiftBar"
    echo ""
    echo "🔄 Daily Usage:"
    echo "  • 启动监控: cd $CLAUDE_SWIFT_DIR && ./bin/start.sh"
    echo "  • 停止监控: cd $CLAUDE_SWIFT_DIR && ./bin/stop.sh"
    echo "  • 不要重复运行 install.sh！仅用于首次安装。"
}

# 验证安装
verify_installation() {
    echo_info "Verifying installation..."

    local errors=0

    # 检查SwiftBar插件
    if [[ ! -f "$SWIFTBAR_PLUGINS_DIR/claude-swift.1s.swift" ]]; then
        echo_error "SwiftBar plugin not found"
        ((errors++))
    fi

    # 检查配置文件
    if [[ ! -f "$CONFIG_DIR/status-config.json" ]]; then
        echo_error "Configuration file not found"
        ((errors++))
    fi

    # 检查launch agent
    if [[ ! -f "$LAUNCHD_DIR/com.claude-swift.monitor.plist" ]]; then
        echo_error "Launch agent not found"
        ((errors++))
    fi

    # 检查便捷命令
    if ! command -v claude-status &> /dev/null; then
        echo_warning "claude-status command not in PATH"
    fi

    if [[ $errors -eq 0 ]]; then
        echo_success "Installation verification passed"
        return 0
    else
        echo_error "Installation verification failed with $errors errors"
        return 1
    fi
}

# 主安装流程
main() {
    echo "🚀 Claude-Swift Installer"
    echo "========================="
    echo ""

    # 检查是否已经安装
    if [[ -f "$CONFIG_DIR/installed" ]]; then
        echo_warning "Claude-Swift appears to be already installed."
        read -p "Do you want to reinstall? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Installation cancelled."
            exit 0
        fi
    fi

    # 执行安装步骤
    check_requirements
    install_swiftbar
    setup_config_directory
    install_swiftbar_plugin
    create_launch_agent
    start_services
    create_convenience_commands

    # 验证并完成
    if verify_installation; then
        # 标记已安装
        touch "$CONFIG_DIR/installed"
        show_completion_info
    else
        echo_error "Installation completed with errors. Please check the logs."
        exit 1
    fi
}

# 运行主程序
main "$@"