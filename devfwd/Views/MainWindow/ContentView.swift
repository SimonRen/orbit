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
                    .id(selectedId)  // Force view recreation when selection changes
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
    private static let frameKey = "MainWindowFrame"

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                // Restore saved frame if available
                if let frameString = UserDefaults.standard.string(forKey: Self.frameKey) {
                    let savedFrame = NSRectFromString(frameString)
                    if savedFrame.width >= 800 && savedFrame.height >= 500 {
                        window.setFrame(savedFrame, display: true)
                    }
                }

                // Observe frame changes to save them (store observers for cleanup)
                context.coordinator.resizeObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didResizeNotification,
                    object: window,
                    queue: .main
                ) { _ in
                    context.coordinator.scheduleFrameSave(window.frame)
                }
                context.coordinator.moveObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didMoveNotification,
                    object: window,
                    queue: .main
                ) { _ in
                    context.coordinator.scheduleFrameSave(window.frame)
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
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    class Coordinator {
        var resizeObserver: NSObjectProtocol?
        var moveObserver: NSObjectProtocol?
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

#Preview {
    ContentView()
        .environmentObject(AppState())
}
