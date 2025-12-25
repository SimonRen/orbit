# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

This project uses XcodeGen to generate the Xcode project from `project.yml`:

```bash
# Generate Xcode project (required after adding/removing files)
xcodegen generate

# Build the app
xcodebuild -project devfwd.xcodeproj -scheme devfwd -configuration Debug build

# Run tests
xcodebuild -project devfwd.xcodeproj -scheme devfwd test

# Relaunch app after build
pkill -f "devfwd.app"; open ~/Library/Developer/Xcode/DerivedData/devfwd-*/Build/Products/Debug/devfwd.app
```

The generated `*.xcodeproj` is gitignored - always regenerate with `xcodegen generate`.

## Architecture Overview

DEV Fwd is a macOS SwiftUI app for managing development environment port forwarding. It allows users to:
- Define environments with loopback interface aliases (127.0.x.x)
- Configure services that run commands with variable substitution ($IP, $IP2, etc.)
- Toggle environments on/off from both the main window and menubar

### Key Components

**Privileged Helper (`devfwdHelper/`)**: A separate XPC service that runs as root to manage network interface aliases without repeated password prompts. Installed via SMJobBless on first use.

**AppState (`ViewModels/AppState.swift`)**: Central ObservableObject holding all application state. Manages:
- Environment/service CRUD operations
- Activation/deactivation with transition state tracking
- Toggle cooldown (500ms) to prevent rapid clicks
- Process lifecycle coordination

**ProcessManager (`Services/ProcessManager.swift`)**: Spawns and monitors service processes. Key behavior:
- Kills entire process tree on stop (not just parent bash)
- Uses `pgrep -P` to find child processes recursively

**NetworkManager (`Services/NetworkManager.swift`)**: Communicates with the privileged helper via XPC to add/remove interface aliases.

### Data Flow

1. User toggles environment → `AppState.toggleEnvironment()`
2. Sets `environment.isTransitioning = true`
3. NetworkManager adds interface aliases via XPC to helper
4. ProcessManager spawns enabled services with resolved commands
5. Sets `environment.isEnabled = true`, clears transitioning

### Variable Substitution

Commands use `$IP`, `$IP2`, `$IP3` etc. which resolve to the environment's interface IPs:
- `interfaces[0]` → `$IP`
- `interfaces[1]` → `$IP2`
- `interfaces[n]` → `$IP{n+1}`

### Configuration

Persisted to `~/Library/Application Support/DEV Fwd/config.json`. Runtime state (isEnabled, isTransitioning, service status, logs) is not persisted.
