import Foundation

/// A block of content inside a help article. Rendered structurally by
/// HelpWindowView so we never have to ship a Markdown renderer.
enum HelpBlock: Identifiable {
    case heading(String)
    case paragraph(String)
    case bullets([String])
    case numberedSteps([String])
    case codeBlock(String)
    /// Styled callout. Severity affects color (`.tip` blue, `.warn` yellow, `.danger` red).
    case note(severity: NoteSeverity, String)
    case shortcutTable([(label: String, keys: String)])

    var id: String {
        switch self {
        case .heading(let s):           return "h:\(s)"
        case .paragraph(let s):         return "p:\(s.prefix(40))"
        case .bullets(let xs):          return "b:\(xs.first ?? "")"
        case .numberedSteps(let xs):    return "n:\(xs.first ?? "")"
        case .codeBlock(let s):         return "c:\(s.prefix(40))"
        case .note(_, let s):           return "k:\(s.prefix(40))"
        case .shortcutTable(let xs):    return "s:\(xs.first?.label ?? "")"
        }
    }
}

enum NoteSeverity {
    case tip, warn, danger
}

/// One article, shown as the main pane when its sidebar entry is selected.
struct HelpArticle: Identifiable, Hashable {
    let id: String        // stable slug, e.g. "getting-started"
    let title: String
    /// Used for search (free-text match against title + summary + raw body text).
    let summary: String
    let body: [HelpBlock]

    static func == (lhs: HelpArticle, rhs: HelpArticle) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// A grouping of articles in the sidebar.
struct HelpSection: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let articles: [HelpArticle]
}

// MARK: - Content

enum HelpContent {
    static let sections: [HelpSection] = [
        gettingStartedSection,
        coreConceptsSection,
        kubernetesSection,
        networkSection,
        operationsSection,
        referenceSection,
    ]

    static let allArticles: [HelpArticle] = sections.flatMap { $0.articles }

    /// Free-text search across all articles. Matches title, summary, and raw text body.
    static func search(_ query: String) -> [HelpArticle] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return allArticles }
        return allArticles.filter { article in
            if article.title.lowercased().contains(needle) { return true }
            if article.summary.lowercased().contains(needle) { return true }
            return article.body.contains { block in
                rawText(of: block).lowercased().contains(needle)
            }
        }
    }

    private static func rawText(of block: HelpBlock) -> String {
        switch block {
        case .heading(let s), .paragraph(let s), .codeBlock(let s):
            return s
        case .bullets(let xs), .numberedSteps(let xs):
            return xs.joined(separator: " ")
        case .note(_, let s):
            return s
        case .shortcutTable(let rows):
            return rows.map { "\($0.label) \($0.keys)" }.joined(separator: " ")
        }
    }
}

// MARK: - Sections

extension HelpContent {

    static let gettingStartedSection = HelpSection(
        id: "getting-started",
        title: "Getting Started",
        systemImage: "sparkles",
        articles: [welcomeArticle, firstEnvironmentArticle]
    )

    static let coreConceptsSection = HelpSection(
        id: "core",
        title: "Core Concepts",
        systemImage: "circle.grid.cross",
        articles: [environmentsArticle, servicesArticle, variablesArticle]
    )

    static let kubernetesSection = HelpSection(
        id: "kubernetes",
        title: "Kubernetes",
        systemImage: "shippingbox",
        articles: [k8sImportArticle, orbKubectlArticle]
    )

    static let networkSection = HelpSection(
        id: "network",
        title: "Network & Helper",
        systemImage: "lock.shield",
        articles: [helperArticle, networkModesArticle]
    )

    static let operationsSection = HelpSection(
        id: "operations",
        title: "Operations",
        systemImage: "wrench.and.screwdriver",
        articles: [importExportArticle, settingsArticle, autoUpdateArticle]
    )

    static let referenceSection = HelpSection(
        id: "reference",
        title: "Reference",
        systemImage: "book",
        articles: [shortcutsArticle, troubleshootingArticle, aboutArticle]
    )
}

// MARK: - Articles

extension HelpContent {

