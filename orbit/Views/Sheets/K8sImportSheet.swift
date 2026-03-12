import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.orbit.app", category: "K8sImportSheet")

struct K8sImportSheet: View {
    let environmentId: UUID
    let existingServiceNames: [String]
    let onImport: ([Service]) -> Void
    let onCancel: () -> Void

    // MARK: - State

    @State private var contexts: [String] = []
    @State private var selectedContext: String = ""
    @State private var namespaces: [String] = []
    @State private var selectedNamespace: String?
    @State private var services: [K8sService] = []
    @State private var selectedServiceIds: Set<String> = []
    @State private var allSelectedServices: [String: K8sService] = [:]  // accumulated across namespaces
    @State private var selectedTool: String = "kubectl"

    @State private var namespaceSearch: String = ""
    @State private var serviceSearch: String = ""

    @State private var isLoadingContexts = false
    @State private var isLoadingNamespaces = false
    @State private var isLoadingServices = false
    @State private var errorMessage: String?

    @State private var fetchTask: Task<Void, Never>?

    // MARK: - Computed

    private var filteredNamespaces: [String] {
        if namespaceSearch.isEmpty { return namespaces }
        return namespaces.filter { $0.localizedCaseInsensitiveContains(namespaceSearch) }
    }

    private var filteredServices: [K8sService] {
        if serviceSearch.isEmpty { return services }
        return services.filter { $0.name.localizedCaseInsensitiveContains(serviceSearch) }
    }

    private var selectedCount: Int { allSelectedServices.count }

    private var orbKubectlInstalled: Bool {
        ToolManager.shared.orbKubectlStatus != .notInstalled
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            topBar
            panelBody
            Divider()
            footerView
        }
        .frame(width: 700, height: 550)
        .onAppear { loadContexts() }
        .onDisappear { fetchTask?.cancel() }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Import from Kubernetes")
                    .font(.headline)
                Text("Select services to import as port-forward commands")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Top Bar (Context + Tool)

