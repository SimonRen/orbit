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
# Automated release (builds, notarizes, creates DMG, signs for Sparkle, updates appcast)
./scripts/release.sh 0.x.x

# After release script completes:
# 1. Edit docs/release-notes/0.x.x.html
# 2. git add docs/ && git commit -m "Release v0.x.x"
# 3. git tag v0.x.x && git push origin main --tags
# 4. gh release create v0.x.x releases/Orbit-v0.x.x.dmg
```

Credentials stored in Keychain:
- Notarization profile: "notary"
- Sparkle EdDSA key: "Sparkle Private Key" (auto-created by `generate_keys`)

## Auto-Update System

Orbit uses [Sparkle](https://sparkle-project.org/) for automatic updates.

### Components

| Component | Location | Purpose |
|-----------|----------|---------|
| UpdaterManager | `orbit/Services/UpdaterManager.swift` | Sparkle wrapper singleton |
| Appcast | `docs/appcast.xml` | Update feed (hosted on GitHub Pages) |
| Release Notes | `docs/release-notes/*.html` | Per-version release notes |
| SUFeedURL | `Info.plist` | Points to `https://simonren.github.io/orbit/appcast.xml` |

### First-Time Setup (One-Time)

```bash
# After building once to download Sparkle, generate EdDSA keys:
SPARKLE_BIN=$(find ~/Library/Developer/Xcode/DerivedData/orbit-*/SourcePackages/artifacts/sparkle/Sparkle/bin -maxdepth 0 2>/dev/null | head -1)
"${SPARKLE_BIN}/generate_keys"

# This:
# 1. Creates private key in Keychain (never share!)
# 2. Prints public key - copy to Info.plist SUPublicEDKey
```

### How Updates Work

1. App checks `appcast.xml` on startup (and daily)
2. Sparkle compares `sparkle:version` with app's `CFBundleShortVersionString`
3. If newer version found, shows update dialog with release notes
4. User clicks "Install Update" → downloads DMG → verifies EdDSA signature → replaces app

### GitHub Pages Setup

1. Repo Settings → Pages → Source: Deploy from branch
2. Branch: `main`, Folder: `/docs`
3. URL: `https://simonren.github.io/orbit/`

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
