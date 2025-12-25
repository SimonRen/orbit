import SwiftUI

/// Detail view showing the selected environment's configuration
struct DetailView: View {
    @EnvironmentObject var appState: AppState
    let environmentId: UUID

    @State private var editedName: String = ""
    @State private var editedInterfaces: [String] = []
    @State private var hasUnsavedChanges: Bool = false
    @State private var isEditingName: Bool = false

    @State private var showingAddServiceSheet = false
    @State private var editingService: Service?
    @State private var showingDeleteConfirmation = false
    @State private var showingSaveBeforeEnablePrompt = false
    @State private var previousIsEnabled: Bool = false
    @State private var showingCannotDeleteEnvAlert = false
    @State private var showingCannotDeleteServiceAlert = false
    @State private var serviceToDelete: Service?

    private var environment: DevEnvironment? {
        appState.environments.first { $0.id == environmentId }
    }

    private var isActive: Bool {
        environment?.isEnabled ?? false
    }

    private var isTransitioning: Bool {
        environment?.isTransitioning ?? false
    }

    var body: some View {
        Group {
            if let env = environment {
                VStack(alignment: .leading, spacing: 0) {
                    // Header with environment name
                    headerView

                    Divider()

                    // Content
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            // Interfaces card
                            interfacesCard

                            // Services section
                            servicesSection(env: env)

                            Spacer(minLength: 20)

                            // Delete button at bottom
                            deleteSection
                        }
                        .padding(20)
                    }
                }
                .onAppear {
                    loadEnvironmentData(env)
                }
                .onChange(of: environmentId) { _ in
                    if let newEnv = environment {
                        loadEnvironmentData(newEnv)
                        previousIsEnabled = newEnv.isEnabled
                        isEditingName = false
                    }
                }
                .onChange(of: env.isEnabled) { newValue in
                    // Detect enabling with unsaved changes
                    if newValue && !previousIsEnabled && hasUnsavedChanges {
                        // Disable it back and show prompt
                        appState.toggleEnvironment(environmentId)
                        showingSaveBeforeEnablePrompt = true
                    }
                    previousIsEnabled = newValue
                }
                .alert("Unsaved Changes", isPresented: $showingSaveBeforeEnablePrompt) {
                    Button("Save & Enable") {
                        saveChanges()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            appState.toggleEnvironment(environmentId)
                        }
                    }
                    Button("Discard & Enable") {
                        if let env = environment {
                            loadEnvironmentData(env)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            appState.toggleEnvironment(environmentId)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("You have unsaved changes. Would you like to save them before enabling this environment?")
                }
                .sheet(isPresented: $showingAddServiceSheet) {
                    AddServiceSheet(
                        availableVariables: environment?.availableVariables ?? [],
                        onSave: { service in
                            appState.addService(to: environmentId, service: service)
                            showingAddServiceSheet = false
                        },
                        onCancel: {
                            showingAddServiceSheet = false
                        }
                    )
                }
                .sheet(item: $editingService) { service in
                    EditServiceSheet(
                        service: service,
                        availableVariables: environment?.availableVariables ?? [],
                        onSave: { updatedService in
                            appState.updateService(in: environmentId, service: updatedService)
                            editingService = nil
                        },
                        onCancel: {
                            editingService = nil
                        }
                    )
                }
                .confirmationDialog(
                    "Delete Environment?",
                    isPresented: $showingDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        appState.deleteEnvironment(environmentId)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will permanently delete \"\(env.name)\" and all its services.")
                }
                .alert("Cannot Delete Environment", isPresented: $showingCannotDeleteEnvAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    if isTransitioning {
                        Text("Please wait for the environment to finish starting or stopping before deleting.")
                    } else {
                        Text("Please deactivate the environment before deleting. Turn off the toggle switch first.")
                    }
                }
                .alert("Cannot Delete Service", isPresented: $showingCannotDeleteServiceAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    if isTransitioning {
                        Text("Please wait for the environment to finish starting or stopping before deleting services.")
                    } else {
                        Text("Please deactivate the environment before deleting services. Turn off the environment toggle first.")
                    }
                }
            } else {
                EmptyDetailView()
            }
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack(spacing: 12) {
            if isEditingName {
                // Edit mode: text field with save/cancel
                TextField("Environment Name", text: $editedName)
                    .textFieldStyle(.roundedBorder)
                    .font(.title2)
                    .frame(maxWidth: 300)

                Button("Save") {
                    saveChanges()
                    isEditingName = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Cancel") {
                    if let env = environment {
                        editedName = env.name
                    }
                    isEditingName = false
                    checkForChanges()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                // Display mode: name with edit button
                Text(editedName)
                    .font(.title2)
                    .fontWeight(.semibold)

                Button {
                    isEditingName = true
                } label: {
                    Image(systemName: "pencil")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(isActive || isTransitioning)
                .help("Edit environment name")
            }

            Spacer()

            // Unsaved changes indicator
            if hasUnsavedChanges && !isEditingName {
                Button("Save Changes") {
                    saveChanges()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isActive || isTransitioning)
            }

            // Add service button
            Button {
                showingAddServiceSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text("Add Service")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isTransitioning)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Interfaces Card

    private var interfacesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack {
                Image(systemName: "network")
                    .foregroundColor(.secondary)
                Text("INTERFACES")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 12)

            // Interfaces list in a card
            VStack(spacing: 0) {
                ForEach(Array(editedInterfaces.enumerated()), id: \.offset) { index, ip in
                    InterfaceRowCompact(
                        index: index,
                        ipAddress: Binding(
                            get: { editedInterfaces[index] },
                            set: { newValue in
                                editedInterfaces[index] = newValue
                                checkForChanges()
                            }
                        ),
                        isDisabled: isActive || isTransitioning,
                        canRemove: editedInterfaces.count > 1,
                        onRemove: {
                            editedInterfaces.remove(at: index)
                            checkForChanges()
                        }
                    )

                    if index < editedInterfaces.count - 1 {
                        Divider()
                            .padding(.leading, 60)
                    }
                }

                // Add interface button
                if !isActive && !isTransitioning {
                    Divider()

                    Button {
                        let newIP = suggestNextIP()
                        editedInterfaces.append(newIP)
                        checkForChanges()
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.accentColor)
                            Text("Add Interface")
                                .foregroundColor(.accentColor)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
    }

    // MARK: - Services Section

    private func servicesSection(env: DevEnvironment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Image(systemName: "server.rack")
                    .foregroundColor(.secondary)
                Text("SERVICES")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }

            ServiceListView(
                services: env.services,
                isEnvironmentActive: isActive,
                isEnvironmentTransitioning: env.isTransitioning,
                onToggle: { serviceId, _ in
                    appState.toggleServiceEnabled(
                        environmentId: environmentId,
                        serviceId: serviceId
                    )
                },
                onViewLogs: { service in
                    WindowCoordinator.shared.openLogWindow?(service.id)
                },
                onEdit: { service in
                    editingService = service
                },
                onDelete: { service in
                    if isActive || isTransitioning {
                        serviceToDelete = service
                        showingCannotDeleteServiceAlert = true
                    } else {
                        appState.deleteService(
                            from: environmentId,
                            serviceId: service.id
                        )
                    }
                },
                onRestart: { service in
                    restartService(service)
                },
                canToggleService: { serviceId in
                    appState.canToggleService(environmentId: environmentId, serviceId: serviceId)
                }
            )
        }
    }

    // MARK: - Delete Section

    private var deleteSection: some View {
        HStack {
            Spacer()
            Button(role: .destructive) {
                if isActive || isTransitioning {
                    showingCannotDeleteEnvAlert = true
                } else {
                    showingDeleteConfirmation = true
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                    Text("Delete Environment")
                }
                .font(.callout)
            }
            .buttonStyle(.plain)
            .foregroundColor(.red)
        }
    }

    // MARK: - Actions

    private func loadEnvironmentData(_ env: DevEnvironment) {
        editedName = env.name
        editedInterfaces = env.interfaces
        hasUnsavedChanges = false
        previousIsEnabled = env.isEnabled
    }

    private func checkForChanges() {
        guard let env = environment else {
            hasUnsavedChanges = false
            return
        }
        hasUnsavedChanges = editedName != env.name || editedInterfaces != env.interfaces
    }

    private func saveChanges() {
        guard var env = environment else { return }
        env.name = editedName
        env.interfaces = editedInterfaces
        appState.updateEnvironment(env)
        hasUnsavedChanges = false
    }

    private func restartService(_ service: Service) {
        appState.toggleServiceEnabled(environmentId: environmentId, serviceId: service.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            appState.toggleServiceEnabled(environmentId: environmentId, serviceId: service.id)
        }
    }

    private func suggestNextIP() -> String {
        let usedIPs = Set(appState.environments.flatMap { $0.interfaces })

        for i in 2...254 {
            let candidate = "127.0.0.\(i)"
            if !usedIPs.contains(candidate) && !editedInterfaces.contains(candidate) {
                return candidate
            }
        }

        return "127.0.1.1"
    }
}

/// Compact interface row for the new card layout
struct InterfaceRowCompact: View {
    let index: Int
    @Binding var ipAddress: String
    let isDisabled: Bool
    let canRemove: Bool
    let onRemove: () -> Void

    private var variableName: String {
        index == 0 ? "$IP" : "$IP\(index + 1)"
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(variableName)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 45, alignment: .leading)

            TextField("127.0.0.x", text: $ipAddress)
                .textFieldStyle(.plain)
                .disabled(isDisabled)

            Spacer()

            if canRemove && !isDisabled {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
                .help("Remove interface")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

/// Empty state when no environment is selected
struct EmptyDetailView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Select an Environment")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Choose an environment from the sidebar or create a new one")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    DetailView(environmentId: UUID())
        .environmentObject(AppState())
        .frame(width: 600, height: 500)
}
