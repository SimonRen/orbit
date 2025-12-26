import SwiftUI
import UniformTypeIdentifiers

/// Sidebar showing the list of environments
struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @State private var environmentToDelete: DevEnvironment?
    @State private var showingDeleteConfirmation = false
    @State private var showingCannotDeleteAlert = false

    // Import/Export state
    @State private var importPreview: ImportPreview?
    @State private var importError: ImportError?
    @State private var showingImportError = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // App header with branding
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    // App icon
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 32, height: 32)
                        .cornerRadius(6)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("Orbit")
                                .font(.system(size: 15, weight: .semibold))

                            Text("v\(appVersion)")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                        }

                        Text("Tunnels, Organized")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 26)  // Space for traffic lights
            .padding(.bottom, 16)
            .background(WindowDragArea())

            Divider()
                .padding(.horizontal, 12)

            // Section header
            Text("ENVIRONMENTS")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                        .contextMenu {
                            Button {
                                exportEnvironment(environment)
                            } label: {
                                Label("Export...", systemImage: "square.and.arrow.up")
                            }

                            Divider()

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

            // Footer with new environment and import buttons
            VStack(spacing: 0) {
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

                Button(action: importEnvironment) {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text("Import...")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding(.bottom, 8)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .sheet(item: $importPreview) { preview in
            ImportPreviewSheet(
                preview: preview,
                onImport: { name, useSuggestedIPs in
                    appState.importEnvironment(preview, name: name, useSuggestedIPs: useSuggestedIPs)
                    importPreview = nil
                },
                onCancel: {
                    importPreview = nil
                }
            )
        }
        .alert("Import Error", isPresented: $showingImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError?.localizedDescription ?? "Unknown error")
        }
        .onAppear {
            WindowCoordinator.shared.triggerImport = { [self] in
                importEnvironment()
            }
        }
    }

    private func createNewEnvironment() {
        _ = appState.createEnvironment()
    }

    private func exportEnvironment(_ environment: DevEnvironment) {
        guard let data = appState.exportEnvironment(environment.id) else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(environment.name).orbit.json"
        panel.allowedContentTypes = [UTType.json]
        panel.canCreateDirectories = true

        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try data.write(to: url)
                } catch {
                    print("Failed to export: \(error)")
                }
            }
        }
    }

    private func importEnvironment() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            do {
                let data = try Data(contentsOf: url)

                DispatchQueue.main.async {
                    let result = appState.validateImport(data)

                    switch result {
                    case .success(let preview):
                        importPreview = preview
                    case .failure(let error):
                        importError = error
                        showingImportError = true
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    importError = .invalidJSON(error)
                    showingImportError = true
                }
            }
        }
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
