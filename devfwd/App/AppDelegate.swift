import AppKit
import SwiftUI
import Combine

/// App delegate handling menubar and app lifecycle
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var appState: AppState?
    private var cancellables = Set<AnyCancellable>()
    private var eventMonitor: Any?

    // Cached state for menu building (updated via Combine)
    private var cachedEnvironments: [DevEnvironment] = []

    // Window observation
    private var windowObservers: [NSObjectProtocol] = []

    // MARK: - Configuration

    /// Configure the delegate with shared app state (only runs once)
    func configure(with appState: AppState) {
        // Guard against duplicate configuration
        guard self.appState == nil else { return }

        self.appState = appState
        setupStatusItem()
        setupPopover()
        observeStateChanges()
        setupWindowObservation()
    }

    // MARK: - NSApplicationDelegate

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        // Status item setup happens in configure()
    }

    nonisolated func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Check on main actor
        let hasActive = MainActor.assumeIsolated {
            appState?.hasActiveEnvironments ?? false
        }

        guard hasActive else {
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
            Task { @MainActor in
                appState?.stopAllEnvironments {
                    NSApp.reply(toApplicationShouldTerminate: true)
                }
            }
            return .terminateLater
        } else {
            return .terminateCancel
        }
    }

    nonisolated func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in menubar even if window is closed
        return false
    }

    // MARK: - Status Item Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "Orbit")
            button.target = self
            button.action = #selector(statusItemClicked(_:))
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 220, height: 200)
        popover?.behavior = .transient
        popover?.delegate = self
        // Content is created lazily in showPopover() to avoid idle CPU usage
    }

    private func addEventMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func setupWindowObservation() {
        // Observe window visibility to toggle Dock icon
        let willOpen = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeMainNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateDockIconVisibility()
        }

        let willClose = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Delay check to allow window to fully close
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self?.updateDockIconVisibility()
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

    private func observeStateChanges() {
        // Cache environments for status icon (SwiftUI handles popover updates)
        appState?.$environments
            .receive(on: RunLoop.main)
            .sink { [weak self] environments in
                self?.cachedEnvironments = environments
            }
            .store(in: &cancellables)
    }

    private func updateStatusIcon() {
        // Icon stays the same - no color changes needed
    }

    // MARK: - Popover Control

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        togglePopover()
    }

    private func togglePopover() {
        if let popover = popover, popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button, let popover = popover, let appState = appState else { return }

        // Create content lazily to avoid idle CPU usage from SwiftUI's CVDisplayLink
        let contentView = StatusMenuView(appState: appState) { [weak self] in
            self?.closePopover()
        }
        popover.contentViewController = NSHostingController(rootView: contentView)

        // Show popover relative to the button
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // Configure popover window for fullscreen compatibility
        if let popoverWindow = popover.contentViewController?.view.window {
            popoverWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            popoverWindow.level = .popUpMenu
        }

        // Start monitoring for outside clicks
        addEventMonitor()
    }

    private func closePopover() {
        popover?.performClose(nil)
    }

    // MARK: - NSPopoverDelegate

    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor in
            removeEventMonitor()
            // Destroy content to stop SwiftUI's CVDisplayLink and save CPU
            popover?.contentViewController = nil
        }
    }

    // MARK: - Actions

    @objc private func showMainWindow(_ sender: Any?) {
        closePopover()

        // Show in Dock before activating
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Find existing window or create new one
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            // No window exists, use coordinator to open one
            WindowCoordinator.shared.openMainWindow?()
        }
    }

    @objc private func quitApp(_ sender: Any?) {
        closePopover()
        NSApp.terminate(nil)
    }

}

// MARK: - Status Menu SwiftUI View

struct StatusMenuView: View {
    @ObservedObject var appState: AppState
    var onDismiss: () -> Void

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

            // Show Window button
            MenuRowButton(label: "Show Window") {
                onDismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    // Show in Dock before activating
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
                        window.makeKeyAndOrderFront(nil)
                    } else {
                        WindowCoordinator.shared.openMainWindow?()
                    }
                }
            }

            Divider()
                .padding(.vertical, 6)

            // Quit button
            MenuRowButton(label: "Quit Orbit", shortcut: "⌘Q") {
                onDismiss()
                NSApp.terminate(nil)
            }
            .padding(.bottom, 4)
        }
        .frame(width: 200)
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

    var body: some View {
        HStack {
            // Status indicator dot
            Circle()
                .fill(environment.isEnabled ? Color.green : Color.gray.opacity(0.5))
                .frame(width: 6, height: 6)

            Text(environment.name)
                .foregroundColor(textColor)
                .fontWeight(environment.isEnabled ? .medium : .regular)

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
                .toggleStyle(.switch)
                .controlSize(.mini)
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
