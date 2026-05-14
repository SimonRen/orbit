import AppKit
import SwiftUI

/// App delegate handling app lifecycle. The menubar item lives in OrbitApp's
/// MenuBarExtra scene; this delegate now only handles termination, dock-icon
/// visibility, and the static activation helpers used by other windows.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState?

    // Window observation
    private var windowObservers: [NSObjectProtocol] = []

    // MARK: - Configuration

    /// Configure the delegate with shared app state (only runs once)
    func configure(with appState: AppState) {
        // Guard against duplicate configuration
        guard self.appState == nil else { return }

        self.appState = appState
        setupWindowObservation()

        // Register with helper for orphan monitoring
        Task {
            await OrphanRegistrar.shared.register()
        }
    }

    // MARK: - NSApplicationDelegate

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        // MenuBarExtra in OrbitApp handles the status item; nothing to do here.
    }

    nonisolated func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // AppKit guarantees this is called on main thread
        return MainActor.assumeIsolated {
            guard appState?.hasActiveEnvironments ?? false else {
                // No active environments - unregister and quit immediately
                Task {
                    await OrphanRegistrar.shared.unregister()
                }
                return .terminateNow
            }

            // Show confirmation dialog
            let alert = NSAlert()
            alert.messageText = "Active Environments"
            alert.informativeText = "Active environments will be stopped. Quit anyway?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Quit")
            alert.addButton(withTitle: "Cancel")

            if alert.runModal() == .alertFirstButtonReturn {
                // User confirmed - stop all and quit
                appState?.stopAllEnvironments {
                    Task { @MainActor in
                        // Unregister AFTER processes stopped
                        await OrphanRegistrar.shared.unregister()
                        NSApp.reply(toApplicationShouldTerminate: true)
                    }
                }
                return .terminateLater
            } else {
                return .terminateCancel
            }
        }
    }

    nonisolated func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in menubar even if window is closed
        return false
    }

    // MARK: - Window Observation

    private func setupWindowObservation() {
        // Observe window visibility to toggle Dock icon
        let willOpen = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeMainNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // queue: .main guarantees main thread
            MainActor.assumeIsolated {
                self?.updateDockIconVisibility()
            }
        }

        let willClose = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Delay check to allow window to fully close
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                MainActor.assumeIsolated {
                    self?.updateDockIconVisibility()
                }
            }
        }

        windowObservers = [willOpen, willClose]
    }

    private func updateDockIconVisibility() {
        // Check if any main windows are visible (exclude popovers and panels)
        let hasVisibleWindow = NSApp.windows.contains { window in
            window.isVisible &&
            window.canBecomeMain &&
            !window.isKind(of: NSPanel.self) &&
            window.className != "NSStatusBarWindow"
        }

        if hasVisibleWindow {
            // Show in Dock
            NSApp.setActivationPolicy(.regular)
        } else {
            // Hide from Dock (menubar only)
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Activation Helpers

    /// Workaround for macOS bug where programmatic activation doesn't fully activate the app
    /// Solution: briefly activate the Dock, then reactivate our app - forces proper activation cycle
    /// Used by: Swiftness, Better Blocker, and other menubar apps
    static func activateAppWithDockToggle() {
        // Step 1: Briefly activate the Dock to force a proper activation cycle
        let dockActivated = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.activate(options: []) ?? false

        // Step 2: After delay, reactivate our app (use shorter delay if Dock activation failed)
        let delay = dockActivated ? 200 : 50
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay)) {
            activateAndShowWindow()
        }
    }

    /// Shared logic for activating app and showing main window
    static func activateAndShowWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Find existing window or create new one
        if let window = NSApp.windows.first(where: { $0.canBecomeMain && !$0.isKind(of: NSPanel.self) }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            WindowCoordinator.shared.openMainWindow?()
        }
    }

}

// MARK: - Status Menu SwiftUI View

struct StatusMenuView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("ENVIRONMENTS")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            // Environment list
            if appState.environments.isEmpty {
                Text("No environments")
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ForEach(appState.sortedEnvironments) { environment in
                    EnvironmentMenuRow(
                        environment: environment,
                        onToggle: {
                            appState.toggleEnvironment(environment.id)
                        }
                    )
                }
            }

            Divider()
                .padding(.vertical, 6)

            // Show Window button — activating the app causes MenuBarExtra
            // to lose focus and dismiss automatically.
            MenuRowButton(label: "Show Window") {
                AppDelegate.activateAppWithDockToggle()
            }

            Divider()
                .padding(.vertical, 6)

            // Quit button
            MenuRowButton(label: "Quit Orbit", shortcut: "⌘Q") {
                NSApp.terminate(nil)
            }
            .padding(.bottom, 4)
        }
        // MenuBarExtra(.window) supplies its own native material — no
        // explicit background here so the system frosted look comes through.
    }
}

struct EnvironmentMenuRow: View {
    let environment: DevEnvironment
    let onToggle: () -> Void
    @State private var isHovered = false

    private var textColor: Color {
        if isHovered {
            return .white
        } else if environment.isTransitioning {
            return .secondary
        } else if environment.isEnabled {
            return .primary  // Bright for enabled
        } else {
            return .secondary  // Gray for disabled
        }
    }

    private var ipColor: Color {
        if isHovered {
            return .white.opacity(0.7)
        } else {
            return .secondary
        }
    }

    var body: some View {
        HStack {
            // Status indicator dot
            Circle()
                .fill(environment.isEnabled ? Color.green : Color.gray.opacity(0.5))
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 1) {
                Text(environment.name)
                    .foregroundColor(textColor)
                    .fontWeight(environment.isEnabled ? .medium : .regular)

                if !environment.interfaces.isEmpty {
                    Text(environment.interfaceIPs.prefix(2).joined(separator: ", "))
                        .font(.caption2)
                        .foregroundColor(ipColor)
                }
            }

            Spacer()

            if environment.isTransitioning {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            } else {
                Toggle("", isOn: Binding(
                    get: { environment.isEnabled },
                    set: { _ in onToggle() }
                ))
                .toggleStyle(AccentToggleStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color.accentColor : Color.clear)
        )
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

/// Reusable menu row button with hover state
struct MenuRowButton: View {
    let label: String
    var shortcut: String? = nil
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .foregroundColor(isHovered ? .white : .primary)
                Spacer()
                if let shortcut = shortcut {
                    Text(shortcut)
                        .foregroundColor(isHovered ? .white.opacity(0.8) : .secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? Color.accentColor : Color.clear)
            )
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
