# Orbit

A macOS menubar app for managing development environment port forwarding with loopback interface aliases.

## Why Orbit?

Run multiple services on the same ports using different loopback IPs (127.0.x.x). Useful for:
- Multiple microservices that all want port 8080
- Kubernetes port-forwards to predictable local addresses
- SSH tunnels to remote databases

## Install

Download the latest DMG from [Releases](https://github.com/SimonRen/orbit/releases), or build from source:

```bash
brew install xcodegen
git clone https://github.com/SimonRen/orbit.git && cd orbit
xcodegen generate
xcodebuild -scheme orbit -configuration Release build
```

## Quick Start

1. Create an environment with interface IPs (e.g., `127.0.0.2`)
2. Add services using `$IP` variable in commands:
   ```bash
   kubectl port-forward --address $IP svc/my-service 8080:8080
   ssh -N -L $IP:5432:db.internal:5432 user@bastion
   ```
3. Toggle environment on/off from menubar or main window

## orb-kubectl

Orbit includes an optional `orb-kubectl` tool - a custom kubectl build with **retry support** for port-forwarding.

### Install

**Orbit menu → Install orb-kubectl...**

The binary is downloaded to `~/Library/Application Support/Orbit/bin/` and automatically available in PATH for all services.

### Usage

Use `orb-kubectl` instead of `kubectl` in your service commands:

```bash
orb-kubectl port-forward --address $IP svc/my-service 8080:8080 --retry
```

### Update

When a new version is available, the menu will show **"Update orb-kubectl..."**. Updates are tied to Orbit releases.

## Requirements

- macOS 13.0+
- Admin password on first run (installs privileged helper for network config)

## License

MIT
