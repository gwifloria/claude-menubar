#!/bin/bash

# Claude-Swift 配置文件
# 定义项目的全局配置变量

# 版本信息
CLAUDE_SWIFT_VERSION="1.0.0"

# 基础路径配置
CLAUDE_SWIFT_CONFIG_DIR="$HOME/.claude-swift"
CLAUDE_SWIFT_STATUS_FILE="$CLAUDE_SWIFT_CONFIG_DIR/status-config.json"
CLAUDE_SWIFT_LOG_FILE="$CLAUDE_SWIFT_CONFIG_DIR/monitor.log"
CLAUDE_SWIFT_ERROR_LOG="$CLAUDE_SWIFT_CONFIG_DIR/monitor.error.log"

# SwiftBar配置
SWIFTBAR_PLUGINS_DIR="$HOME/Library/Application Support/SwiftBar"
SWIFTBAR_PLUGIN_NAME="claude-swift.1s.swift"
SWIFTBAR_PLUGIN_PATH="$SWIFTBAR_PLUGINS_DIR/$SWIFTBAR_PLUGIN_NAME"

# LaunchAgent配置
LAUNCHD_DIR="$HOME/Library/LaunchAgents"
LAUNCH_AGENT_PLIST="com.claude-swift.monitor.plist"
LAUNCH_AGENT_PATH="$LAUNCHD_DIR/$LAUNCH_AGENT_PLIST"

# 状态类型定义
CLAUDE_STATUS_IDLE="idle"
CLAUDE_STATUS_EXECUTING="executing"
CLAUDE_STATUS_WAITING="waiting_confirmation"
CLAUDE_STATUS_COMPLETED="completed"
CLAUDE_STATUS_ERROR="error"

# 状态图标映射
declare -A CLAUDE_STATUS_ICONS=(
    ["$CLAUDE_STATUS_IDLE"]="💤"
    ["$CLAUDE_STATUS_EXECUTING"]="⚡️"
    ["$CLAUDE_STATUS_WAITING"]="⏸"
    ["$CLAUDE_STATUS_COMPLETED"]="✅"
    ["$CLAUDE_STATUS_ERROR"]="❌"
)

# 状态颜色映射（用于终端输出）
declare -A CLAUDE_STATUS_COLORS=(
    ["$CLAUDE_STATUS_IDLE"]="gray"
    ["$CLAUDE_STATUS_EXECUTING"]="orange"
    ["$CLAUDE_STATUS_WAITING"]="blue"
    ["$CLAUDE_STATUS_COMPLETED"]="green"
    ["$CLAUDE_STATUS_ERROR"]="red"
)

# 监听配置
MONITOR_INTERVAL=3  # 监听间隔（秒）
MAX_LOG_LINES=1000  # 最大日志行数
CLEANUP_INTERVAL_HOURS=24  # 清理旧记录的间隔（小时）

# iTerm2检测配置
ITERM_DETECTION_METHOD="applescript"  # applescript | process | both
ITERM_CHECK_WINDOW_TITLE=true
ITERM_CHECK_PROCESS_LIST=true

# Claude进程检测关键词
CLAUDE_PROCESS_KEYWORDS=(
    "claude"
    "claude-code"
    "anthropic"
)

# Claude状态检测关键词
declare -A CLAUDE_STATUS_KEYWORDS=(
    ["$CLAUDE_STATUS_EXECUTING"]="Executing|Running|Processing|Working"
    ["$CLAUDE_STATUS_WAITING"]="Waiting|Confirm|Continue|Approve|Accept"
    ["$CLAUDE_STATUS_COMPLETED"]="Completed|Done|Finished|Success"
    ["$CLAUDE_STATUS_ERROR"]="Error|Failed|Exception|Timeout"
)

# SwiftBar刷新配置
SWIFTBAR_AUTO_REFRESH=true
SWIFTBAR_REFRESH_INTERVAL=1  # 插件刷新间隔（秒）

# 调试配置
DEBUG_MODE=false
VERBOSE_LOGGING=false

# 实用函数
get_config_value() {
    local key="$1"
    local default="$2"
    echo "${!key:-$default}"
}

is_debug_mode() {
    [[ "$DEBUG_MODE" == "true" ]]
}

is_verbose_logging() {
    [[ "$VERBOSE_LOGGING" == "true" ]]
}

# 获取状态图标
get_status_icon() {
    local status="$1"
    echo "${CLAUDE_STATUS_ICONS[$status]:-❓}"
}

# 获取状态颜色
get_status_color() {
    local status="$1"
    echo "${CLAUDE_STATUS_COLORS[$status]:-black}"
}

# 日志函数
log_info() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] INFO: $message" >> "$CLAUDE_SWIFT_LOG_FILE"

    if is_verbose_logging; then
        echo "ℹ️  $message" >&2
    fi
}

log_error() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] ERROR: $message" >> "$CLAUDE_SWIFT_ERROR_LOG"
    echo "❌ $message" >&2
}

log_debug() {
    local message="$1"

    if is_debug_mode; then
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo "[$timestamp] DEBUG: $message" >> "$CLAUDE_SWIFT_LOG_FILE"
        echo "🐛 $message" >&2
    fi
}

# 确保配置目录存在
ensure_config_directory() {
    mkdir -p "$CLAUDE_SWIFT_CONFIG_DIR"

    # 创建初始状态文件（如果不存在）
    if [[ ! -f "$CLAUDE_SWIFT_STATUS_FILE" ]]; then
        local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
        echo "{\"projects\": [], \"lastUpdate\": \"$timestamp\"}" > "$CLAUDE_SWIFT_STATUS_FILE"
        log_info "Created initial status configuration file"
    fi
}

# 验证依赖
check_dependencies() {
    local missing_deps=()

    # 检查Python3
    if ! command -v python3 &> /dev/null; then
        missing_deps+=("python3")
    fi

    # 检查osascript（macOS内置）
    if ! command -v osascript &> /dev/null; then
        missing_deps+=("osascript")
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        return 1
    fi

    return 0
}

# 导出配置变量（供其他脚本使用）
export CLAUDE_SWIFT_CONFIG_DIR
export CLAUDE_SWIFT_STATUS_FILE
export CLAUDE_SWIFT_LOG_FILE
export CLAUDE_SWIFT_ERROR_LOG
export SWIFTBAR_PLUGIN_PATH
export LAUNCH_AGENT_PATH

# 在脚本被source时执行初始化
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # 被source调用
    ensure_config_directory
    check_dependencies || log_error "Dependency check failed"
fi