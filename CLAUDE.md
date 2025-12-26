# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

This project uses XcodeGen to generate the Xcode project from `project.yml`:

```bash
# Generate Xcode project (required after adding/removing files or modifying project.yml)
xcodegen generate

# Build (Debug)
xcodebuild -project orbit.xcodeproj -scheme orbit -configuration Debug build

# Build (Release)
xcodebuild -project orbit.xcodeproj -scheme orbit -configuration Release build

# Run all tests
xcodebuild -project orbit.xcodeproj -scheme orbit test

# Run a single test
xcodebuild -project orbit.xcodeproj -scheme orbit test -only-testing:orbitTests/OrbitTests/testValidIPFormat

# Build and relaunch
pkill -f "Orbit.app"; open ~/Library/Developer/Xcode/DerivedData/orbit-*/Build/Products/Debug/Orbit.app
```

The `*.xcodeproj` is gitignored - always regenerate with `xcodegen generate`.

## Build Configurations

| Config | Purpose | Key Settings |
|--------|---------|--------------|
| **Debug** | Development | `CODE_SIGN_INJECT_BASE_ENTITLEMENTS: YES` (allows debugger) |
| **Release** | Distribution | `CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO` + `--timestamp` (notarization-ready) |

## Release Process

```bash
# Automated release (builds, notarizes, creates DMG)
./scripts/release.sh 0.x.x

# Or manually:
xcodebuild -project orbit.xcodeproj -scheme orbit -configuration Release clean build
xcrun notarytool submit Orbit.zip --keychain-profile "notary" --wait
xcrun stapler staple Orbit.app
```

Notarization credentials are stored in Keychain as profile "notary".

## Architecture Overview

Orbit is a macOS SwiftUI app for managing development environment port forwarding. It allows users to:
- Define environments with loopback interface aliases (127.0.x.x)
- Configure services that run commands with variable substitution ($IP, $IP2, etc.)
- Toggle environments on/off from both the main window and menubar

### Source Structure

- `orbit/` - Main app source (SwiftUI views, models, services)
- `orbitHelper/` - Privileged helper daemon (runs as root via XPC)
- `orbitTests/` - Unit tests

### Key Components

**Privileged Helper (`orbitHelper/`)**: XPC service running as root to manage network interface aliases without repeated password prompts. Installed via SMJobBless on first use. The helper binary is embedded in the app bundle at `Contents/Library/LaunchServices/com.orbit.helper`.

**AppState (`orbit/ViewModels/AppState.swift`)**: Central ObservableObject holding all application state. Manages:
- Environment/service CRUD operations
- Activation/deactivation with transition state tracking
- Toggle cooldown (500ms) to prevent rapid clicks
- Process lifecycle coordination
- Import/export of environment configurations

**ProcessManager (`orbit/Services/ProcessManager.swift`)**: Spawns and monitors service processes. Kills entire process tree on stop using `pgrep -P` to find child processes recursively.

**NetworkManager (`orbit/Services/NetworkManager.swift`)**: Communicates with the privileged helper via XPC to add/remove interface aliases.

**WindowCoordinator (`orbit/App/OrbitApp.swift`)**: Singleton for cross-window communication. Provides closures to open main window, log windows, and trigger import dialogs from anywhere (e.g., menubar).

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

### Import/Export

Environments can be exported to `.orbit.json` files and imported back. Export includes environment name, interfaces, and services. Import auto-detects name/IP conflicts and suggests resolutions.

### Configuration

Persisted to `~/Library/Application Support/Orbit/config.json`. Runtime state (isEnabled, isTransitioning, service status, logs) is not persisted.
