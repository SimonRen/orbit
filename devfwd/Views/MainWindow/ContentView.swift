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

#Preview {
    ContentView()
        .environmentObject(AppState())
}
