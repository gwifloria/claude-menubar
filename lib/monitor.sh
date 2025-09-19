#!/bin/bash

# Claude状态监听脚本
# 监听iTerm2中Claude的执行状态

CONFIG_DIR="$HOME/.claude-swift"
CONFIG_FILE="$CONFIG_DIR/status-config.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 创建配置目录
mkdir -p "$CONFIG_DIR"

# 初始化配置文件
init_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo '{"projects": [], "lastUpdate": "'$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")'"}' > "$CONFIG_FILE"
    fi
}

# 获取当前工作目录的项目名称
get_project_name() {
    local cwd="$1"
    if [[ -z "$cwd" ]]; then
        cwd="$(pwd)"
    fi
    basename "$cwd"
}

# 检测Claude进程的函数
detect_claude_processes() {
    # 查找所有 claude 进程，使用awk精确匹配命令名
    local claude_processes=$(ps aux | grep claude | grep -v grep | awk '$11 == "claude"' | grep -v "Claude.app")
    local process_count=0
    local process_info=""

    if [[ -n "$claude_processes" ]]; then
        process_count=$(echo "$claude_processes" | wc -l | tr -d ' ')
        process_info="$claude_processes"
        echo "active:$process_count:$process_info"
        return 0
    else
        echo "idle:0:"
        return 1
    fi
}

# 获取进程的项目信息
get_process_project_info() {
    local pid="$1"
    local project_name=""

    # 获取进程的工作目录
    local cwd=$(lsof -p "$pid" 2>/dev/null | grep cwd | awk '{print $NF}' | head -1)

    if [[ -n "$cwd" && "$cwd" != "/" ]]; then
        # 从工作目录提取项目名
        project_name=$(basename "$cwd")

        # 避免使用用户名等通用名称
        if [[ "$project_name" =~ ^(home|Users|[a-z]+)$ ]]; then
            # 尝试获取上一级目录
            local parent_dir=$(dirname "$cwd")
            if [[ "$parent_dir" != "/" ]]; then
                project_name=$(basename "$parent_dir")
            fi
        fi
    fi

    # 如果仍然无法获取合适的项目名，使用PID
    if [[ -z "$project_name" || "$project_name" =~ ^(home|Users|[a-z]+)$ ]]; then
        project_name="claude-session-$pid"
    fi

    echo "$project_name"
}

# 检测进程状态（改进版：智能区分用户输入、执行中、等待确认）
detect_process_waiting_state() {
    local claude_processes="$1"
    local user_input_sessions=()
    local executing_sessions=()
    local waiting_sessions=()

    # 获取所有 Claude 进程的 PID
    local pids=$(echo "$claude_processes" | awk '{print $2}')

    for pid in $pids; do
        # 获取进程状态、CPU使用率和内存信息
        local proc_info=$(ps -p $pid -o stat,pcpu,pmem,time,tty 2>/dev/null | tail -1)
        local proc_stat=$(echo "$proc_info" | awk '{print $1}' | tr -d ' ')
        local cpu_usage=$(echo "$proc_info" | awk '{print $2}' | tr -d ' ')
        local tty=$(echo "$proc_info" | awk '{print $5}' | tr -d ' ')
        local project_name=$(get_process_project_info "$pid")

        # 将CPU使用率转换为数值
        local cpu_int=$(echo "$cpu_usage" | cut -d'.' -f1)
        if [[ -z "$cpu_int" || "$cpu_int" == "0" ]]; then
            cpu_int=0
        fi

        # 检测是否在活跃的iTerm2窗口中
        local is_active_window=$(detect_active_iterm_window "$pid" "$tty")

        # 检测最近的文件描述符活动
        local has_recent_io=$(detect_recent_io_activity "$pid")

        # 检测是否有网络活动（Claude API调用）
        local has_network_activity=$(detect_network_activity "$pid")

        # 简化的状态判断逻辑 - 更可靠
        if [[ "$proc_stat" =~ R.* ]] || [[ "$cpu_int" -gt 5 ]] || [[ "$has_network_activity" == "true" ]]; then
            # 运行状态、高CPU或有网络活动 = 执行中
            executing_sessions+=("$project_name:executing:$pid")
        elif [[ "$is_active_window" == "true" ]] && [[ "$cpu_int" -le 2 ]]; then
            # 在活跃窗口且CPU很低 = 用户输入
            user_input_sessions+=("$project_name:user_input:$pid")
        else
            # 其他情况默认为等待确认（更保守的做法）
            waiting_sessions+=("$project_name:waiting_confirmation:$pid")
        fi
    done

    # 输出格式：project:status:pid，每行一个，按优先级排序
    for session in "${waiting_sessions[@]}"; do
        echo "$session"
    done
    for session in "${executing_sessions[@]}"; do
        echo "$session"
    done
    for session in "${user_input_sessions[@]}"; do
        echo "$session"
    done
}