    private var topBar: some View {
        HStack(spacing: 12) {
            // Context picker
            VStack(alignment: .leading, spacing: 4) {
                Text("CONTEXT")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Picker("", selection: $selectedContext) {
                    ForEach(contexts, id: \.self) { ctx in
                        Text(ctx).tag(ctx)
                    }
                }
                .labelsHidden()
                .disabled(isLoadingContexts || contexts.isEmpty)
                .onChange(of: selectedContext) { _ in
                    loadNamespaces()
                }
            }

            Spacer()

            // Tool toggle
            VStack(alignment: .leading, spacing: 4) {
                Text("TOOL")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Picker("", selection: $selectedTool) {
                    Text("kubectl").tag("kubectl")
                    Text("orb-kubectl").tag("orb-kubectl")
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .disabled(!orbKubectlInstalled && selectedTool != "kubectl")
                .help(orbKubectlInstalled ? "" : "orb-kubectl is not installed")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Two-Panel Body

    private var panelBody: some View {
        HStack(spacing: 0) {
            namespacesPanel
            Divider()
            servicesPanel
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Namespaces Panel

    private var namespacesPanel: some View {
        VStack(spacing: 0) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.caption)
                TextField("Search namespaces", text: $namespaceSearch)
                    .textFieldStyle(.plain)
                    .font(.caption)
            }
            .padding(8)

            Divider()

            // List
            if isLoadingNamespaces {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
                Spacer()
            } else if namespaces.isEmpty && !isLoadingContexts {
                Spacer()
                Text(errorMessage ?? "No namespaces")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filteredNamespaces, id: \.self) { ns in
                            Button {
                                selectedNamespace = ns
                                loadServices()
                            } label: {
                                HStack {
                                    Text(ns)
                                        .font(.system(size: 12))
                                    Spacer()
                                    let nsCount = allSelectedServices.values.filter { $0.namespace == ns }.count
                                    if nsCount > 0 {
                                        Text("\(nsCount)")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Color.accentColor)
                                            .cornerRadius(8)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(selectedNamespace == ns ?
                                    Color.accentColor.opacity(0.2) : Color.clear)
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                }
            }
        }
        .frame(width: 180)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Services Panel

    private var servicesPanel: some View {
        VStack(spacing: 0) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.caption)
                TextField("Search services", text: $serviceSearch)
                    .textFieldStyle(.plain)
                    .font(.caption)
            }
            .padding(8)

            Divider()

            // Column headers
            HStack(spacing: 0) {
                Text("").frame(width: 28)
                Text("SERVICE").frame(maxWidth: .infinity, alignment: .leading)
                Text("TYPE").frame(width: 80, alignment: .leading)
                Text("PORTS").frame(width: 100, alignment: .leading)
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            // List
            if isLoadingServices {
                Spacer()
                ProgressView()
                    .scaleEffect(0.8)
                Spacer()
            } else if selectedNamespace == nil {
                Spacer()
                Text("Select a namespace")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            } else if services.isEmpty {
                Spacer()
                Text("No services found")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filteredServices) { svc in
                            serviceRow(svc)
                        }
                    }
                    .padding(4)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func serviceRow(_ svc: K8sService) -> some View {
        let isSelected = selectedServiceIds.contains(svc.id)
        let canSelect = svc.hasPorts

        return Button {
            guard canSelect else { return }
            if isSelected {
                selectedServiceIds.remove(svc.id)
                allSelectedServices.removeValue(forKey: svc.id)
            } else {
                selectedServiceIds.insert(svc.id)
                allSelectedServices[svc.id] = svc
            }
        } label: {
            HStack(spacing: 0) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(canSelect ? (isSelected ? .accentColor : .secondary) : .secondary.opacity(0.3))
                    .frame(width: 28)

                Text(svc.name)
                    .font(.system(size: 12))
                    .foregroundColor(canSelect ? .primary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(svc.type)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(width: 80, alignment: .leading)

                Text(svc.hasPorts ? svc.ports.map { String($0.port) }.joined(separator: ", ") : "—")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(width: 100, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .disabled(!canSelect)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            if errorMessage != nil && namespaces.isEmpty && services.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                    .font(.caption)
                Text(errorMessage ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            } else {
                Text("\(selectedCount) service\(selectedCount == 1 ? "" : "s") selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Cancel") { onCancel() }
                .keyboardShortcut(.cancelAction)

            Button("Import \(selectedCount) Service\(selectedCount == 1 ? "" : "s")") {
                importSelected()
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedCount == 0)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Data Loading

    private func loadContexts() {
        isLoadingContexts = true
        errorMessage = nil
        fetchTask?.cancel()
        fetchTask = Task {
            do {
                let ctxs = try await KubernetesService.fetchContexts()
                let current = try await KubernetesService.fetchCurrentContext()
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    contexts = ctxs
                    selectedContext = ctxs.contains(current) ? current : (ctxs.first ?? "")
                    isLoadingContexts = false
                    if !selectedContext.isEmpty { loadNamespaces() }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    isLoadingContexts = false
                    errorMessage = error.localizedDescription
                    logger.error("Failed to fetch contexts: \(error.localizedDescription)")
                }
            }
        }
    }

    private func loadNamespaces() {
        guard !selectedContext.isEmpty else { return }
        isLoadingNamespaces = true
        selectedNamespace = nil
        services = []
        selectedServiceIds = []
        allSelectedServices = [:]
        errorMessage = nil
        fetchTask?.cancel()
        fetchTask = Task {
            do {
                let ns = try await KubernetesService.fetchNamespaces(context: selectedContext)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    namespaces = ns
                    isLoadingNamespaces = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    isLoadingNamespaces = false
                    errorMessage = error.localizedDescription
                    logger.error("Failed to fetch namespaces: \(error.localizedDescription)")
                }
            }
        }
    }

    private func loadServices() {
        guard let ns = selectedNamespace else { return }
        isLoadingServices = true
        serviceSearch = ""
        fetchTask?.cancel()
        fetchTask = Task {
            do {
                let svcs = try await KubernetesService.fetchServices(namespace: ns, context: selectedContext)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    services = svcs
                    // Restore checkmarks for services previously selected in this namespace
                    selectedServiceIds = Set(svcs.map(\.id).filter { allSelectedServices[$0] != nil })
                    isLoadingServices = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    isLoadingServices = false
                    errorMessage = error.localizedDescription
                    logger.error("Failed to fetch services: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Import

    private func importSelected() {
        let selected = allSelectedServices.values.sorted { $0.id < $1.id }
        var existingNames = existingServiceNames
        var newServices: [Service] = []

        for svc in selected {
            let name = KubernetesService.deduplicateName(svc.name, existing: existingNames)
            existingNames.append(name)

            let service = Service(
                name: name,
                ports: KubernetesService.portsString(for: svc),
                command: KubernetesService.generateCommand(
                    for: svc, tool: selectedTool, context: selectedContext
                )
            )
            newServices.append(service)
        }

        onImport(newServices)
    }
}
