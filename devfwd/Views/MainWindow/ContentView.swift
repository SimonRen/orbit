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
    }
}

/// Helper to access NSWindow and adjust traffic light positions
struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
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
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
