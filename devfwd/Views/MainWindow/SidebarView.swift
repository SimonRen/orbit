import SwiftUI

/// Sidebar showing the list of environments
struct SidebarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("ENVIRONMENTS")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)
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
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
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