    static let welcomeArticle = HelpArticle(
        id: "welcome",
        title: "Welcome to Orbit",
        summary: "What Orbit does, why you might want it, and how to get started in two minutes.",
        body: [
            .paragraph("Orbit is a macOS menubar app for managing port-forwarding setups. It lets you bind multiple services to the same port by giving each its own loopback IP address (127.0.0.x), and toggle whole groups of those services on and off with a single click."),
            .heading("Why use it?"),
            .bullets([
                "Run several microservices that all want port 8080, on the same machine.",
                "Keep predictable local addresses for Kubernetes port-forwards.",
                "Switch between dev / staging / prod-mirror stacks without port collisions.",
                "Open SSH tunnels to remote databases without juggling local ports.",
            ]),
            .heading("The two-minute tour"),
            .numberedSteps([
                "Open Orbit's main window (menubar icon → Show Window).",
                "Create an environment with one or more interface IPs like 127.0.0.2.",
                "Add a service whose command uses the $IP variable, e.g. kubectl port-forward --address $IP svc/my-service 8080:8080.",
                "Toggle the environment on. Orbit aliases the IP on lo0 and spawns the service.",
                "Inspect logs by opening the service's log window. Toggle off to stop everything cleanly.",
            ]),
            .note(severity: .tip, "On first launch Orbit asks if you want to install a small privileged helper that manages loopback aliases automatically. Recommended. See 'Network & Helper' for what that helper does."),
        ]
    )

    static let firstEnvironmentArticle = HelpArticle(
        id: "first-environment",
        title: "Your First Environment",
        summary: "Walk through creating an environment, adding interfaces, and adding a service.",
        body: [
            .heading("1. Create the environment"),
            .paragraph("In the main window, choose New Environment (⌘N) or click the + button in the sidebar. Give it a name like \"dev\" or \"staging-mirror\"."),
            .heading("2. Add an interface IP"),
            .paragraph("Each environment owns one or more loopback IPs in the 127.0.0.x range. The first interface is referenced as $IP in service commands; the second as $IP2; and so on."),
            .bullets([
                "Valid: 127.0.0.2 through 127.255.255.255",
                "Rejected: 127.0.0.1 (that's the system default, not yours to manage)",
                "Each IP must be unique across all of your environments.",
            ]),
            .note(severity: .tip, "Click \"Suggest IP\" in the interface editor and Orbit will pick the next unused 127.0.0.x for you."),
            .heading("3. Add a service"),
            .paragraph("Click Add Service. A service has a name, port list, and a shell command. Use $IP in the command to reference this environment's first interface."),
            .codeBlock("kubectl port-forward --address $IP svc/auth 8080:8080"),
            .heading("4. Toggle on"),
            .paragraph("Flip the toggle in the sidebar (or from the menubar). Orbit aliases the IP on lo0, launches the service, and turns the status dot green when it's healthy. Toggle off and Orbit signals the process group, waits, then force-kills if needed, and removes the alias."),
        ]
    )

    static let environmentsArticle = HelpArticle(
        id: "environments",
        title: "Environments & Interfaces",
        summary: "What an environment is and how its loopback interface IPs are managed.",
        body: [
            .paragraph("An environment is a named group of services that share a set of loopback IP addresses. Activating the environment brings up the IPs on lo0 and starts the enabled services; deactivating tears them back down."),
            .heading("Interfaces"),
            .paragraph("Each environment owns one or more interfaces. An interface is a 127.x.x.x IP and an optional domain pattern."),
            .bullets([
                "The IP is added as an alias on lo0 when the environment activates.",
                "The domain pattern (e.g. *.myapp-dev) is informational unless you've separately wired up local DNS (e.g. dnsmasq) to resolve it to the IP.",
            ]),
            .heading("Why loopback aliases?"),
            .paragraph("Loopback aliases let you bind a server to 127.0.0.2:8080 instead of 0.0.0.0:8080 or 127.0.0.1:8080. Two services can then each use port 8080 without colliding — one on 127.0.0.2:8080, the other on 127.0.0.3:8080. The connection still never leaves your machine."),
            .heading("History"),
            .paragraph("Each environment keeps up to 10 snapshots of past configurations. Use the History button in the detail header to inspect or restore a previous state. Restoring is reversible — the current state becomes a new snapshot."),
        ]
    )

