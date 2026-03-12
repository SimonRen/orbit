# K8s Service Import Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow users to import services from a live Kubernetes cluster into an Orbit environment with auto-generated port-forward commands.

**Architecture:** Two new files — `KubernetesService` (data fetching/parsing via kubectl shell commands) and `K8sImportSheet` (SwiftUI two-panel selection UI). The sheet calls the existing `AppState.addService()` API. No new dependencies.

**Tech Stack:** SwiftUI, Foundation (Process, JSONDecoder), existing kubectl/orb-kubectl binaries

**Spec:** `docs/superpowers/specs/2026-03-12-k8s-service-import-design.md`

---

## Chunk 1: KubernetesService (Data Layer)

### Task 1: K8s Models and Command Generation

**Files:**
- Create: `orbit/Services/KubernetesService.swift`
- Test: `orbitTests/orbitTests.swift` (append to existing test file)

- [ ] **Step 1: Write failing tests for JSON parsing and command generation**

Append to `orbitTests/orbitTests.swift`:

```swift
// MARK: - KubernetesService Tests

final class KubernetesServiceTests: XCTestCase {

    func testParseContexts() {
        let output = "docker-desktop\nminikube\nprod-cluster\n"
        let contexts = KubernetesService.parseContexts(from: output)
        XCTAssertEqual(contexts, ["docker-desktop", "minikube", "prod-cluster"])
    }

    func testParseContextsFiltersEmpty() {
        let output = "\ndocker-desktop\n\n"
        let contexts = KubernetesService.parseContexts(from: output)
        XCTAssertEqual(contexts, ["docker-desktop"])
    }

    func testParseNamespaces() throws {
        let json = """
        {
            "items": [
                {"metadata": {"name": "default"}},
                {"metadata": {"name": "kube-system"}},
                {"metadata": {"name": "monitoring"}}
            ]
        }
        """.data(using: .utf8)!
        let namespaces = try KubernetesService.parseNamespaces(from: json)
        XCTAssertEqual(namespaces, ["default", "kube-system", "monitoring"])
    }

    func testParseServices() throws {
        let json = """
        {
            "items": [
                {
                    "metadata": {"name": "api-gateway", "namespace": "default"},
                    "spec": {
                        "type": "ClusterIP",
                        "ports": [
                            {"port": 8080, "protocol": "TCP"}
                        ]
                    }
                },
                {
                    "metadata": {"name": "elasticsearch", "namespace": "default"},
                    "spec": {
                        "type": "ClusterIP",
                        "ports": [
                            {"port": 9200, "protocol": "TCP", "name": "http"},
                            {"port": 9300, "protocol": "TCP", "name": "transport"}
                        ]
                    }
                }
            ]
        }
        """.data(using: .utf8)!
        let services = try KubernetesService.parseServices(from: json)
        XCTAssertEqual(services.count, 2)
        XCTAssertEqual(services[0].name, "api-gateway")
        XCTAssertEqual(services[0].ports.count, 1)
        XCTAssertEqual(services[0].ports[0].port, 8080)
        XCTAssertEqual(services[1].name, "elasticsearch")
        XCTAssertEqual(services[1].ports.count, 2)
    }

    func testParseServicesWithZeroPorts() throws {
        let json = """
        {
            "items": [
                {
                    "metadata": {"name": "external-svc", "namespace": "default"},
                    "spec": {
                        "type": "ExternalName"
                    }
                }
            ]
        }
        """.data(using: .utf8)!
        let services = try KubernetesService.parseServices(from: json)
        XCTAssertEqual(services.count, 1)
        XCTAssertFalse(services[0].hasPorts)
    }

    func testCommandGenerationSinglePort() {
        let svc = K8sService(
            name: "postgres",
            namespace: "default",
            type: "ClusterIP",
            ports: [K8sPort(port: 5432, name: nil, transportProtocol: "TCP")]
        )
        let cmd = KubernetesService.generateCommand(
            for: svc, tool: "kubectl", context: "prod-cluster"
        )
        XCTAssertEqual(cmd, "kubectl port-forward --address $IP svc/postgres 5432:5432 -n default --context prod-cluster")
    }

    func testCommandGenerationMultiPort() {
        let svc = K8sService(
            name: "elasticsearch",
            namespace: "monitoring",
            type: "ClusterIP",
            ports: [
                K8sPort(port: 9200, name: "http", transportProtocol: "TCP"),
                K8sPort(port: 9300, name: "transport", transportProtocol: "TCP")
            ]
        )
        let cmd = KubernetesService.generateCommand(
            for: svc, tool: "orb-kubectl", context: "dev"
        )
        XCTAssertEqual(cmd, "orb-kubectl port-forward --address $IP svc/elasticsearch 9200:9200 9300:9300 -n monitoring --context dev")
    }

    func testPortsString() {
        let svc = K8sService(
            name: "es",
            namespace: "default",
            type: "ClusterIP",
            ports: [
                K8sPort(port: 9200, name: nil, transportProtocol: "TCP"),
                K8sPort(port: 9300, name: nil, transportProtocol: "TCP")
            ]
        )
        XCTAssertEqual(KubernetesService.portsString(for: svc), "9200,9300")
    }

    func testDuplicateNameSuffix() {
        let existing = ["api-gateway", "postgres", "api-gateway-2"]
        XCTAssertEqual(KubernetesService.deduplicateName("redis", existing: existing), "redis")
        XCTAssertEqual(KubernetesService.deduplicateName("api-gateway", existing: existing), "api-gateway-3")
        XCTAssertEqual(KubernetesService.deduplicateName("postgres", existing: existing), "postgres-2")
    }

    func testServiceCreation() {
        let k8sSvc = K8sService(
            name: "api-gateway",
            namespace: "production",
            type: "ClusterIP",
            ports: [
                K8sPort(port: 8080, name: "http", transportProtocol: "TCP"),
                K8sPort(port: 8443, name: "https", transportProtocol: "TCP")
            ]
        )
        let name = KubernetesService.deduplicateName(k8sSvc.name, existing: [])
        let service = Service(
            name: name,
            ports: KubernetesService.portsString(for: k8sSvc),
            command: KubernetesService.generateCommand(for: k8sSvc, tool: "kubectl", context: "prod")
        )
        XCTAssertEqual(service.name, "api-gateway")
        XCTAssertEqual(service.ports, "8080,8443")
        XCTAssertEqual(service.command, "kubectl port-forward --address $IP svc/api-gateway 8080:8080 8443:8443 -n production --context prod")
        XCTAssertTrue(service.isEnabled)
    }

    func testParseMalformedJSON() {
        let badData = "not json".data(using: .utf8)!
        XCTAssertThrowsError(try KubernetesService.parseNamespaces(from: badData))
        XCTAssertThrowsError(try KubernetesService.parseServices(from: badData))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodegen generate && xcodebuild -project orbit.xcodeproj -scheme orbit test -only-testing:orbitTests/KubernetesServiceTests 2>&1 | tail -5`
