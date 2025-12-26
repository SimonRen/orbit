# Orbit

A macOS application for managing development environment port forwarding with loopback interface aliases.

![Main Window](design/main-frame.png)

## Overview

Orbit simplifies local development by allowing you to run multiple services on the same ports using different loopback IP addresses (127.0.x.x). This is particularly useful when:

- Running multiple microservices locally that all want port 8080
- Port-forwarding Kubernetes services to predictable local addresses
- Setting up SSH tunnels to remote databases
- Testing with Docker containers bound to specific IPs

## Features

- **Multiple Environments**: Create separate environments for different projects or contexts
- **Interface Aliases**: Automatically manage loopback interface aliases (127.0.x.x)
- **Variable Substitution**: Use `$IP`, `$IP2`, `$IP3` in commands that resolve to your configured interfaces
- **Service Management**: Start/stop services with automatic process lifecycle management
- **Menubar Integration**: Quick access to toggle environments without opening the main window
- **Real-time Logs**: View service output in dedicated log windows
- **Privileged Helper**: One-time admin authentication for passwordless network configuration

## Screenshots

<details>
<summary>Add Service</summary>

![Add Service](design/add-service.png)

</details>

<details>
<summary>Menubar Menu</summary>

![Menubar](design/menubar.png)

</details>

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15+ (for building from source)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (for project generation)

## Installation

### From Source

```bash
# Clone the repository
git clone https://github.com/SimonRen/orbit.git
cd orbit

# Install XcodeGen if needed
brew install xcodegen

# Generate Xcode project
xcodegen generate

# Build
xcodebuild -project orbit.xcodeproj -scheme orbit -configuration Release build

# The built app is at:
# ~/Library/Developer/Xcode/DerivedData/orbit-*/Build/Products/Release/Orbit.app
```

## Usage

### Creating an Environment

1. Click **"+ New Environment"** in the sidebar
2. Edit the environment name by clicking the pencil icon
3. Configure interface IPs (default: 127.0.0.2)
4. Add services with their startup commands

### Adding a Service

1. Click **"+ Add Service"**
2. Enter service name and ports (for display)
3. Write the command using variables:
   - `$IP` → first interface (e.g., 127.0.0.2)
   - `$IP2` → second interface
   - `$IP3` → third interface, etc.

### Example Commands

**Kubernetes port-forward:**
```bash
kubectl port-forward --address $IP svc/auth-service 8080:8080
```

**SSH tunnel:**
```bash
ssh -N -L $IP:5432:database.internal:5432 user@bastion.example.com
```

**Docker with specific IP:**
```bash
docker run -p $IP:3000:3000 my-service:latest
```

### Activating an Environment

Toggle the switch next to an environment in the sidebar or menubar. On first activation, you'll be prompted to install the privileged helper (one-time admin authentication).

## Configuration

Configuration is stored at:
```
~/Library/Application Support/Orbit/config.json
```

Runtime state (enabled status, service status, logs) is not persisted between app launches.

## Architecture

- **SwiftUI** for the user interface
- **XPC Service** for privileged network operations (interface alias management)
- **SMJobBless** for helper installation with code signing
- Built with **XcodeGen** for reproducible project configuration

## Development

```bash
# Generate project after file changes
xcodegen generate

# Build debug
xcodebuild -project orbit.xcodeproj -scheme orbit -configuration Debug build

# Run tests
xcodebuild -project orbit.xcodeproj -scheme orbit test

# Relaunch after build
pkill -f "Orbit.app"; open ~/Library/Developer/Xcode/DerivedData/orbit-*/Build/Products/Debug/Orbit.app
```

### Build Configurations

| Config | Purpose | Signing | Debugger |
|--------|---------|---------|----------|
| **Debug** | Development | Developer ID | ✅ Allowed |
| **Release** | Distribution | Developer ID + Timestamp | ❌ Disabled |

- **Debug**: Includes `com.apple.security.get-task-allow` entitlement for debugger attachment
- **Release**: No debug entitlements, includes secure timestamp for notarization

## Release Process

### Automated Release (Recommended)

```bash
# Run the release script (builds, notarizes, creates DMG)
./scripts/release.sh 0.3.0
```

This script will:
1. Regenerate Xcode project
2. Build Release configuration
3. Submit to Apple notary service
4. Staple the notarization ticket
5. Create DMG with Applications symlink
6. Notarize and staple the DMG

### Prerequisites for Notarization

1. **Store notarization credentials** (one-time setup):
```bash
xcrun notarytool store-credentials "notary" \
  --key ~/.appstore-keys/AuthKey_XXXXXX.p8 \
  --key-id YOUR_KEY_ID \
  --issuer YOUR_ISSUER_ID
```

2. **Verify credentials**:
```bash
xcrun notarytool history --keychain-profile "notary"
```

### Manual Release

```bash
# 1. Build release
xcodebuild -project orbit.xcodeproj -scheme orbit -configuration Release clean build

# 2. Create ZIP and notarize
cd ~/Library/Developer/Xcode/DerivedData/orbit-*/Build/Products/Release
zip -r Orbit-notarize.zip Orbit.app
xcrun notarytool submit Orbit-notarize.zip --keychain-profile "notary" --wait

# 3. Staple ticket
xcrun stapler staple Orbit.app

# 4. Create DMG
mkdir dmg-staging
cp -R Orbit.app dmg-staging/
ln -s /Applications dmg-staging/Applications
hdiutil create -volname "Orbit" -srcfolder dmg-staging -ov -format UDZO Orbit-vX.X.X.dmg
rm -rf dmg-staging

# 5. Notarize and staple DMG
xcrun notarytool submit Orbit-vX.X.X.dmg --keychain-profile "notary" --wait
xcrun stapler staple Orbit-vX.X.X.dmg
```

### Tagging a Release

```bash
# Create tag
git tag v0.x.x

# Push tag to remote
git push origin v0.x.x
```

### Version History

| Version | Date | Highlights |
|---------|------|------------|
| v0.2.9 | 2025-12-26 | Notarization support, animation fixes, local network permission |
| v0.2.8 | 2025-12-26 | Fix service toggle stuck disabled |
| v0.2.7 | 2025-12-26 | Fix UI freeze when enabling environments |
| v0.2.6 | 2025-12-26 | Interface UP indicator, service filter |
| v0.2.5 | 2025-12-26 | Fix idle CPU usage, helper version checking |
| v0.2.4 | 2025-12-26 | Fix crash on quit |
| v0.2.3 | 2025-12-25 | Icon fixes, performance improvements |
| v0.2 | 2025-12-25 | Import/export, UI improvements |
| v0.1 | 2025-12-24 | Initial release |

## Import/Export

Environments can be exported to `.orbit.json` files and shared with team members.

**Export:** Right-click an environment → Export

**Import:** Click "Import..." button or use File → Import (⌘I)

See [docs/export-format.md](docs/export-format.md) for file format specification.

## License

MIT License - See LICENSE file for details.