# 检测Claude状态的函数（重构版）
detect_claude_status() {
    local detection_result=$(detect_claude_processes)
    IFS=':' read -r proc_status process_count process_info <<< "$detection_result"

    if [[ "$proc_status" == "active" && "$process_count" -gt 0 ]]; then
        # 有 Claude 进程在运行，检测每个进程的详细状态
        local session_states=$(detect_process_waiting_state "$process_info")

        if [[ -n "$session_states" ]]; then
            # 输出所有会话的状态信息
            echo "$session_states"
        else
            # 如果无法获取详细状态，至少标记为有活动
            echo "claude-unknown:executing:0"
        fi
    else
        # 没有 Claude 进程，返回空
        echo ""
    fi
}

# 清理过期进程记录
cleanup_stale_sessions() {
    python3 -c "
import json
import subprocess

config_file = '$CONFIG_FILE'

try:
    # 获取当前运行的Claude进程PIDs
    result = subprocess.run(['ps', 'aux'], capture_output=True, text=True)
    running_pids = []
    for line in result.stdout.split('\n'):
        if 'claude' in line and 'grep' not in line and 'Claude.app' not in line:
            parts = line.split()
            if len(parts) > 10 and parts[10] == 'claude':
                running_pids.append(parts[1])

    # 读取配置文件
    with open(config_file, 'r') as f:
        config = json.load(f)

    # 过滤掉不再运行的进程
    original_count = len(config['projects'])
    config['projects'] = [p for p in config['projects']
                         if p.get('command', '').replace('PID:', '') in running_pids]

    cleaned_count = original_count - len(config['projects'])
    if cleaned_count > 0:
        # 保存配置
        with open(config_file, 'w') as f:
            json.dump(config, f, indent=2)
        print(f'Cleaned up {cleaned_count} stale sessions')

except Exception as e:
    print(f'Error during cleanup: {e}')
"
}

# 更新状态配置
update_status() {
    local project="$1"
    local status="$2"
    local command="$3"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

    # 使用Python脚本更新JSON（更可靠）
    python3 -c "
import json
import sys
from datetime import datetime

config_file = '$CONFIG_FILE'
project = '$project'
status = '$status'
command = '$command'
timestamp = '$timestamp'

try:
    with open(config_file, 'r') as f:
        config = json.load(f)
except:
    config = {'projects': [], 'lastUpdate': timestamp}

# 查找并更新现有项目，或添加新项目
found = False
for i, p in enumerate(config['projects']):
    if p['project'] == project:
        config['projects'][i] = {
            'project': project,
            'status': status,
            'timestamp': timestamp,
            'command': command if command else None
        }
        found = True
        break

if not found:
    config['projects'].append({
        'project': project,
        'status': status,
        'timestamp': timestamp,
        'command': command if command else None
    })

# 清理超过24小时的idle状态项目
from datetime import datetime, timedelta
current_time = datetime.now()
config['projects'] = [
    p for p in config['projects']
    if not (p['status'] == 'idle' and
           (current_time - datetime.fromisoformat(p['timestamp'].replace('Z', '+00:00'))).total_seconds() > 86400)
]

config['lastUpdate'] = timestamp

with open(config_file, 'w') as f:
    json.dump(config, f, indent=2)

print('Status updated successfully')
" || echo "Failed to update status"
}

# 主监听循环（支持多进程）
monitor_loop() {
    echo "Starting Claude process monitor (multi-session support)"
    echo "Press Ctrl+C to stop monitoring"

    local cleanup_counter=0
    while true; do
        # 每10次循环执行一次清理（约30秒）
        if [[ $((cleanup_counter % 10)) -eq 0 ]]; then
            cleanup_stale_sessions
        fi
        ((cleanup_counter++))

        # 检测所有Claude进程状态
        local session_states=$(detect_claude_status)

        if [[ -n "$session_states" ]]; then
            # 处理每个会话的状态
            while IFS= read -r session_line; do
                if [[ -n "$session_line" ]]; then
                    IFS=':' read -r project_name session_status pid <<< "$session_line"

                    # 更新状态
                    update_status "$project_name" "$session_status" "PID:$pid"
                    echo "[$(date '+%H:%M:%S')] Updated $project_name -> $session_status (PID: $pid)"
                fi
            done <<< "$session_states"
        else
            # 没有Claude进程时，清理旧的执行状态
            echo "[$(date '+%H:%M:%S')] No Claude processes detected"

            # 可选：将所有执行中的会话标记为idle
            # update_all_executing_to_idle
        fi

        # 等待一段时间再检查
        sleep 3
    done
}