Expected: Build error — `KubernetesService` not found

- [ ] **Step 3: Implement KubernetesService**

Create `orbit/Services/KubernetesService.swift`:

```swift
import Foundation
import os.log

private let logger = Logger(subsystem: "com.orbit.app", category: "KubernetesService")

// MARK: - Models

struct K8sService: Identifiable, Hashable {
    /// Deterministic ID from namespace/name — stable across refetches
    var id: String { "\(namespace)/\(name)" }
    let name: String
    let namespace: String
    let type: String
    let ports: [K8sPort]

    var hasPorts: Bool { !ports.isEmpty }
}

struct K8sPort: Hashable {
    let port: Int
    let name: String?
    let transportProtocol: String
}

// MARK: - Service

final class KubernetesService {
    private static let timeout: TimeInterval = 15

    // MARK: - Shell Execution

    /// Run a shell command and return stdout. Throws on timeout or non-zero exit.
    /// Dispatches to a background queue to avoid blocking the cooperative thread pool.
    static func run(_ arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = arguments

                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr

                // Read pipe data asynchronously to prevent buffer deadlock
                var outData = Data()
                var errData = Data()
                stdout.fileHandleForReading.readabilityHandler = { handle in
                    outData.append(handle.availableData)
                }
                stderr.fileHandleForReading.readabilityHandler = { handle in
                    errData.append(handle.availableData)
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: K8sError.commandFailed(error.localizedDescription))
                    return
                }

                // Timeout
                let deadline = DispatchTime.now() + timeout
                DispatchQueue.global().asyncAfter(deadline: deadline) {
                    if process.isRunning { process.terminate() }
                }

                process.waitUntilExit()

                // Clean up handlers and read remaining data
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                outData.append(stdout.fileHandleForReading.readDataToEndOfFile())
                errData.append(stderr.fileHandleForReading.readDataToEndOfFile())

                guard process.terminationStatus == 0 else {
                    let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
                    continuation.resume(throwing: K8sError.commandFailed(errStr))
                    return
                }

                let output = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: output)
            }
        }
    }

    // MARK: - Fetching

    static func fetchContexts() async throws -> [String] {
        let output = try await run(["kubectl", "config", "get-contexts", "-o", "name"])
        return parseContexts(from: output)
    }

    static func fetchCurrentContext() async throws -> String {
        try await run(["kubectl", "config", "current-context"])
    }

    static func fetchNamespaces(context: String) async throws -> [String] {
        let output = try await run(["kubectl", "get", "ns", "-o", "json", "--context", context])
        guard let data = output.data(using: .utf8) else { throw K8sError.parseError }
        return try parseNamespaces(from: data)
    }

    static func fetchServices(namespace: String, context: String) async throws -> [K8sService] {
        let output = try await run(["kubectl", "get", "svc", "-n", namespace, "-o", "json", "--context", context])
        guard let data = output.data(using: .utf8) else { throw K8sError.parseError }
        return try parseServices(from: data)
    }

    // MARK: - Parsing (static for testability)

    static func parseContexts(from output: String) -> [String] {
        output.components(separatedBy: .newlines).filter { !$0.isEmpty }
    }

    static func parseNamespaces(from data: Data) throws -> [String] {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let items = json?["items"] as? [[String: Any]] else { throw K8sError.parseError }
        return items.compactMap { item in
            (item["metadata"] as? [String: Any])?["name"] as? String
        }.sorted()
    }

    static func parseServices(from data: Data) throws -> [K8sService] {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let items = json?["items"] as? [[String: Any]] else { throw K8sError.parseError }

        return items.compactMap { item -> K8sService? in
            guard let metadata = item["metadata"] as? [String: Any],
                  let name = metadata["name"] as? String,
                  let namespace = metadata["namespace"] as? String,
                  let spec = item["spec"] as? [String: Any],
                  let type = spec["type"] as? String
            else { return nil }

            let portsArray = (spec["ports"] as? [[String: Any]]) ?? []
            let ports = portsArray.compactMap { portDict -> K8sPort? in
                guard let port = portDict["port"] as? Int else { return nil }
                return K8sPort(
                    port: port,
                    name: portDict["name"] as? String,
                    transportProtocol: (portDict["protocol"] as? String) ?? "TCP"
                )
            }

            return K8sService(name: name, namespace: namespace, type: type, ports: ports)
        }.sorted { $0.name < $1.name }
    }

    // MARK: - Service Generation

    static func generateCommand(for svc: K8sService, tool: String, context: String) -> String {
        let portMappings = svc.ports.map { "\($0.port):\($0.port)" }.joined(separator: " ")
        return "\(tool) port-forward --address $IP svc/\(svc.name) \(portMappings) -n \(svc.namespace) --context \(context)"
    }

    static func portsString(for svc: K8sService) -> String {
        svc.ports.map { String($0.port) }.joined(separator: ",")
    }

    static func deduplicateName(_ name: String, existing: [String]) -> String {
        if !existing.contains(name) { return name }
        var suffix = 2
        while existing.contains("\(name)-\(suffix)") { suffix += 1 }
        return "\(name)-\(suffix)"
    }
}

// MARK: - Errors

enum K8sError: LocalizedError {
    case commandFailed(String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .commandFailed(let msg): return msg
        case .parseError: return "Failed to parse kubectl output"
        }
    }
}
```

