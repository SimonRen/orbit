import SwiftUI

/// Main content view with sidebar and detail pane
struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            // Fixed sidebar
            SidebarView()
                .frame(width: 220)

            Divider()

            // Detail view
            if let selectedId = appState.selectedEnvironmentId {
                DetailView(environmentId: selectedId)
                    .id(selectedId)  // Required to force view recreation and reset @State
                    .transition(.identity)  // No transition animation
                    .transaction { $0.animation = nil }  // Prevent animation jump during selection change
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyDetailView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .background(WindowAccessor())
        .alert(item: $appState.lastError) { error in
            Alert(
                title: Text("Error"),
                message: Text(error.localizedDescription),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert("Install Helper", isPresented: $appState.showHelperInstallPrompt) {
            Button("Install") {
                Task {
                    await appState.installHelper()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Orbit needs to install a privileged helper to manage network interfaces. This requires administrator permission once.")
        }
        .alert("Upgrade Helper", isPresented: $appState.showHelperUpgradePrompt) {
            Button("Upgrade") {
                Task {
                    await appState.installHelper()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Orbit needs to upgrade its privileged helper to a newer version. This requires administrator permission.")
        }
    }
}

/// Helper to access NSWindow, adjust traffic light positions, and persist frame
struct WindowAccessor: NSViewRepresentable {
    static let frameKey = "MainWindowFrame"

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        // Use custom view for synchronous window configuration
        WindowConfigView(coordinator: context.coordinator)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    class Coordinator {
        var resizeObserver: NSObjectProtocol?
        var moveObserver: NSObjectProtocol?
        var isConfigured = false
        private var saveWorkItem: DispatchWorkItem?

        func scheduleFrameSave(_ frame: NSRect) {
            saveWorkItem?.cancel()
            saveWorkItem = DispatchWorkItem {
                UserDefaults.standard.set(NSStringFromRect(frame), forKey: WindowAccessor.frameKey)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: saveWorkItem!)
        }

        deinit {
            saveWorkItem?.cancel()
            if let observer = resizeObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = moveObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}

/// Custom NSView that configures the window synchronously when added to window hierarchy
private class WindowConfigView: NSView {
    private let coordinator: WindowAccessor.Coordinator

    init(coordinator: WindowAccessor.Coordinator) {
        self.coordinator = coordinator
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard let window = self.window, !coordinator.isConfigured else { return }
        coordinator.isConfigured = true

        // Hide window temporarily to prevent visible jump during frame restoration
        window.alphaValue = 0

        // Restore saved frame if available and on a valid screen
        if let frameString = UserDefaults.standard.string(forKey: WindowAccessor.frameKey) {
            let savedFrame = NSRectFromString(frameString)
            // Validate size constraints
            if savedFrame.width >= 800 && savedFrame.height >= 500 {
                // Validate frame is on a connected screen (handles external monitor disconnect)
                let isOnValidScreen = NSScreen.screens.contains { $0.frame.intersects(savedFrame) }
                if isOnValidScreen {
                    window.setFrame(savedFrame, display: false)
                }
            }
        }

        // Show window after positioning
        window.alphaValue = 1

        // Observe frame changes to save them
        coordinator.resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            guard let window = self?.window else { return }
            self?.coordinator.scheduleFrameSave(window.frame)
        }
        coordinator.moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            guard let window = self?.window else { return }
            self?.coordinator.scheduleFrameSave(window.frame)
        }

        // Adjust traffic light button positions
        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for buttonType in buttons {
            if let button = window.standardWindowButton(buttonType) {
                var frame = button.frame
                frame.origin.x += 4
                frame.origin.y -= 4
                button.setFrameOrigin(frame.origin)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