# 一次性状态更新
update_once() {
    local target_project="${1:-}"

    echo "Detecting Claude processes..."
    local session_states=$(detect_claude_status)

    if [[ -n "$session_states" ]]; then
        echo "Found Claude sessions:"
        local updated_count=0

        while IFS= read -r session_line; do
            if [[ -n "$session_line" ]]; then
                IFS=':' read -r project_name session_status pid <<< "$session_line"

                # 如果指定了目标项目，只更新该项目
                if [[ -n "$target_project" && "$project_name" != "$target_project" ]]; then
                    continue
                fi

                update_status "$project_name" "$session_status" "PID:$pid"
                echo "  ✅ $project_name -> $session_status (PID: $pid)"
                ((updated_count++))
            fi
        done <<< "$session_states"

        echo "Updated $updated_count sessions"
    else
        echo "No Claude processes detected"

        # 如果指定了项目名且没有检测到进程，标记为idle
        if [[ -n "$target_project" ]]; then
            update_status "$target_project" "idle" ""
            echo "  ✅ $target_project -> idle"
        fi
    fi
}

# 显示帮助
show_help() {
    echo "Claude Monitor Script"
    echo "Usage: $0 [COMMAND] [PROJECT_NAME]"
    echo ""
    echo "Commands:"
    echo "  monitor [PROJECT_NAME]  - Start monitoring (default)"
    echo "  update [PROJECT_NAME]   - Update status once"
    echo "  status [PROJECT_NAME]   - Show current status"
    echo "  help                    - Show this help"
    echo ""
    echo "If PROJECT_NAME is not provided, current directory name is used"
}

# 显示状态
show_status() {
    local project_name="${1:-$(get_project_name)}"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "No status file found. Run monitor first."
        return 1
    fi

    python3 -c "
import json

config_file = '$CONFIG_FILE'
project = '$project_name'

try:
    with open(config_file, 'r') as f:
        config = json.load(f)

    for p in config['projects']:
        if p['project'] == project:
            print(f\"Project: {p['project']}\")
            print(f\"Status: {p['status']}\")
            print(f\"Timestamp: {p['timestamp']}\")
            if p.get('command'):
                print(f\"Command: {p['command']}\")
            exit(0)

    print(f'No status found for project: {project}')
except Exception as e:
    print(f'Error reading status: {e}')
"
}

# 主程序
main() {
    init_config

    local command="${1:-monitor}"
    local project_name="$2"

    case "$command" in
        "monitor")
            monitor_loop "$project_name"
            ;;
        "update")
            update_once "$project_name"
            ;;
        "status")
            show_status "$project_name"
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            echo "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# 检测活跃的iTerm2窗口
detect_active_iterm_window() {
    local pid="$1"
    local tty="$2"

    # 获取当前活跃的iTerm2窗口信息
    local active_tty=$(osascript -e '
        tell application "iTerm2"
            try
                set currentWindow to current window
                set currentSession to current session of currentWindow
                return tty of currentSession
            on error
                return "unknown"
            end try
        end tell
    ' 2>/dev/null)

    if [[ "$tty" == "$active_tty" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

# 检测最近的IO活动
detect_recent_io_activity() {
    local pid="$1"

    # 检查进程的文件描述符最近是否有活动
    local fd_activity=$(lsof -p "$pid" 2>/dev/null | grep -E "(pipe|socket)" | wc -l | tr -d ' ')

    if [[ "$fd_activity" -gt 2 ]]; then
        echo "true"
    else
        echo "false"
    fi
}

# 检测网络活动（Claude API调用）
detect_network_activity() {
    local pid="$1"

    # 检查进程是否有网络连接
    local network_connections=$(lsof -p "$pid" 2>/dev/null | grep -E "TCP.*ESTABLISHED" | wc -l | tr -d ' ')

    if [[ "$network_connections" -gt 0 ]]; then
        echo "true"
    else
        echo "false"
    fi
}

# 处理中断信号
trap 'echo "Monitoring stopped"; exit 0' INT TERM

# 运行主程序
main "$@"