- [ ] **Step 4: Regenerate project and run tests**

Run: `xcodegen generate && xcodebuild -project orbit.xcodeproj -scheme orbit test -only-testing:orbitTests/KubernetesServiceTests 2>&1 | tail -10`
Expected: All 10 tests PASS

- [ ] **Step 5: Commit**

```bash
git add orbit/Services/KubernetesService.swift orbitTests/orbitTests.swift
git commit -m "feat: add KubernetesService with kubectl JSON parsing and command generation"
```

---

## Chunk 2: K8sImportSheet (UI Layer)

### Task 2: K8s Import Sheet View

**Files:**
- Create: `orbit/Views/Sheets/K8sImportSheet.swift`

- [ ] **Step 1: Create K8sImportSheet**

Create `orbit/Views/Sheets/K8sImportSheet.swift`:

```swift
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

    private var selectedCount: Int { selectedServiceIds.count }

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
            } else {
                selectedServiceIds.insert(svc.id)
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
        selectedServiceIds = []
        serviceSearch = ""
        fetchTask?.cancel()
        fetchTask = Task {
            do {
                let svcs = try await KubernetesService.fetchServices(namespace: ns, context: selectedContext)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    services = svcs
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
        let selectedServices = services.filter { selectedServiceIds.contains($0.id) }
        var existingNames = existingServiceNames
        var newServices: [Service] = []

        for svc in selectedServices {
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
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodegen generate && xcodebuild -project orbit.xcodeproj -scheme orbit -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add orbit/Views/Sheets/K8sImportSheet.swift
git commit -m "feat: add K8sImportSheet with two-panel namespace/service browser"
```

