import SwiftUI

/// Shared coordinator for window management
class WindowCoordinator: ObservableObject {
    static let shared = WindowCoordinator()
    var openMainWindow: (() -> Void)?
    var openLogWindow: ((UUID) -> Void)?  // Opens log window for service ID
    var triggerImport: (() -> Void)?  // Triggers import dialog
}

@main
struct OrbitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var updaterManager = UpdaterManager.shared
    @StateObject private var toolManager = ToolManager.shared
    @Environment(\.openWindow) private var openWindow

    private let processManager = ProcessManager.shared
    private let networkManager = NetworkManager.shared

    /// Track if initial setup has been done (prevents duplicate setup on new windows)
    @State private var isSetupDone = false

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(appState)
                .onAppear {
                    // Only run setup once, not on every window open
                    if !isSetupDone {
                        setupApp()
                        isSetupDone = true
                    }
                    // Always update the openWindow closure (it may change)
                    WindowCoordinator.shared.openMainWindow = { [openWindow] in
                        openWindow(id: "main")
                    }
                    WindowCoordinator.shared.openLogWindow = { [openWindow] serviceId in
                        openWindow(id: "logs", value: serviceId)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 600)

        // Log viewer window
        WindowGroup(id: "logs", for: UUID.self) { $serviceId in
            if let serviceId = serviceId {
                LogWindowView(serviceId: serviceId)
                    .environmentObject(appState)
            }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 700, height: 500)
        .commands {
            // Check for Updates in app menu (after About)
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updaterManager: updaterManager)

                Divider()

                OrbKubectlMenuView(toolManager: toolManager)
            }

            // File menu customization
            CommandGroup(replacing: .newItem) {
                Button("New Environment") {
                    _ = appState.createEnvironment()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Import...") {
                    WindowCoordinator.shared.triggerImport?()
                }
                .keyboardShortcut("i", modifiers: .command)
            }

            // Custom menu for environments
            CommandMenu("Environment") {
                if let selectedId = appState.selectedEnvironmentId,
                   let env = appState.environments.first(where: { $0.id == selectedId }) {
                    Button(env.isEnabled ? "Deactivate" : "Activate") {
                        appState.toggleEnvironment(selectedId)
                    }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(appState.selectedEnvironmentId == nil)
                }

                Divider()

                Button("Add Service...") {
                    // This would need to trigger the sheet
                    // For now, just a placeholder
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(appState.selectedEnvironmentId == nil)
            }
        }
    }

    private func setupApp() {
        // Configure AppState with managers
        appState.configure(
            processManager: processManager,
            networkManager: networkManager
        )

        // Configure AppDelegate with shared state
        appDelegate.configure(with: appState)
    }
}
