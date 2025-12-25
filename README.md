# DEV Fwd

A macOS application for managing development environment port forwarding with loopback interface aliases.

![Main Window](design/main-frame.png)

## Overview

DEV Fwd simplifies local development by allowing you to run multiple services on the same ports using different loopback IP addresses (127.0.x.x). This is particularly useful when:

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
git clone https://github.com/SimonRen/devfwd.git
cd devfwd

# Install XcodeGen if needed
brew install xcodegen

# Generate Xcode project
xcodegen generate

# Build
xcodebuild -project devfwd.xcodeproj -scheme devfwd -configuration Release build

# The built app is at:
# ~/Library/Developer/Xcode/DerivedData/devfwd-*/Build/Products/Release/devfwd.app
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
~/Library/Application Support/DEV Fwd/config.json
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
xcodebuild -project devfwd.xcodeproj -scheme devfwd -configuration Debug build

# Run tests
xcodebuild -project devfwd.xcodeproj -scheme devfwd test
```

## License

MIT License - See LICENSE file for details.