---

## Chunk 3: Integration (Wire Up)

### Task 3: Add Import Button to DetailView

**Files:**
- Modify: `orbit/Views/MainWindow/DetailView.swift`

- [ ] **Step 1: Add state variable for the K8s import sheet**

In `DetailView.swift`, add near line 36 (alongside `showingAddServiceSheet`):

```swift
@State private var showingK8sImportSheet = false
```

- [ ] **Step 2: Add the "Import from K8s" button next to "Add Service"**

Replace the existing "Add service button" block (lines 373-383) — keep the Add Service button and add the K8s import button before it:

```swift
            // Import from K8s button
            Button {
                showingK8sImportSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "cube")
                    Text("Import from K8s")
                }
            }
            .disabled(isTransitioning)

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
```

- [ ] **Step 3: Add the sheet modifier**

After the existing `.sheet(isPresented: $showingAddServiceSheet)` block (around line 211), add:

```swift
.sheet(isPresented: $showingK8sImportSheet) {
    K8sImportSheet(
        environmentId: environmentId,
        existingServiceNames: environment?.services.map(\.name) ?? [],
        onImport: { services in
            for service in services {
                appState.addService(to: environmentId, service: service)
            }
            showingK8sImportSheet = false
        },
        onCancel: {
            showingK8sImportSheet = false
        }
    )
}
```

- [ ] **Step 4: Build and verify**

Run: `xcodegen generate && xcodebuild -project orbit.xcodeproj -scheme orbit -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Run all tests**

Run: `xcodebuild -project orbit.xcodeproj -scheme orbit test 2>&1 | tail -10`
Expected: All tests PASS (existing 50 + new 10 = 60 tests)

- [ ] **Step 6: Commit**

```bash
git add orbit/Views/MainWindow/DetailView.swift
git commit -m "feat: wire K8s import button into environment detail view"
```
