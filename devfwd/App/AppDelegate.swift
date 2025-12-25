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

    // MARK: - Configuration

    /// Configure the delegate with shared app state (only runs once)
    func configure(with appState: AppState) {
        // Guard against duplicate configuration
        guard self.appState == nil else { return }

        self.appState = appState
        setupStatusItem()
        setupPopover()
        observeStateChanges()
        setupEventMonitor()
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
            button.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "DEV Fwd")
            button.target = self
            button.action = #selector(statusItemClicked(_:))
        }
    }

    private func setupPopover() {
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 220, height: 200)
        popover?.behavior = .transient
        popover?.delegate = self
        updatePopoverContent()
    }

    private func updatePopoverContent() {
        guard let appState = appState else { return }
        let contentView = StatusMenuView(appState: appState) { [weak self] in
            self?.closePopover()
        }
        popover?.contentViewController = NSHostingController(rootView: contentView)
    }

    private func setupEventMonitor() {
        // Close popover when clicking outside
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func observeStateChanges() {
        // Rebuild menu when environments change
        appState?.$environments
            .receive(on: RunLoop.main)
            .sink { [weak self] environments in
                self?.cachedEnvironments = environments
                self?.updatePopoverContent()
                self?.updateStatusIcon()
            }
            .store(in: &cancellables)
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }

        let hasActive = cachedEnvironments.contains { $0.isEnabled }
        let hasFailed = cachedEnvironments.flatMap { $0.services }.contains { $0.status == .failed }

        if hasFailed {
            button.image = NSImage(
                systemSymbolName: "exclamationmark.arrow.triangle.2.circlepath",
                accessibilityDescription: "DEV Fwd - Warning"
            )
            button.contentTintColor = .systemRed
        } else if hasActive {
            button.image = NSImage(
                systemSymbolName: "arrow.triangle.branch",
                accessibilityDescription: "DEV Fwd - Active"
            )
            button.contentTintColor = .controlAccentColor
        } else {
            button.image = NSImage(
                systemSymbolName: "arrow.triangle.branch",
                accessibilityDescription: "DEV Fwd"
            )
            button.contentTintColor = nil
        }
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
        guard let button = statusItem?.button, let popover = popover else { return }

        updatePopoverContent()

        // Show popover relative to the button
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // Configure popover window for fullscreen compatibility
        if let popoverWindow = popover.contentViewController?.view.window {
            popoverWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            popoverWindow.level = .popUpMenu
        }
    }

    private func closePopover() {
        popover?.performClose(nil)
    }

    // MARK: - NSPopoverDelegate

    nonisolated func popoverDidClose(_ notification: Notification) {
        // Popover closed
    }

    // MARK: - Actions

    @objc private func showMainWindow(_ sender: Any?) {
        closePopover()
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

    func toggleEnvironment(_ id: UUID) {
        appState?.toggleEnvironment(id)
    }

    func canToggleEnvironment(_ id: UUID) -> Bool {
        appState?.canToggleEnvironment(id) ?? false
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
                        canToggle: appState.canToggleEnvironment(environment.id),
                        onToggle: {
                            appState.toggleEnvironment(environment.id)
                        }
                    )
                }
            }

            Divider()
                .padding(.vertical, 6)

            // Show Window button
            Button(action: {
                onDismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NSApp.activate(ignoringOtherApps: true)
                    if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
                        window.makeKeyAndOrderFront(nil)
                    } else {
                        WindowCoordinator.shared.openMainWindow?()
                    }
                }
            }) {
                Text("Show Window")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()
                .padding(.vertical, 6)

            // Quit button
            Button(action: {
                onDismiss()
                NSApp.terminate(nil)
            }) {
                HStack {
                    Text("Quit DEV Fwd")
                    Spacer()
                    Text("⌘Q")
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .padding(.bottom, 4)
        }
        .frame(width: 200)
    }
}

struct EnvironmentMenuRow: View {
    let environment: DevEnvironment
    let canToggle: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack {
            Text(environment.name)
                .foregroundColor(environment.isTransitioning ? .secondary : .primary)

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
                .disabled(!canToggle)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