    static let servicesArticle = HelpArticle(
        id: "services",
        title: "Services, Status, and Logs",
        summary: "How services are spawned, monitored, restarted, and logged.",
        body: [
            .paragraph("A service is a shell command that Orbit runs when its environment is active. Services share their environment's interfaces but each has its own process group, log buffer, and on/off toggle."),
            .heading("Status"),
            .bullets([
                "Stopped — not running.",
                "Starting — spawned, not yet declared healthy.",
                "Running — process has stayed up past Orbit's stability window.",
                "Stopping — Orbit is signaling it to exit.",
                "Failed — process exited non-zero or won't stay running.",
            ]),
            .heading("Logs"),
            .paragraph("Orbit captures stdout and stderr per service. Open the log window from a service row to tail output. Logs are kept in memory only — they reset on restart."),
            .heading("Auto-restart"),
            .paragraph("If a running service exits unexpectedly, Orbit restarts it with a progressive backoff: 1s, 2s, 5s, 10s, 15s, 30s, 60s, 120s, 180s, then steady at 180s. If a service stays up for 60 seconds, the restart counter resets."),
            .note(severity: .tip, "If you stop a service intentionally (toggle off or environment off), Orbit suppresses the restart. The auto-restart only fires on unexpected exits."),
            .heading("Process groups & cleanup"),
            .paragraph("Each service runs in its own process group (PGID == PID). On shutdown Orbit sends SIGTERM to the entire group, waits, then sends SIGKILL. If the app crashes, the privileged helper reaps the orphaned groups so you don't end up with zombie kubectl processes."),
        ]
    )

    static let variablesArticle = HelpArticle(
        id: "variables",
        title: "Command Variables ($IP, $IP2, ...)",
        summary: "Substitute environment interface IPs into shell commands.",
        body: [
            .paragraph("A service's command is a shell snippet evaluated by /bin/bash -c. Before execution, Orbit substitutes a small set of variables that reference the environment's interfaces."),
            .heading("The variables"),
            .bullets([
                "$IP  — the first interface's IP",
                "$IP2 — the second interface's IP",
                "$IP3, $IP4, ... — the Nth interface's IP",
            ]),
            .paragraph("If an environment only has one interface, $IP2 will remain literal in the command. Add another interface to give it a value."),
            .heading("Example: multiple bindings"),
            .codeBlock("ssh -N \\\n  -L $IP:5432:db.internal:5432 \\\n  -L $IP2:6379:cache.internal:6379 \\\n  user@bastion"),
            .note(severity: .warn, "$IP matches greedily but stops at digit boundaries. $IPADDR is not substituted (that's a different variable name). $IP10 is fine — it resolves the 10th interface IP."),
        ]
    )

    static let k8sImportArticle = HelpArticle(
        id: "k8s-import",
        title: "Kubernetes Service Import",
        summary: "Pick services from a live cluster and turn them into ready-to-run port-forwards.",
        body: [
            .paragraph("Orbit can talk to your local kubectl, list services in any context + namespace, and turn the ones you pick into kubectl port-forward services in the current environment — auto-generating names, ports, and commands."),
            .heading("Open it"),
            .paragraph("In the detail view, click \"Import from K8s\". A sheet opens with a context picker, a namespace list, and a service list."),
            .heading("Pick + import"),
            .numberedSteps([
                "Choose the kubectl context (defaults to your current context).",
                "Pick a namespace — Orbit fetches the services in that namespace via kubectl get svc -o json.",
                "Tick the services you want. Services with zero ports (ExternalName, headless) are shown but not selectable.",
                "Click \"Import N Services\" to add them all at once.",
            ]),
            .heading("kubectl vs orb-kubectl"),
            .paragraph("The Tool toggle lets you generate commands using bare kubectl or orb-kubectl. orb-kubectl is a kubectl build with built-in retry on transient failures (handy when the connection to your cluster wobbles). If you haven't installed orb-kubectl, that option is disabled."),
            .note(severity: .tip, "The fetcher runs each kubectl command with a 15-second timeout and cancels in-flight requests when you switch contexts or namespaces. No hung requests."),
        ]
    )

