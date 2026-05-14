# Orbit

> A macOS menubar app for managing development-environment port forwarding with loopback interface aliases.

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-13.0%2B-lightgrey.svg)](#requirements)
[![Release](https://img.shields.io/github/v/release/simonren/orbit)](https://github.com/simonren/orbit/releases/latest)
[![Build](https://github.com/simonren/orbit/actions/workflows/ci.yml/badge.svg)](https://github.com/simonren/orbit/actions/workflows/ci.yml)

<!-- Screenshot placeholder: add docs/screenshots/hero.png and uncomment.
<p align="center">
  <img src="docs/screenshots/hero.png" alt="Orbit screenshot" width="720"/>
</p>
-->

## Why Orbit?

Run multiple services on the same port using different loopback IPs (`127.0.x.x`), each tied to a named environment you can toggle on and off from the menubar.

Useful for:

- Multiple microservices that all want port 8080
- Kubernetes `port-forward`s to predictable local addresses
- SSH tunnels to remote databases
- Switching between dev/staging/prod-mirror stacks without port collisions

## Features

- **Environments** — group related services under a name; each has one or more loopback IPs
- **One-click toggle** — menubar or main window; activates network aliases and spawns service processes
- **Variable substitution** — use `$IP`, `$IP2`, … in commands; resolved per-environment
- **Service logs** — capture stdout/stderr per service, view in a dedicated window
- **Import / Export** — share environments via `.orbit.json`; bulk archives as dated `.orbit.zip`
- **K8s import** — pick a context/namespace and import services as `kubectl port-forward` commands
- **Auto-update** — Sparkle delivers signed, notarized updates from the public appcast
- **Crash-safe** — privileged XPC helper monitors the app and cleans up orphaned process groups

## Install

### Download (recommended)

Grab the latest DMG from [**Releases**](https://github.com/simonren/orbit/releases/latest). Universal binary (Apple Silicon + Intel), signed, notarized.

### Build from source

```bash
brew install xcodegen
git clone https://github.com/simonren/orbit.git
cd orbit
xcodegen generate
make build         # Debug build
make release       # Release build with signing
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for details, especially if you don't have an Apple Developer team ID matching the default.

## Quick Start

1. Create an environment with interface IPs (e.g., `127.0.0.2`)
2. Add services using the `$IP` variable in commands:
   ```bash
   kubectl port-forward --address $IP svc/my-service 8080:8080
   ssh -N -L $IP:5432:db.internal:5432 user@bastion
   ```
3. Toggle the environment on/off from the menubar or main window

## orb-kubectl

Orbit ships an optional `orb-kubectl` — a custom kubectl build with **retry support** for port-forwarding (auto-reconnects on transient failures).

- **Install**: *Orbit menu → Settings → Tools → Install...* — you'll see a trust dialog showing the source repo (`github.com/simonren/kubernetes`, branch `feature/resilient-port-forward`), expected SHA-256, and where the binary gets installed. You can decline and stick with plain `kubectl` from your `$PATH`.
- **Use**: substitute `orb-kubectl` for `kubectl` in any service command, then add `--retry`:
  ```bash
  orb-kubectl port-forward --address $IP svc/my-service 8080:8080 --retry
  ```
- Installed to `~/Library/Application Support/Orbit/bin/` and automatically on `PATH` for spawned services.

## Requirements

- macOS 13.0 or later
- Optional: admin password once, if you let Orbit install a privileged helper to manage `lo0` aliases automatically. You can decline at first-run and manage the aliases yourself with `sudo ifconfig` — see [Network & Helper](#how-it-works) below.

## How it works

Orbit installs a small privileged XPC helper (`com.orbit.helper`) via [`SMJobBless`](https://developer.apple.com/documentation/servicemanagement). The helper runs as root and is the only component that touches the network configuration (`ifconfig lo0 alias`). All connections to the helper are verified against Orbit's code signature before being accepted. The helper also monitors Orbit's PID and cleans up any orphaned child processes if Orbit crashes.

The app itself runs unsandboxed (hardened runtime) so it can spawn arbitrary user-defined commands. Service processes are launched in their own process groups for reliable shutdown.

For the full architecture, see [CLAUDE.md](CLAUDE.md).

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a PR — there's a small bit of setup needed because of macOS code-signing.

## Security

To report a vulnerability privately, see [SECURITY.md](SECURITY.md). Please do **not** open public issues for security problems — the app installs a root-level helper, so we want to coordinate disclosure.

## Acknowledgments

Orbit stands on the shoulders of:

- [Sparkle](https://github.com/sparkle-project/Sparkle) — auto-update framework (MIT)
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) — ZIP archive support (MIT)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — Xcode project generator (MIT, dev dependency)

See [NOTICE](NOTICE) for full attribution.

## License

[MIT](LICENSE) © Simon Ren
