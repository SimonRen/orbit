# Security Policy

Orbit installs a privileged helper that runs as root to manage network configuration. We take security reports seriously.

## Reporting a Vulnerability

**Please do not file public GitHub issues for security problems.**

Email **jmulro@gmail.com** with:

- A description of the issue and the impact
- Reproduction steps (proof-of-concept welcome)
- Affected version(s)
- Your name/handle for credit (or "anonymous" — your call)

You'll get an initial reply within 5 business days. We aim to ship a fix within 90 days of receiving a confirmed report and will coordinate disclosure timing with you.

## Scope

In scope:

- **Privileged helper (`com.orbit.helper`)** — XPC service running as root. Anything that lets a non-Orbit process invoke its API, bypass code-signature verification, or escalate privileges beyond `lo0` alias management.
- **Process spawning (`ProcessManager`)** — command injection, environment manipulation, or PATH hijacking that could be triggered via attacker-influenced service definitions.
- **Config/import paths** — malicious `.orbit.json` or `.orbit.zip` payloads that escape their parsing scope (path traversal, arbitrary write).
- **Auto-update (Sparkle)** — anything that lets an attacker substitute a non-genuine update past EdDSA signature validation.

Out of scope:

- Issues that require an already-compromised root account or physical access
- Self-XSS that requires the user to paste attacker-controlled content into their own config
- Missing security headers on `simonren.github.io/orbit/` (the appcast host) — Sparkle validates the EdDSA signature regardless
- Generic clickjacking / UI redress on the GitHub Pages site
- macOS bugs not specific to Orbit (report to Apple)

## Supported Versions

| Version | Supported |
|---------|-----------|
| Latest minor release | ✅ |
| Older versions | ❌ — please update before reporting |

Auto-update is enabled by default; users on outdated versions will see an update prompt within 24 hours.

## Defense-in-Depth Notes

The privileged helper:

- Verifies every connecting client's code signature against a `SecRequirement` matching Orbit's team ID and bundle ID
- Validates that `ifconfig` operations target only `127.x.x.x` (loopback) addresses
- Spawns `/sbin/ifconfig` with an argument array (no shell interpolation)
- Does not write to disk except via `os.log`

The main app:

- Validates user-supplied IPs/ports/names through a single `ValidationService`
- Spawns user commands via `/bin/bash -c` (intentional — users expect shell semantics) inside an isolated process group, so kill-by-group cleanup works reliably
- Receives updates only from a Sparkle appcast hosted on `simonren.github.io` and verified via EdDSA against the public key embedded in `Info.plist`

## Coordinated Disclosure

Once a fix is shipped:

- A CVE is requested if the issue is exploitable in a default configuration
- The release notes credit the reporter (unless they prefer anonymity)
- Details are published in this file's history once users have had reasonable time to update

Thank you for helping keep Orbit users safe.
