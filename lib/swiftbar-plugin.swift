#!/usr/bin/swift

import Foundation
import AppKit

struct ClaudeStatus: Codable {
    let project: String
    let status: String
    let timestamp: Date
    let command: String?
}

struct StatusConfig: Codable {
    let projects: [ClaudeStatus]
    let lastUpdate: Date
}

class ClaudeSwiftBarPlugin {
    private let configPath = "\(NSHomeDirectory())/.claude-swift/status-config.json"

    func main() {
        let statusConfig = loadStatus()
        let output = generateMenuBarOutput(for: statusConfig)
        print(output)
    }

    private func loadStatus() -> StatusConfig {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)) else {
            return StatusConfig(projects: [], lastUpdate: Date())
        }

        let decoder = JSONDecoder()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        decoder.dateDecodingStrategy = .formatted(formatter)

        guard let config = try? decoder.decode(StatusConfig.self, from: data) else {
            return StatusConfig(projects: [], lastUpdate: Date())
        }
        return config
    }

    private func generateMenuBarOutput(for config: StatusConfig) -> String {
        var output = ""

        // 主状态显示 - 直接显示项目名称和状态图标
        // 检查是否有活跃状态的项目
        let hasActiveProjects = config.projects.contains { project in
            let status = project.status
            return status == "executing" || status == "waiting_confirmation" || status == "user_input"
        }

        if config.projects.isEmpty || !hasActiveProjects {
            output += "💤"  // 没有项目或都是idle/completed状态时显示
        } else {
            // 只显示活跃状态的项目，并按状态重要性排序
            let activeProjects = config.projects.filter { project in
                let status = project.status
                return status == "executing" || status == "waiting_confirmation" || status == "user_input"
            }

            let sortedProjects = activeProjects.sorted { project1, project2 in
                let priority1 = getStatusPriority(project1.status)
                let priority2 = getStatusPriority(project2.status)

                if priority1 != priority2 {
                    return priority1 < priority2  // 数字小的优先级高
                } else {
                    return project1.timestamp > project2.timestamp  // 时间新的在前
                }
            }

            // 生成菜单栏标题 - 显示项目名称和状态
            var menuBarItems: [String] = []
            let maxDisplayProjects = 3  // 最多显示3个项目

            for (index, project) in sortedProjects.enumerated() {
                if index >= maxDisplayProjects {
                    break
                }

                let icon = getStatusIcon(project.status)
                let projectName = truncateProjectName(project.project, maxLength: 12)
                menuBarItems.append("\(icon)\(projectName)")
            }

            // 如果还有更多项目未显示
            if sortedProjects.count > maxDisplayProjects {
                let remainingCount = sortedProjects.count - maxDisplayProjects
                menuBarItems.append("+\(remainingCount)")
            }

            output += menuBarItems.joined(separator: " ")
        }

        output += "\n---\n"

        // 直接显示所有项目，不分类
        if config.projects.isEmpty {
            output += "No Claude Sessions | color=gray\n"
        } else {
            // 按状态重要性和时间排序
            let sortedProjects = config.projects.sorted { project1, project2 in
                let priority1 = getStatusPriority(project1.status)
                let priority2 = getStatusPriority(project2.status)

                if priority1 != priority2 {
                    return priority1 < priority2  // 数字小的优先级高
                } else {
                    return project1.timestamp > project2.timestamp  // 时间新的在前
                }
            }

            for project in sortedProjects {
                output += addProjectMenuItem(project: project)
            }
        }

        output += "---\n"
        // 操作菜单
        output += "🔄 Refresh All | refresh=true\n"
        output += "⚙️ Open Config | bash=open param1=\(configPath.replacingOccurrences(of: " ", with: "\\ "))\n"
        output += "📊 Process Detection Test | bash=\(getProcessTestCommand())\n"

        return output
    }

    private func addProjectMenuItem(project: ClaudeStatus) -> String {
        let icon = getStatusIcon(project.status)
        let timeAgo = getTimeAgo(project.timestamp)
        let statusText = getStatusText(project.status)
        let statusColor = getStatusColor(project.status)

        var menuItem = "\(icon) \(project.project) | submenu=true\n"
        menuItem += "--Status: \(statusText) | color=\(statusColor)\n"
        menuItem += "--Updated: \(timeAgo)\n"

        if let command = project.command {
            let truncatedCommand = String(command.prefix(50))
            menuItem += "--Info: \(truncatedCommand) | color=gray font=Monaco\n"
        }

        menuItem += "-----\n"
        menuItem += "--🔄 Refresh | refresh=true\n"
        menuItem += "--Mark Completed | bash=\(getMarkCompletedCommand(project.project))\n"
        menuItem += "--Mark Idle | bash=\(getMarkIdleCommand(project.project))\n"

        return menuItem
    }

    private func getStatusPriority(_ status: String) -> Int {
        switch status {
        case "waiting_confirmation": return 1  // 最高优先级 - 需要用户注意
        case "executing": return 2             // 第二优先级 - 正在处理
        case "user_input": return 3            // 第三优先级 - 用户输入中
        case "error": return 4                 // 第四优先级 - 错误状态
        case "completed": return 5             // 较低优先级 - 已完成
        case "idle": return 6                  // 最低优先级 - 闲置
        default: return 7
        }
    }

    private func getMarkCompletedCommand(_ project: String) -> String {
        return "\(getScriptPath())/status-updater.sh completed \"\(project)\""
    }

    private func getMarkIdleCommand(_ project: String) -> String {
        return "\(getScriptPath())/status-updater.sh idle \"\(project)\""
    }

    private func getScriptPath() -> String {
        // 假设脚本在 ~/wonderland/claude-swift/scripts 目录
        return "\(NSHomeDirectory())/wonderland/claude-swift/scripts"
    }

    private func addProjectSubmenu(project: ClaudeStatus, isSubItem: Bool) -> String {
        let prefix = isSubItem ? "--" : ""
        let icon = getStatusIcon(project.status)
        let timeAgo = getTimeAgo(project.timestamp)
        let statusText = getStatusText(project.status)

        var submenu = "\(prefix)\(icon) \(project.project) | submenu=true\n"
        submenu += "\(prefix)--Status: \(statusText) | color=\(getStatusColor(project.status))\n"
        submenu += "\(prefix)--Updated: \(timeAgo)\n"

        if let command = project.command {
            let truncatedCommand = String(command.prefix(50))
            submenu += "\(prefix)--Info: \(truncatedCommand) | color=gray font=Monaco\n"
        }

        submenu += "\(prefix)-----\n"
        submenu += "\(prefix)--🔄 Refresh | refresh=true\n"

        return submenu
    }

    private func getProcessTestCommand() -> String {
        // 返回进程检测测试命令
        return "/bin/bash -c 'ps aux | grep -E \" claude$|/claude$\" | grep -v \"Claude.app\" | grep -v grep'"
    }

    private func getMainStatusIcon(_ projects: [ClaudeStatus]) -> String {
        let hasExecuting = projects.contains { $0.status == "executing" }
        let hasWaiting = projects.contains { $0.status == "waiting_confirmation" }
        let hasError = projects.contains { $0.status == "error" }

        if hasExecuting {
            return "⚡️"  // 执行中
        } else if hasWaiting {
            return "⏸"   // 等待确认
        } else if hasError {
            return "❌"   // 错误
        } else if !projects.isEmpty {
            return "✅"   // 完成
        } else {
            return "💤"   // 闲置
        }
    }

    private func getStatusIcon(_ status: String) -> String {
        switch status {
        case "executing":
            return getLoadingIcon()  // 动态Loading图标
        case "waiting_confirmation":
            return getAttentionIcon()  // 跳动的通知图标
        case "user_input":
            return "✏️"  // 静态输入图标
        case "completed":
            return "✅"
        case "error":
            return "❌"
        case "idle":
            return "💤"
        default:
            return "❓"
        }
    }

    private func getLoadingIcon() -> String {
        // 基于当前时间生成循环动画
        let spinner = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
        let index = Int(Date().timeIntervalSince1970) % spinner.count
        return spinner[index]
    }

    private func getAttentionIcon() -> String {
        // 长间隔温和闪烁的输入图标
        let currentTime = Int(Date().timeIntervalSince1970)
        let cycle = currentTime % 60  // 每60秒一个周期

        if cycle < 3 {
            // 前3秒快速闪烁2次
            return cycle % 2 == 0 ? "✏️" : "📝"
        } else {
            // 后57秒静止显示
            return "✏️"
        }
    }

    private func getStatusText(_ status: String) -> String {
        switch status {
        case "executing":
            return "Processing..."  // 更动感的文本
        case "waiting_confirmation":
            return "⚠️ NEEDS ATTENTION"  // 醒目的提示
        case "user_input":
            return "Typing..."  // 用户输入中
        case "completed":
            return "Completed"
        case "error":
            return "Error"
        case "idle":
            return "Idle"
        default:
            return "Unknown"
        }
    }

    private func getStatusColor(_ status: String) -> String {
        switch status {
        case "executing":
            return "orange"
        case "waiting_confirmation":
            return "red"  // 改为红色，更醒目
        case "user_input":
            return "blue"  // 蓝色表示用户输入
        case "completed":
            return "green"
        case "error":
            return "red"
        case "idle":
            return "gray"
        default:
            return "black"
        }
    }

    private func getTimeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }

    private func truncateProjectName(_ name: String, maxLength: Int) -> String {
        if name.count <= maxLength {
            return name
        }
        let endIndex = name.index(name.startIndex, offsetBy: maxLength - 1)
        return String(name[..<endIndex]) + "…"
    }
}

// 创建实例并运行
let plugin = ClaudeSwiftBarPlugin()
plugin.main()