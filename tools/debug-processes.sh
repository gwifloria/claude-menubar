#!/bin/bash

echo "=== 当前Claude进程调试 ==="

echo "1. 所有Claude进程:"
ps aux | grep claude | grep -v grep | awk '$11 == "claude"'

echo ""
echo "2. 进程详细分析:"

ps aux | grep claude | grep -v grep | awk '$11 == "claude"' | while read line; do
    pid=$(echo "$line" | awk '{print $2}')
    stat=$(echo "$line" | awk '{print $8}')

    echo "PID: $pid"
    echo "  Line: $line"
    echo "  Stat: $stat"

    # 获取详细状态
    detailed_stat=$(ps -p $pid -o stat= 2>/dev/null | tr -d ' ')
    echo "  Detailed Stat: $detailed_stat"

    # 获取工作目录
    cwd=$(lsof -p "$pid" 2>/dev/null | grep cwd | awk '{print $NF}' | head -1)
    echo "  CWD: $cwd"

    if [[ -n "$cwd" && "$cwd" != "/" ]]; then
        project_name=$(basename "$cwd")
        echo "  Project: $project_name"

        # 判断状态
        if [[ "$detailed_stat" =~ S.*\+ ]]; then
            echo "  Status: waiting_confirmation"
        elif [[ "$detailed_stat" =~ R.*\+ ]]; then
            echo "  Status: executing"
        else
            echo "  Status: other ($detailed_stat)"
        fi
    fi
    echo "  ---"
done

echo ""
echo "3. 改进的状态判断（结合CPU使用率）:"

ps aux | grep claude | grep -v grep | awk '$11 == "claude"' | while read line; do
    pid=$(echo "$line" | awk '{print $2}')

    # 获取进程状态和CPU使用率
    proc_info=$(ps -p $pid -o stat,pcpu 2>/dev/null | tail -1)
    proc_stat=$(echo "$proc_info" | awk '{print $1}' | tr -d ' ')
    cpu_usage=$(echo "$proc_info" | awk '{print $2}' | tr -d ' ')

    cwd=$(lsof -p "$pid" 2>/dev/null | grep cwd | awk '{print $NF}' | head -1)

    if [[ -n "$cwd" && "$cwd" != "/" ]]; then
        project_name=$(basename "$cwd")

        # CPU使用率转换为整数
        cpu_int=$(echo "$cpu_usage" | cut -d'.' -f1)
        if [[ -z "$cpu_int" ]]; then
            cpu_int=0
        fi

        echo "  $project_name (PID $pid):"
        echo "    Stat: $proc_stat, CPU: $cpu_usage%"

        # 改进的状态判断
        if [[ "$proc_stat" =~ R.*\+ ]]; then
            echo "    Status: executing (运行状态)"
            echo "$project_name:executing:$pid"
        elif [[ "$proc_stat" =~ S.*\+ ]] && [[ "$cpu_int" -gt 5 ]]; then
            echo "    Status: executing (睡眠但高CPU)"
            echo "$project_name:executing:$pid"
        elif [[ "$proc_stat" =~ S.*\+ ]] && [[ "$cpu_int" -le 5 ]]; then
            echo "    Status: waiting_confirmation (睡眠且低CPU)"
            echo "$project_name:waiting_confirmation:$pid"
        else
            echo "    Status: other"
            echo "$project_name:other:$pid"
        fi
        echo ""
    fi
done