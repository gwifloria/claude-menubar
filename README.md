# Claude Menubar

A macOS menubar application that monitors Claude AI sessions and displays their status in real-time.

## Features

- **Real-time Status Monitoring**: Tracks Claude AI processes and displays current status
- **Visual Status Indicators**:
  - ⚡️ Processing/Executing (spinning animation)
  - ✏️ User Input (gentle flashing every minute for vibe coding)
  - ✅ Completed
  - 💤 Idle/No active sessions
- **Project-based Display**: Shows individual project names with their status instead of merged counters
- **SwiftBar Integration**: Native macOS menubar plugin with automatic updates
- **Background Monitoring**: Automatic process detection and status updates

## Installation

1. Install [SwiftBar](https://swiftbar.app/) if you haven't already:
   ```bash
   brew install --cask swiftbar
   ```

2. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/claude-menubar.git
   cd claude-menubar
   ```

3. Run the installation script:
   ```bash
   chmod +x bin/install.sh
   ./bin/install.sh
   ```

## Usage

Once installed, the application runs automatically in the background:

- The menubar will show active Claude sessions with their status icons and project names
- ✏️ icons will gently flash every minute when waiting for user input (perfect for vibe coding)
- Click on any project to see detailed information and quick actions
- Use `bin/restart.sh` to restart all services
- Use `bin/stop.sh` to stop monitoring

## Commands

```bash
# Service management
bin/restart.sh                 # Restart all services and refresh plugin
bin/restart.sh --status       # Show current service status
bin/restart.sh --logs         # View recent logs
bin/stop.sh                   # Stop all monitoring services

# Manual status updates (optional)
config/status-updater.sh executing "project-name"
config/status-updater.sh completed "project-name"
config/status-updater.sh idle "project-name"
```

## Project Structure

```
claude-menubar/
├── bin/                      # Executable scripts
│   ├── install.sh           # Installation script
│   ├── restart.sh          # Restart services
│   └── stop.sh            # Stop services
├── lib/                     # Core library files
│   ├── monitor.sh          # Background monitoring script
│   └── swiftbar-plugin.swift # SwiftBar menubar plugin
└── config/                  # Configuration and utilities
    └── status-updater.sh   # Manual status update tool
```

## Status Types

- **executing**: Claude is actively processing (⚡️ with spinning animation)
- **user_input**: Waiting for user input (✏️ with gentle 1-minute flashing)
- **waiting_confirmation**: Needs user attention (✏️)
- **completed**: Task completed (✅)
- **idle**: No active processing (💤)
- **error**: Error occurred (❌)

## Configuration

The application stores status in `~/.claude-swift/status-config.json`:

```json
{
  "projects": [
    {
      "project": "my-project",
      "status": "executing",
      "timestamp": "2025-09-19T01:00:00.000Z",
      "command": "PID:12345"
    }
  ],
  "lastUpdate": "2025-09-19T01:00:00.000Z"
}
```

## Troubleshooting

**Menubar not showing**: Restart SwiftBar with `bin/restart.sh`

**Status not updating**: Check background service with `bin/restart.sh --status`

**View logs**: Use `bin/restart.sh --logs` to see recent activity

## Requirements

- macOS 10.15+
- SwiftBar application
- Swift runtime (included with macOS)

## License

MIT License - see LICENSE file for details.