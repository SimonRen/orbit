import AppKit
import SwiftUI
import Combine

/// App delegate handling menubar and app lifecycle
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var appState: AppState?
    private var cancellables = Set<AnyCancellable>()

    // Cached state for menu building (updated via Combine)
    private var cachedEnvironments: [DevEnvironment] = []

    // MARK: - Configuration

    /// Configure the delegate with shared app state (only runs once)
    func configure(with appState: AppState) {
        // Guard against duplicate configuration
        guard self.appState == nil else { return }

        self.appState = appState
        setupStatusItem()
        observeStateChanges()
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
        }

        rebuildMenu()
    }

    private func observeStateChanges() {
        // Rebuild menu when environments change
        appState?.$environments
            .receive(on: RunLoop.main)
            .sink { [weak self] environments in
                self?.cachedEnvironments = environments
                self?.rebuildMenu()
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

    private func rebuildMenu() {
        let menu = NSMenu()

        // Header
        let headerItem = NSMenuItem(title: "ENVIRONMENTS", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        headerItem.attributedTitle = NSAttributedString(
            string: "ENVIRONMENTS",
            attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold)
            ]
        )
        menu.addItem(headerItem)

        // Environment toggles
        if cachedEnvironments.isEmpty {
            let emptyItem = NSMenuItem(title: "No environments", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for environment in cachedEnvironments.sorted(by: { $0.order < $1.order }) {
                let item = NSMenuItem()
                item.view = createEnvironmentMenuItemView(for: environment)
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        // Main Frame
        let mainFrameItem = NSMenuItem(
            title: "Show Window",
            action: #selector(showMainWindow(_:)),
            keyEquivalent: ""
        )
        mainFrameItem.target = self
        menu.addItem(mainFrameItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit DEV Fwd",
            action: #selector(quitApp(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    /// Creates a custom view for environment menu item with name and toggle switch
    private func createEnvironmentMenuItemView(for environment: DevEnvironment) -> NSView {
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 28))

        // Environment name label
        let label = NSTextField(labelWithString: environment.name)
        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = environment.isTransitioning ? .secondaryLabelColor : .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(label)

        if environment.isTransitioning {
            // Show spinner when transitioning
            let spinner = NSProgressIndicator()
            spinner.style = .spinning
            spinner.controlSize = .small
            spinner.isIndeterminate = true
            spinner.startAnimation(nil)
            spinner.translatesAutoresizingMaskIntoConstraints = false
            containerView.addSubview(spinner)

            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 14),
                label.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),

                spinner.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -14),
                spinner.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),

                label.trailingAnchor.constraint(lessThanOrEqualTo: spinner.leadingAnchor, constant: -8)
            ])
        } else {
            // Toggle switch (only when not transitioning)
            let toggle = NSSwitch()
            toggle.controlSize = .mini
            toggle.state = environment.isEnabled ? .on : .off
            toggle.target = self
            toggle.action = #selector(environmentSwitchToggled(_:))
            toggle.identifier = NSUserInterfaceItemIdentifier(environment.id.uuidString)
            toggle.translatesAutoresizingMaskIntoConstraints = false

            // Check if we can toggle (respects cooldown)
            let canToggle = appState?.canToggleEnvironment(environment.id) ?? false
            toggle.isEnabled = canToggle

            containerView.addSubview(toggle)

            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 14),
                label.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),

                toggle.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -14),
                toggle.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),

                label.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -8)
            ])
        }

        return containerView
    }

    // MARK: - Actions

    @objc private func environmentSwitchToggled(_ sender: NSSwitch) {
        guard let identifier = sender.identifier?.rawValue,
              let environmentId = UUID(uuidString: identifier) else { return }

        // Toggle the environment - menu stays open
        // The menu will rebuild automatically via state observation
        appState?.toggleEnvironment(environmentId)
    }

    @objc private func toggleEnvironment(_ sender: NSMenuItem) {
        guard let environmentId = sender.representedObject as? UUID else { return }
        appState?.toggleEnvironment(environmentId)
    }

    @objc private func showMainWindow(_ sender: NSMenuItem) {
        NSApp.activate(ignoringOtherApps: true)

        // Find existing window or create new one
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            // No window exists, use coordinator to open one
            WindowCoordinator.shared.openMainWindow?()
        }
    }

    @objc private func quitApp(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }
}