    static let orbKubectlArticle = HelpArticle(
        id: "orb-kubectl",
        title: "orb-kubectl (kubectl with retry)",
        summary: "An optional kubectl variant that auto-reconnects on transient port-forward failures. What it is, where it comes from, and whether you need it.",
        body: [
            .paragraph("orb-kubectl is a custom build of kubectl with a --retry flag for port-forward. It transparently re-establishes the connection when the underlying API server hiccups, avoiding the common \"the connection was closed unexpectedly\" situation."),
            .heading("Do you need it?"),
            .paragraph("No. Orbit's Kubernetes import works with plain kubectl from your $PATH. orb-kubectl is a convenience for users whose clusters have flaky API-server connections. If you're not sure, stick with kubectl."),
            .heading("Where the binary comes from (trust model)"),
            .paragraph("orb-kubectl is shipped by the Orbit project as a GitHub Release asset, built from a public fork of kubernetes/kubernetes. When you choose to install it, Orbit downloads the archive, verifies its SHA-256 against the value embedded in this build of Orbit, and only then writes the binary to disk. A checksum mismatch aborts the install — your existing setup is not modified."),
            .heading("Source you can audit"),
            .bullets([
                "Fork: github.com/simonren/kubernetes (a fork of kubernetes/kubernetes)",
                "Branch: feature/resilient-port-forward",
                "Patch: staging/src/k8s.io/kubectl/pkg/cmd/portforward/resilient.go",
                "Release archive: github.com/simonren/orbit/releases (orb-kubectl-vX.Y.Z asset)",
            ]),
            .paragraph("The patch adds a --retry flag to kubectl port-forward that re-establishes the underlying API server connection on transient failures. You can clone the fork, inspect the diff against upstream master, and build your own copy if you'd rather not run the pre-built binary."),
            .heading("What Orbit verifies and where it installs"),
            .bullets([
                "Verification: SHA-256 of the archive, compared against a value pinned in Orbit's source code",
                "Installation path: ~/Library/Application Support/Orbit/bin/orb-kubectl",
                "Privileges: runs as your user; no admin password required to install",
            ]),
            .note(severity: .warn, "Like any third-party kubectl, orb-kubectl can read your kubeconfig and talk to your clusters with your credentials. If you'd rather not trust a non-official kubectl build, decline the install — plain kubectl works fine."),
            .heading("Install"),
            .paragraph("Orbit menu → Install orb-kubectl... — or open Settings → Network. You'll get a confirmation dialog showing the version, source URL, and expected checksum before any download starts. Click Cancel to back out."),
            .heading("Use it"),
            .codeBlock("orb-kubectl port-forward --address $IP svc/api 8080:8080 --retry"),
            .paragraph("Same flags as kubectl, plus --retry. The binary is added to the PATH for every service Orbit spawns, so you can just type orb-kubectl in your service command. When a new orb-kubectl is shipped with Orbit, the menu changes to \"Update orb-kubectl...\" — the same trust confirmation runs again."),
            .heading("Uninstall"),
            .paragraph("Delete the binary at ~/Library/Application Support/Orbit/bin/orb-kubectl. Orbit's K8s import sheet automatically falls back to kubectl when orb-kubectl isn't installed."),
            .note(severity: .tip, "orb-kubectl uses your existing kubeconfig (~/.kube/config), contexts, and credentials — nothing changes about cluster auth itself."),
        ]
    )

    static let helperArticle = HelpArticle(
        id: "helper",
        title: "The Privileged Helper",
        summary: "What the helper is, what it does, and the security model.",
        body: [
            .paragraph("Configuring loopback interface aliases (ifconfig lo0 alias 127.0.0.x) requires root. To avoid prompting for an admin password every time you toggle an environment, Orbit installs a small privileged XPC service called com.orbit.helper that runs as root and exposes a narrow API."),
            .heading("What it can do"),
            .bullets([
                "Add or remove 127.x.x.x aliases on lo0.",
                "Watch Orbit's PID and reap orphaned process groups if Orbit crashes.",
            ]),
            .heading("What it cannot do"),
            .bullets([
                "Run arbitrary commands.",
                "Modify anything outside lo0.",
                "Accept connections from any process that isn't a code-signature-verified copy of Orbit.",
            ]),
            .heading("Installation"),
            .paragraph("The helper is installed via Apple's SMJobBless API the first time you ask for it (first-run prompt, the reactive prompt when you toggle an environment without the helper, or the Install button in Settings). You'll see one admin password prompt; afterward it runs unattended."),
            .heading("Security verification"),
            .paragraph("The helper validates every incoming XPC connection against a SecRequirement that pins both Orbit's team identifier and its bundle identifier. An attacker would need a binary signed by the same Apple Developer team using the same bundle ID to talk to it."),
            .heading("Uninstall"),
            .paragraph("Settings → Network → Uninstall helper... removes the daemon. Existing aliases stay until you toggle off or reboot. You can re-install at any time."),
        ]
    )

