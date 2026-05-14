# Contributing to Orbit

Thanks for your interest in contributing! Orbit is a small macOS app and the codebase is approachable — most contributions only need Xcode and a few minutes of setup.

## Quick Links

- **Bug?** → [Open an issue](https://github.com/simonren/orbit/issues/new?template=bug_report.md)
- **Idea?** → [Feature request](https://github.com/simonren/orbit/issues/new?template=feature_request.md)
- **Security issue?** → [SECURITY.md](SECURITY.md) — do *not* file a public issue
- **Code of Conduct** → [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)

## Prerequisites

- macOS 13.0 or later
- Xcode 15+ (matching Command Line Tools)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

That's it. The Xcode project file (`orbit.xcodeproj/`) is generated and **not** checked in — run `xcodegen generate` once after cloning.

## Building

```bash
git clone https://github.com/simonren/orbit.git
cd orbit
xcodegen generate

make build         # Debug build (default)
make run           # Build and launch
make test          # Run the unit test suite
make release       # Release build with signing
make help          # All targets
```

## Code Signing for Contributors

Orbit's official releases are signed with Simon's Apple Developer team (`DN4YAHWP2P`). If you're building from a fork with your own team ID, you have two options:

### Option 1 — Build without signing (simplest)

Most development and testing doesn't require a working signature:

```bash
xcodebuild -project orbit.xcodeproj -scheme orbit \
  -configuration Debug build \
  CODE_SIGNING_ALLOWED=NO
```

The unit-test target works the same way:

```bash
xcodebuild -project orbit.xcodeproj -scheme orbit test \
  CODE_SIGNING_ALLOWED=NO
```

CI uses this approach.

### Option 2 — Build with your own team ID

Create `Config/Project.local.xcconfig` (gitignored) with your team:

```
DEVELOPMENT_TEAM = YOURTEAMID
CODE_SIGN_IDENTITY = Apple Development
```

That's enough for a normal Debug build. **However**, exercising the privileged helper (network alias installation, SMJobBless) also requires changing the team ID in three security-critical places, because the helper validates the calling app's signature:

| File | What to change |
|------|----------------|
| `orbit/Resources/Info.plist` | `SMPrivilegedExecutables` requirement string — replace `DN4YAHWP2P` with yours |
| `orbitHelper/Info.plist` | `SMAuthorizedClients` requirement string — replace `DN4YAHWP2P` with yours |
| `orbitHelper/main.swift` | `codeSigningRequirement` string — replace `DN4YAHWP2P` with yours |

**Do not commit those changes.** They are part of the on-the-wire identity of the official Orbit binary; changing them in the public repo would break auto-update for everyone who's already installed Orbit.

## Code Style

- Swift 5.9, follow the surrounding code's conventions
- Logging: `os.Logger(subsystem: "com.orbit.app", category: "ClassName")` — never `print()` or `NSLog`
- Validation: all IP/port/name validation goes through `ValidationService` (single source of truth)
- Tests: write them when fixing a bug or adding a feature
- Comments: explain *why*, not *what* — let names do the work for *what*

## Commit & PR Conventions

- **Commits**: imperative subject ≤72 chars; body explains *why* and any non-obvious tradeoffs. One logical change per commit.
- **PRs**: open against `main`. Reference an issue when relevant. Keep diffs focused — refactors and feature work in the same PR are harder to review.
- **Before opening a PR**:
  - `make test` passes
  - `make release` builds successfully (if your change touches build settings or signing)

## What's in scope

Good fits:
- Bug fixes
- Quality-of-life features (keyboard shortcuts, UI polish, better error messages)
- Performance improvements with measurable wins
- Documentation
- Test coverage

Discuss before starting:
- Large refactors (e.g., splitting `AppState.swift`)
- New top-level features
- Changes to the privileged helper protocol — security review needed
- Changes to the release pipeline or auto-update mechanism

## Project Layout

```
orbit/                # Main app source
  App/                # @main entry, AppDelegate
  Models/             # Codable data types
  Services/           # XPC, config, process, network, validation, updater
  ViewModels/         # AppState (the central ObservableObject)
  Views/              # SwiftUI windows, sheets, components
  Utilities/          # VariableResolver, etc.
  Resources/          # Info.plist, entitlements, assets
orbitHelper/          # Privileged XPC service (runs as root)
orbitTests/           # Unit tests
docs/                 # GitHub Pages site, appcast.xml, release notes
scripts/              # Release automation
project.yml           # XcodeGen spec — single source of truth for the Xcode project
```

For deeper architecture notes, see [CLAUDE.md](CLAUDE.md).

## Releases

Releases are cut by the maintainer. The flow:

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`
2. Run `./scripts/release.sh <version>` (builds, signs, notarizes, uploads to appcast)
3. Write release notes in `docs/release-notes/<version>.html`
4. Tag and push

Contributors don't need to touch this — the maintainer handles it.

## Questions

Open a [discussion](https://github.com/simonren/orbit/discussions) or drop a comment on a related issue. Thank you for helping make Orbit better!
