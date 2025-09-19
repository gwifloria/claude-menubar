#!/bin/bash

# 状态更新工具脚本
# 提供手动更新Claude状态的接口

CONFIG_DIR="$HOME/.claude-swift"
CONFIG_FILE="$CONFIG_DIR/status-config.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 创建配置目录
mkdir -p "$CONFIG_DIR"

# 获取当前工作目录的项目名称
get_project_name() {
    local cwd="$1"
    if [[ -z "$cwd" ]]; then
        cwd="$(pwd)"
    fi
    basename "$cwd"
}

# 更新状态到配置文件
update_status() {
    local project="$1"
    local status="$2"
    local command="$3"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

    # 确保配置文件存在
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo '{"projects": [], "lastUpdate": "'$timestamp'"}' > "$CONFIG_FILE"
    fi

    # 使用Python更新JSON配置
    python3 -c "
import json
import sys
from datetime import datetime, timedelta

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

# 查找并更新现有项目
found = False
for i, p in enumerate(config['projects']):
    if p['project'] == project:
        config['projects'][i] = {
            'project': project,
            'status': status,
            'timestamp': timestamp,
            'command': command if command else p.get('command')
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

# 清理旧的idle状态项目（超过24小时）
current_time = datetime.now()
config['projects'] = [
    p for p in config['projects']
    if not (p['status'] == 'idle' and
           (current_time - datetime.fromisoformat(p['timestamp'].replace('Z', '+00:00'))).total_seconds() > 86400)
]

config['lastUpdate'] = timestamp

with open(config_file, 'w') as f:
    json.dump(config, f, indent=2)

print(f'✅ Status updated: {project} -> {status}')
"

    # 通知SwiftBar刷新
    refresh_swiftbar
}

# 刷新SwiftBar显示
refresh_swiftbar() {
    # 发送刷新信号给SwiftBar
    osascript -e 'tell application "SwiftBar" to refresh' 2>/dev/null || true

    # 备用方法：通过touch插件文件触发刷新
    local swiftbar_plugin_path="$HOME/Library/Application Support/SwiftBar/claude-swift.1s.swift"
    if [[ -f "$swiftbar_plugin_path" ]]; then
        touch "$swiftbar_plugin_path"
    fi
}

# 设置项目状态为执行中
set_executing() {
    local project="${1:-$(get_project_name)}"
    local command="$2"
    update_status "$project" "executing" "$command"
}

# 设置项目状态为等待确认
set_waiting() {
    local project="${1:-$(get_project_name)}"
    local command="$2"
    update_status "$project" "waiting_confirmation" "$command"
}

# 设置项目状态为完成
set_completed() {
    local project="${1:-$(get_project_name)}"
    update_status "$project" "completed" ""
}

# 设置项目状态为错误
set_error() {
    local project="${1:-$(get_project_name)}"
    local error_msg="$2"
    update_status "$project" "error" "$error_msg"
}

# 设置项目状态为闲置
set_idle() {
    local project="${1:-$(get_project_name)}"
    update_status "$project" "idle" ""
}

# 删除项目状态
remove_project() {
    local project="${1:-$(get_project_name)}"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

    python3 -c "
import json

config_file = '$CONFIG_FILE'
project = '$project'
timestamp = '$timestamp'

try:
    with open(config_file, 'r') as f:
        config = json.load(f)

    # 移除指定项目
    config['projects'] = [p for p in config['projects'] if p['project'] != project]
    config['lastUpdate'] = timestamp

    with open(config_file, 'w') as f:
        json.dump(config, f, indent=2)

    print(f'❌ Removed project: {project}')
except Exception as e:
    print(f'Error removing project: {e}')
"
    refresh_swiftbar
}

# 列出所有项目状态
list_projects() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "📂 No projects found. Create status first."
        return
    fi

    python3 -c "
import json
from datetime import datetime

config_file = '$CONFIG_FILE'

try:
    with open(config_file, 'r') as f:
        config = json.load(f)

    if not config['projects']:
        print('📂 No active projects')
        exit(0)

    print('📊 Active Projects:')
    print('=' * 50)

    for p in config['projects']:
        status_icon = {
            'executing': '⚡️',
            'waiting_confirmation': '⏸',
            'completed': '✅',
            'error': '❌',
            'idle': '💤'
        }.get(p['status'], '❓')

        print(f'{status_icon} {p[\"project\"]} - {p[\"status\"]}')

        # 计算时间差
        try:
            timestamp = datetime.fromisoformat(p['timestamp'].replace('Z', '+00:00'))
            now = datetime.now(timestamp.tzinfo)
            diff = now - timestamp

            if diff.total_seconds() < 60:
                time_str = 'just now'
            elif diff.total_seconds() < 3600:
                time_str = f'{int(diff.total_seconds() / 60)}m ago'
            elif diff.total_seconds() < 86400:
                time_str = f'{int(diff.total_seconds() / 3600)}h ago'
            else:
                time_str = f'{int(diff.total_seconds() / 86400)}d ago'

            print(f'   Updated: {time_str}')
        except:
            print(f'   Updated: {p[\"timestamp\"]}')

        if p.get('command'):
            print(f'   Command: {p[\"command\"]}')
        print()

except Exception as e:
    print(f'Error reading projects: {e}')
"
}

# 显示帮助信息
show_help() {
    echo "Claude Status Updater"
    echo "Usage: $0 [COMMAND] [PROJECT_NAME] [EXTRA_ARGS]"
    echo ""
    echo "Commands:"
    echo "  executing [PROJECT] [COMMAND]    - Set status to executing"
    echo "  waiting [PROJECT] [COMMAND]      - Set status to waiting for confirmation"
    echo "  completed [PROJECT]              - Set status to completed"
    echo "  error [PROJECT] [ERROR_MSG]      - Set status to error"
    echo "  idle [PROJECT]                   - Set status to idle"
    echo "  remove [PROJECT]                 - Remove project from status"
    echo "  list                            - List all projects"
    echo "  refresh                         - Refresh SwiftBar display"
    echo "  help                            - Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 executing my-project 'claude help with ui'"
    echo "  $0 waiting my-project"
    echo "  $0 completed"
    echo "  $0 list"
    echo ""
    echo "If PROJECT_NAME is not provided, current directory name is used"
}

# 主程序
main() {
    local command="$1"
    local project="$2"
    local extra_arg="$3"

    case "$command" in
        "executing"|"exec")
            set_executing "$project" "$extra_arg"
            ;;
        "waiting"|"wait")
            set_waiting "$project" "$extra_arg"
            ;;
        "completed"|"done")
            set_completed "$project"
            ;;
        "error"|"err")
            set_error "$project" "$extra_arg"
            ;;
        "idle")
            set_idle "$project"
            ;;
        "remove"|"rm")
            remove_project "$project"
            ;;
        "list"|"ls")
            list_projects
            ;;
        "refresh")
            refresh_swiftbar
            echo "🔄 SwiftBar refreshed"
            ;;
        "help"|"-h"|"--help"|"")
            show_help
            ;;
        *)
            echo "❌ Unknown command: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# 运行主程序
main "$@"