    static let networkModesArticle = HelpArticle(
        id: "network-modes",
        title: "Automatic vs Manual Network Modes",
        summary: "When the helper manages aliases for you, and when you do it yourself.",
        body: [
            .paragraph("Orbit supports two modes, switched via Settings → Network → \"Automatically configure loopback interfaces\"."),
            .heading("Automatic (default)"),
            .paragraph("With the helper installed and the setting on, Orbit asks the helper to add the required 127.0.0.x aliases on lo0 when you toggle an environment, and to remove them on deactivation. This is the seamless one-click experience."),
            .heading("Manual"),
            .paragraph("Turn the setting off if you want Orbit to never touch lo0. You manage the aliases yourself with sudo ifconfig. When you toggle an environment on, Orbit checks that every required IP is already aliased; if any are missing, it shows a recovery alert with three choices:"),
            .bullets([
                "Install Helper Now — switches you back to the automatic flow with one click.",
                "Copy Manual Command — puts the sudo ifconfig commands on your clipboard.",
                "Cancel — abort the activation.",
            ]),
            .codeBlock("sudo ifconfig lo0 alias 127.0.0.2\nsudo ifconfig lo0 alias 127.0.0.3"),
            .note(severity: .tip, "Manual mode is for users who prefer to avoid installing root daemons. The trade-off is friction every time you bring a new IP online."),
        ]
    )

    static let importExportArticle = HelpArticle(
        id: "import-export",
        title: "Import & Export",
        summary: "Share single environments, or back up your entire setup.",
        body: [
            .heading("Single environment"),
            .paragraph("Each environment can be exported to a .orbit.json file (Export... from the sidebar context menu). The file contains the environment's name, interfaces, and services."),
            .paragraph("Import the same file via File → Import.... If the name or any IP collides with an existing environment, Orbit shows a preview sheet and offers resolutions (rename, replace, or skip)."),
            .heading("Bulk archive"),
            .paragraph("File → Export Archive... (⌘⇧E) packs every environment into a single dated .orbit.zip archive — e.g. 20260514.orbit.zip. The archive includes a manifest.json plus one .orbit.json per environment."),
            .paragraph("File → Import Archive... (⌘⇧I) restores from an archive, with per-environment conflict resolution on import."),
            .note(severity: .tip, "Use the bulk archive for laptop migrations or shared team setups. Use single export for sending one config to a coworker who's debugging the same service."),
        ]
    )

    static let settingsArticle = HelpArticle(
        id: "settings",
        title: "Settings",
        summary: "What every setting does, with sensible defaults.",
        body: [
            .heading("General"),
            .bullets([
                "Launch Orbit at startup — when on, registers Orbit as a macOS login item (via SMAppService). Default off; opt in if you want Orbit always available in the menubar.",
            ]),
            .heading("Network"),
            .bullets([
                "Automatically configure loopback interfaces — toggle the automatic vs manual mode described in \"Network Modes\". Default on for new installs.",
                "Install helper... / Uninstall helper... — install or remove the privileged helper. The label shows the current state and version.",
            ]),
            .note(severity: .warn, "If you uninstall the helper while environments are active, the running services keep going — but the aliases they bound to remain on lo0 until you deactivate or reboot."),
        ]
    )

    static let autoUpdateArticle = HelpArticle(
        id: "auto-update",
        title: "Auto-Update",
        summary: "How Orbit ships updates.",
        body: [
            .paragraph("Orbit uses Sparkle for auto-updates. On launch and roughly once a day, it checks an appcast feed hosted on GitHub Pages."),
            .heading("Where updates come from"),
            .paragraph("The appcast lives at https://simonren.github.io/orbit/appcast.xml and points at signed DMGs in the GitHub Releases section. Each update is signed with an EdDSA private key; Orbit only installs updates whose signature matches the public key embedded in its Info.plist."),
            .heading("Triggering a check"),
            .paragraph("Orbit menu → Check for Updates... runs the check immediately. You'll see release notes for the latest version and can install with one click."),
        ]
    )

