import SwiftUI

/// Sidebar showing the list of environments
struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @State private var environmentToDelete: DevEnvironment?
    @State private var showingDeleteConfirmation = false
    @State private var showingCannotDeleteAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header (with space for traffic lights)
            Text("ENVIRONMENTS")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)

            // Environment list
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(appState.sortedEnvironments) { environment in
                        EnvironmentRowView(
                            environment: environment,
                            isSelected: appState.selectedEnvironmentId == environment.id,
                            isToggleDisabled: !appState.canToggleEnvironment(environment.id),
                            onToggle: { _ in
                                appState.toggleEnvironment(environment.id)
                            }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            appState.selectedEnvironmentId = environment.id
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                if environment.isEnabled || environment.isTransitioning {
                                    showingCannotDeleteAlert = true
                                } else {
                                    environmentToDelete = environment
                                    showingDeleteConfirmation = true
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .alert("Delete Environment?", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    if let env = environmentToDelete {
                        appState.deleteEnvironment(env.id)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete \"\(environmentToDelete?.name ?? "")\" and all its services.")
            }
            .alert("Cannot Delete", isPresented: $showingCannotDeleteAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please stop the environment before deleting it.")
            }

            Divider()

            // Footer with new environment button
            Button(action: createNewEnvironment) {
                HStack {
                    Image(systemName: "plus")
                    Text("New Environment")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func createNewEnvironment() {
        _ = appState.createEnvironment()
    }
}

#Preview {
    SidebarView()
        .environmentObject({
            let state = AppState()
            // Add some sample environments for preview
            return state
        }())
        .frame(height: 400)
}