    static let shortcutsArticle = HelpArticle(
        id: "shortcuts",
        title: "Keyboard Shortcuts",
        summary: "All the keyboard shortcuts in one place.",
        body: [
            .heading("App"),
            .shortcutTable([
                ("Settings...", "⌘,"),
                ("Hide Orbit", "⌘H"),
                ("Quit Orbit", "⌘Q"),
            ]),
            .heading("Window"),
            .shortcutTable([
                ("Close window", "⌘W"),
                ("Minimize", "⌘M"),
            ]),
            .heading("File"),
            .shortcutTable([
                ("New Environment", "⌘N"),
                ("Import Environment...", "⌘I"),
                ("Export Archive...", "⌘⇧E"),
                ("Import Archive...", "⌘⇧I"),
            ]),
            .heading("Environment"),
            .shortcutTable([
                ("Activate / Deactivate selected", "⌘E"),
                ("Add Service... (when env selected)", "⌘⇧S"),
            ]),
        ]
    )

    static let troubleshootingArticle = HelpArticle(
        id: "troubleshooting",
        title: "Troubleshooting",
        summary: "Common issues and how to recover.",
        body: [
            .heading("\"Interface not configured\" alert"),
            .paragraph("You're in manual mode and an IP isn't aliased on lo0. Either install the helper (one click in the alert), or run the manual command (also one click — copies sudo ifconfig commands to your clipboard)."),
            .heading("Helper install failed"),
            .paragraph("SMJobBless can fail for a few reasons:"),
            .bullets([
                "You denied the admin prompt. Retry from Settings → Install helper.",
                "You're running an unsigned build (e.g. a local development build). The helper requires a Developer ID signature.",
                "You're running from a non-/Applications path. Some macOS versions refuse SMJobBless from DerivedData. Move Orbit.app to /Applications and try again.",
            ]),
            .heading("Service keeps failing"),
            .paragraph("Open the service's log window. The progressive backoff (1s, 2s, 5s, ...) prevents tight restart loops, but a misconfigured command will still spam errors. Common causes:"),
            .bullets([
                "Command references $IP for an environment with no interfaces.",
                "kubectl isn't on PATH for GUI apps. Orbit prepends ~/Library/Application Support/Orbit/bin and the common Homebrew/system paths to PATH, but if your kubectl lives elsewhere, use the absolute path.",
                "Bound to a port that's already in use on this IP. Try a different port or IP.",
            ]),
            .heading("Activation fails partway through"),
            .paragraph("If Orbit gets through some interfaces then hits one that fails, it rolls back: every alias it just added gets removed. You'll see an alert naming the IP that failed. Common cause: the IP was already aliased by another tool — pick a different IP."),
            .heading("Toggle does nothing"),
            .paragraph("Orbit enforces a 500ms cooldown between toggles to prevent rapid clicks from racing the activation/deactivation flow. Wait half a second and try again."),
            .heading("Reset everything"),
            .paragraph("Quit Orbit. Delete ~/Library/Application Support/Orbit/config.json (your environments) and config.backup.json. Relaunch. You'll see the first-run welcome and can start fresh."),
        ]
    )

    static let aboutArticle = HelpArticle(
        id: "about",
        title: "About & Contributing",
        summary: "Open-source license, reporting bugs, and contributing.",
        body: [
            .paragraph("Orbit is open source under the MIT license. Source, releases, and discussions live at https://github.com/simonren/orbit."),
            .heading("Report a bug"),
            .paragraph("Use GitHub Issues: https://github.com/simonren/orbit/issues/new/choose. For security vulnerabilities, please follow the private disclosure path in SECURITY.md instead of filing a public issue (the privileged helper is sensitive)."),
            .heading("Contribute"),
            .paragraph("PRs are welcome. See CONTRIBUTING.md in the repo for build setup (XcodeGen + Xcode 15+) and the code-signing override path for contributors using their own Apple Developer team."),
            .heading("Credits"),
            .bullets([
                "Sparkle — auto-update framework (MIT).",
                "ZIPFoundation — ZIP archive support (MIT).",
                "XcodeGen — project generator (MIT, dev dep).",
            ]),
        ]
    )
}
