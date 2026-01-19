import Foundation
import Combine

/// Central application state - single source of truth
@MainActor
final class AppState: ObservableObject {
    // MARK: - Published State

    @Published var environments: [DevEnvironment] = []
    @Published var selectedEnvironmentId: UUID?
    @Published var guestMode: Bool = false
    @Published var lastError: AppError?
    @Published var showHelperInstallPrompt: Bool = false
    @Published var showHelperUpgradePrompt: Bool = false

    /// Whether the privileged helper is installed
    var isHelperInstalled: Bool {
        networkManager?.isHelperInstalled ?? false
    }

    /// Whether the helper needs upgrading
    var helperNeedsUpgrade: Bool {
        networkManager?.needsUpgrade ?? false
    }

    // MARK: - Runtime State

    /// Previously active environments before guest mode
    var previouslyActiveEnvironmentIds: [UUID] = []

    /// Cooldown tracking to prevent rapid toggle clicks
    private var lastEnvironmentToggleTime: [UUID: Date] = [:]
    private var lastServiceToggleTime: [UUID: Date] = [:]

    /// Minimum cooldown period between toggles (milliseconds)
    private let toggleCooldownMs: Double = 500

    /// Cache for O(1) service-to-environment lookup (serviceId -> environmentId)
    private var serviceToEnvironmentCache: [UUID: UUID] = [:]

    // MARK: - Dependencies

    private let configManager = ConfigManager.shared
    private let validationService = ValidationService.shared
    private var processManager: ProcessManager?
    private var networkManager: NetworkManager?

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Properties

    var selectedEnvironment: DevEnvironment? {
        environments.first { $0.id == selectedEnvironmentId }
    }

    var hasActiveEnvironments: Bool {
        environments.contains { $0.isEnabled }
    }

    var sortedEnvironments: [DevEnvironment] {
        environments.sorted { $0.order < $1.order }
    }

    // MARK: - Service Lookup Cache

    /// Rebuild the service-to-environment cache for O(1) lookups
    private func rebuildServiceCache() {
        serviceToEnvironmentCache.removeAll()
        for env in environments {
            for service in env.services {
                serviceToEnvironmentCache[service.id] = env.id
            }
        }
    }

    /// Find environment and service indices by service ID using cache (O(1) lookup)
    private func findServiceIndices(serviceId: UUID) -> (envIndex: Int, serviceIndex: Int)? {
        guard let envId = serviceToEnvironmentCache[serviceId],
              let envIndex = environments.firstIndex(where: { $0.id == envId }),
              let serviceIndex = environments[envIndex].services.firstIndex(where: { $0.id == serviceId })
        else { return nil }
        return (envIndex, serviceIndex)
    }

    /// Get a service by ID using O(1) cache lookup (for views that need service data)
    func service(for serviceId: UUID) -> Service? {
        guard let (envIndex, serviceIndex) = findServiceIndices(serviceId: serviceId) else { return nil }
        return environments[envIndex].services[serviceIndex]
    }

    // MARK: - Initialization

    init() {
        loadConfiguration()
        setupAutoSave()
    }

    /// Inject managers after initialization (to avoid circular dependencies)
    func configure(processManager: ProcessManager, networkManager: NetworkManager) {
        self.processManager = processManager
        self.networkManager = networkManager
        setupProcessManagerCallbacks()
    }

    // MARK: - Configuration Loading/Saving

    private func loadConfiguration() {
        do {
            let config = try configManager.load()
            self.environments = config.environments
            // Select first environment if available
            self.selectedEnvironmentId = environments.first?.id
            // Build service lookup cache
            rebuildServiceCache()
        } catch {
            self.lastError = .configLoadFailed(error.localizedDescription)
            self.environments = []
        }
    }

    private func setupAutoSave() {
        // Debounce saves to avoid excessive disk writes
        $environments
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.saveConfiguration()
            }
            .store(in: &cancellables)
    }

    private func saveConfiguration() {
        do {
            try configManager.save(environments: environments)
        } catch {
            print("Failed to save configuration: \(error)")
        }
    }

    private func setupProcessManagerCallbacks() {
        processManager?.onLogOutput = { [weak self] serviceId, logEntry in
            Task { @MainActor in
                self?.appendLog(serviceId: serviceId, entry: logEntry)
            }
        }

        processManager?.onProcessExit = { [weak self] serviceId, exitCode in
            Task { @MainActor in
                self?.handleProcessExit(serviceId: serviceId, exitCode: exitCode)
            }
        }
    }

    // MARK: - Environment CRUD

    @discardableResult
    func createEnvironment() -> DevEnvironment {
        let nextIP = suggestNextIP()
        let newEnv = DevEnvironment(
            id: UUID(),
            name: generateUniqueEnvironmentName(),
            interfaces: [Interface(ip: nextIP)],
            services: [],
            order: environments.count
        )
        environments.append(newEnv)
        selectedEnvironmentId = newEnv.id
        return newEnv
    }

    func updateEnvironment(_ environment: DevEnvironment) {
        guard let index = environments.firstIndex(where: { $0.id == environment.id }) else { return }

        let oldEnv = environments[index]

        // Check if content changed (excluding history and runtime state)
        let contentChanged = oldEnv.name != environment.name ||
                             oldEnv.interfaces != environment.interfaces ||
                             oldEnv.services != environment.services

        var updated = environment

        // Preserve runtime state
        updated.isEnabled = oldEnv.isEnabled
        updated.isTransitioning = oldEnv.isTransitioning

        if contentChanged {
            // Create versioned snapshot of old state before update
            let snapshot = HistorySnapshot(from: oldEnv)
            // Prepend new snapshot and keep max 10
            updated.history = [snapshot] + oldEnv.history.prefix(9)
        } else {
            // Preserve existing history when no content change
            updated.history = oldEnv.history
        }

        environments[index] = updated
    }

    /// Restore an environment to a previous state from its history
    /// - Parameters:
    ///   - envId: The ID of the environment to restore
    ///   - snapshotIndex: The index of the snapshot to restore (0 = most recent)
    func restoreFromHistory(_ envId: UUID, snapshotIndex: Int) {
        guard let envIndex = environments.firstIndex(where: { $0.id == envId }),
              snapshotIndex >= 0,
              snapshotIndex < environments[envIndex].history.count
        else { return }

        let snapshot = environments[envIndex].history[snapshotIndex]

        // Create snapshot of current state before restoring (so restore is reversible)
        let currentSnapshot = HistorySnapshot(from: environments[envIndex])

        // Get migrated data (handles schema version differences)
        let restoredData = snapshot.migratedData()

        // Remove old service mappings from cache before restore
        for service in environments[envIndex].services {
            serviceToEnvironmentCache.removeValue(forKey: service.id)
        }

        // Restore from snapshot (preserve id, order, and runtime state)
        environments[envIndex].name = restoredData.name
        environments[envIndex].interfaces = restoredData.interfaces
        environments[envIndex].services = restoredData.services

        // Add restored service mappings to cache
        for service in environments[envIndex].services {
            serviceToEnvironmentCache[service.id] = envId
        }

        // Add current state to history (so user can undo the restore)
        environments[envIndex].history.insert(currentSnapshot, at: 0)
        // Keep max 10 entries
        environments[envIndex].history = Array(environments[envIndex].history.prefix(10))
    }

    func deleteEnvironment(_ id: UUID) {
        guard let env = environments.first(where: { $0.id == id }) else { return }

        // Deactivate first if active
        if env.isEnabled {
            deactivateEnvironment(id)
        }

        // Clean up cooldown tracking and cache for this environment and its services
        lastEnvironmentToggleTime.removeValue(forKey: id)
        for service in env.services {
            lastServiceToggleTime.removeValue(forKey: service.id)
            serviceToEnvironmentCache.removeValue(forKey: service.id)
        }

        environments.removeAll { $0.id == id }

        // Update selection
        if selectedEnvironmentId == id {
            selectedEnvironmentId = environments.first?.id
        }

        // Reorder remaining environments
        reorderEnvironments()
    }

    func moveEnvironment(from source: IndexSet, to destination: Int) {
        var sorted = sortedEnvironments
        sorted.move(fromOffsets: source, toOffset: destination)

        // Update order values
        for (index, env) in sorted.enumerated() {
            if let envIndex = environments.firstIndex(where: { $0.id == env.id }) {
                environments[envIndex].order = index
            }
        }
    }

    private func reorderEnvironments() {
        for (index, env) in sortedEnvironments.enumerated() {
            if let envIndex = environments.firstIndex(where: { $0.id == env.id }) {
                environments[envIndex].order = index
            }
        }
    }

    // MARK: - Service CRUD

    func addService(to environmentId: UUID, service: Service) {
        guard let index = environments.firstIndex(where: { $0.id == environmentId }) else { return }
        var newService = service
        newService.order = environments[index].services.count
        environments[index].services.append(newService)
        // Update cache
        serviceToEnvironmentCache[newService.id] = environmentId
    }

    func updateService(in environmentId: UUID, service: Service) {
        guard let envIndex = environments.firstIndex(where: { $0.id == environmentId }),
              let serviceIndex = environments[envIndex].services.firstIndex(where: { $0.id == service.id })
        else { return }

        // Preserve runtime state
        var updated = service
        updated.status = environments[envIndex].services[serviceIndex].status
        updated.restartCount = environments[envIndex].services[serviceIndex].restartCount
        updated.logs = environments[envIndex].services[serviceIndex].logs
        updated.lastError = environments[envIndex].services[serviceIndex].lastError

        environments[envIndex].services[serviceIndex] = updated
    }

    func deleteService(from environmentId: UUID, serviceId: UUID) {
        guard let envIndex = environments.firstIndex(where: { $0.id == environmentId }),
              let serviceIndex = environments[envIndex].services.firstIndex(where: { $0.id == serviceId })
        else { return }

        let service = environments[envIndex].services[serviceIndex]

        // Stop if running
        if service.status == .running || service.status == .starting {
            processManager?.stopProcess(for: serviceId) { }
        }

        // Clean up cooldown tracking and cache
        lastServiceToggleTime.removeValue(forKey: serviceId)
        serviceToEnvironmentCache.removeValue(forKey: serviceId)

        environments[envIndex].services.remove(at: serviceIndex)

        // Reorder remaining services
        for (idx, _) in environments[envIndex].services.enumerated() {
            environments[envIndex].services[idx].order = idx
        }
    }

    func toggleServiceEnabled(environmentId: UUID, serviceId: UUID) {
        guard let envIndex = environments.firstIndex(where: { $0.id == environmentId }),
              let serviceIndex = environments[envIndex].services.firstIndex(where: { $0.id == serviceId })
        else { return }

        let service = environments[envIndex].services[serviceIndex]
        let env = environments[envIndex]

        // Prevent toggle if environment is transitioning
        if env.isTransitioning {
            return
        }

        // Prevent toggle if service is transitioning
        if service.status.isTransitioning {
            return
        }

        // Enforce cooldown to prevent rapid clicks
        if let lastToggle = lastServiceToggleTime[serviceId] {
            let elapsed = Date().timeIntervalSince(lastToggle) * 1000
            if elapsed < toggleCooldownMs {
                return
            }
        }
        lastServiceToggleTime[serviceId] = Date()

        environments[envIndex].services[serviceIndex].isEnabled.toggle()

        let updatedService = environments[envIndex].services[serviceIndex]

        // If environment is active, start/stop the service
        if env.isEnabled {
            if updatedService.isEnabled {
                startService(serviceId: serviceId, in: envIndex)
            } else {
                stopService(serviceId: serviceId, in: envIndex)
            }
        }
    }

    /// Check if a service can be toggled (not transitioning and not in cooldown)
    func canToggleService(environmentId: UUID, serviceId: UUID) -> Bool {
        guard let env = environments.first(where: { $0.id == environmentId }),
              let service = env.services.first(where: { $0.id == serviceId })
        else { return false }

        // Can't toggle if environment is transitioning
        if env.isTransitioning {
            return false
        }

        // Can't toggle if service is transitioning
        if service.status.isTransitioning {
            return false
        }

        // Check cooldown
        if let lastToggle = lastServiceToggleTime[serviceId] {
            let elapsed = Date().timeIntervalSince(lastToggle) * 1000
            if elapsed < toggleCooldownMs {
                return false
            }
        }

        return true
    }

    // MARK: - Environment Activation

    func activateEnvironment(_ id: UUID) {
        guard let index = environments.firstIndex(where: { $0.id == id }),
              !environments[index].isEnabled,
              !environments[index].isTransitioning,
              let networkManager = networkManager,
              processManager != nil
        else { return }

        let env = environments[index]

        // Mark as transitioning
        environments[index].isTransitioning = true

        Task {
            do {
                // 1. Bring up interfaces
                try await networkManager.activateInterfaces(env.interfaces)

                // 2. Mark environment as enabled
                if let idx = environments.firstIndex(where: { $0.id == id }) {
                    environments[idx].isEnabled = true
                    environments[idx].isTransitioning = false

                    // 3. Start enabled services
                    for serviceIndex in environments[idx].services.indices {
                        let service = environments[idx].services[serviceIndex]
                        if service.isEnabled {
                            startService(serviceId: service.id, in: idx)
                        }
                    }
                }
            } catch {
                // Clear transitioning state on error
                if let idx = environments.firstIndex(where: { $0.id == id }) {
                    environments[idx].isTransitioning = false
                }
                self.lastError = .activationFailed(error.localizedDescription)
            }
        }
    }

    func deactivateEnvironment(_ id: UUID) {
        guard let index = environments.firstIndex(where: { $0.id == id }),
              environments[index].isEnabled,
              !environments[index].isTransitioning,
              let networkManager = networkManager,
              let processManager = processManager
        else { return }

        let env = environments[index]

        // Mark as transitioning
        environments[index].isTransitioning = true

        // 1. Stop all services
        let group = DispatchGroup()

        for serviceIndex in environments[index].services.indices {
            let service = environments[index].services[serviceIndex]
            if service.status.isActive {
                environments[index].services[serviceIndex].status = .stopping

                group.enter()
                processManager.stopProcess(for: service.id) { [weak self] in
                    Task { @MainActor in
                        if let self = self,
                           let envIdx = self.environments.firstIndex(where: { $0.id == id }),
                           let svcIdx = self.environments[envIdx].services.firstIndex(where: { $0.id == service.id }) {
                            self.environments[envIdx].services[svcIdx].status = .stopped
                            self.environments[envIdx].services[svcIdx].restartCount = 0
                        }
                        group.leave()
                    }
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }

            Task { @MainActor in
                // 2. Bring down interfaces
                await networkManager.deactivateInterfaces(env.interfaces)

                // 3. Mark environment as disabled and clear transitioning
                if let envIndex = self.environments.firstIndex(where: { $0.id == id }) {
                    self.environments[envIndex].isEnabled = false
                    self.environments[envIndex].isTransitioning = false
                }
            }
        }
    }

    func toggleEnvironment(_ id: UUID) {
        guard let env = environments.first(where: { $0.id == id }) else { return }

        // Prevent toggle if already transitioning
        if env.isTransitioning {
            return
        }

        // Enforce cooldown to prevent rapid clicks
        if let lastToggle = lastEnvironmentToggleTime[id] {
            let elapsed = Date().timeIntervalSince(lastToggle) * 1000
            if elapsed < toggleCooldownMs {
                return
            }
        }
        lastEnvironmentToggleTime[id] = Date()

        // Check if helper is installed and up-to-date before activating
        if !env.isEnabled {
            if !isHelperInstalled {
                showHelperInstallPrompt = true
                return
            }
            if helperNeedsUpgrade {
                showHelperUpgradePrompt = true
                return
            }
        }

        if env.isEnabled {
            deactivateEnvironment(id)
        } else {
            activateEnvironment(id)
        }
    }

    /// Check if an environment can be toggled (not transitioning and not in cooldown)
    func canToggleEnvironment(_ id: UUID) -> Bool {
        guard let env = environments.first(where: { $0.id == id }) else { return false }

        if env.isTransitioning {
            return false
        }

        if let lastToggle = lastEnvironmentToggleTime[id] {
            let elapsed = Date().timeIntervalSince(lastToggle) * 1000
            if elapsed < toggleCooldownMs {
                return false
            }
        }

        return true
    }

    /// Install or upgrade the privileged helper (requires admin auth)
    func installHelper() async {
        guard let networkManager = networkManager else { return }

        do {
            try await networkManager.installHelper()
            showHelperInstallPrompt = false
            showHelperUpgradePrompt = false
        } catch {
            lastError = .privilegeError(error.localizedDescription)
        }
    }

    // MARK: - Service Process Management

    private func startService(serviceId: UUID, in environmentIndex: Int) {
        guard environmentIndex < environments.count,
              let serviceIndex = environments[environmentIndex].services.firstIndex(where: { $0.id == serviceId }),
              let processManager = processManager
        else { return }

        let service = environments[environmentIndex].services[serviceIndex]
        let interfaces = environments[environmentIndex].interfaces
        let environmentId = environments[environmentIndex].id  // Capture ID, not index

        environments[environmentIndex].services[serviceIndex].status = .starting

        if processManager.spawnProcess(for: service, interfaces: interfaces) {
            // Schedule transition to running after 500ms if still running
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }

                // Look up by IDs, not captured indices
                if let envIdx = self.environments.firstIndex(where: { $0.id == environmentId }),
                   let svcIdx = self.environments[envIdx].services.firstIndex(where: { $0.id == serviceId }),
                   self.environments[envIdx].services[svcIdx].status == .starting,
                   processManager.isRunning(serviceId: serviceId) {
                    self.environments[envIdx].services[svcIdx].status = .running
                }
            }
        } else {
            environments[environmentIndex].services[serviceIndex].status = .failed
            environments[environmentIndex].services[serviceIndex].lastError = "Failed to spawn process"
        }
    }

    private func stopService(serviceId: UUID, in environmentIndex: Int) {
        guard environmentIndex < environments.count,
              let serviceIndex = environments[environmentIndex].services.firstIndex(where: { $0.id == serviceId }),
              let processManager = processManager
        else { return }

        let environmentId = environments[environmentIndex].id  // Capture ID, not index
        environments[environmentIndex].services[serviceIndex].status = .stopping

        processManager.stopProcess(for: serviceId) { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }

                // Look up by IDs, not captured indices
                if let envIdx = self.environments.firstIndex(where: { $0.id == environmentId }),
                   let svcIdx = self.environments[envIdx].services.firstIndex(where: { $0.id == serviceId }) {
                    self.environments[envIdx].services[svcIdx].status = .stopped
                }
            }
        }
    }

    // MARK: - Log Management

    private func appendLog(serviceId: UUID, entry: LogEntry) {
        guard let (envIndex, serviceIndex) = findServiceIndices(serviceId: serviceId) else { return }

        environments[envIndex].services[serviceIndex].logs.append(entry)

        // Enforce ring buffer limit (500 entries max per service)
        if environments[envIndex].services[serviceIndex].logs.count > 500 {
            environments[envIndex].services[serviceIndex].logs.removeFirst()
        }
    }

    func clearLogs(for serviceId: UUID) {
        guard let (envIndex, serviceIndex) = findServiceIndices(serviceId: serviceId) else { return }
        environments[envIndex].services[serviceIndex].logs.removeAll()
    }

    // MARK: - Process Exit Handling

    private func handleProcessExit(serviceId: UUID, exitCode: Int32) {
        guard let (envIndex, serviceIndex) = findServiceIndices(serviceId: serviceId) else { return }

        let wasExpected = environments[envIndex].services[serviceIndex].status == .stopping

        if wasExpected {
            environments[envIndex].services[serviceIndex].status = .stopped
        } else {
            environments[envIndex].services[serviceIndex].status = .failed
            environments[envIndex].services[serviceIndex].lastError = "Process exited with code \(exitCode)"
        }
    }

    // MARK: - App Lifecycle

    func stopAllEnvironments(completion: @escaping () -> Void) {
        let activeEnvs = environments.filter { $0.isEnabled || $0.isTransitioning }

        guard !activeEnvs.isEmpty else {
            completion()
            return
        }

        // Deactivate all environments
        for env in activeEnvs {
            if env.isEnabled && !env.isTransitioning {
                deactivateEnvironment(env.id)
            }
        }

        // Poll for completion with timeout
        var pollCount = 0
        let maxPolls = 100  // 10 seconds max (100 * 100ms)

        func checkCompletion() {
            pollCount += 1
            let stillActive = environments.contains { $0.isEnabled || $0.isTransitioning }

            if !stillActive || pollCount >= maxPolls {
                completion()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    checkCompletion()
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            checkCompletion()
        }
    }

    // MARK: - Helper Methods

    func suggestNextIP() -> String {
        let usedIPs = Set(environments.flatMap { $0.interfaceIPs })

        // Try 127.0.0.x range first
        for i in 2...254 {
            let candidate = "127.0.0.\(i)"
            if !usedIPs.contains(candidate) {
                return candidate
            }
        }

        // Fallback to 127.0.1.x range
        for i in 1...254 {
            let candidate = "127.0.1.\(i)"
            if !usedIPs.contains(candidate) {
                return candidate
            }
        }

        return "127.0.0.2"
    }

    private func generateUniqueEnvironmentName() -> String {
        let baseName = "New Environment"
        let existingNames = Set(environments.map { $0.name.lowercased() })

        if !existingNames.contains(baseName.lowercased()) {
            return baseName
        }

        var counter = 2
        while existingNames.contains("\(baseName) \(counter)".lowercased()) {
            counter += 1
        }

        return "\(baseName) \(counter)"
    }

    // MARK: - Export/Import

    /// Export an environment to JSON data
    func exportEnvironment(_ id: UUID) -> Data? {
        guard let env = environments.first(where: { $0.id == id }) else { return nil }

        let exportedEnv = ExportedEnvironment(from: env)
        let export = EnvironmentExport(environment: exportedEnv)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        return try? encoder.encode(export)
    }

    /// Validate import data and return a preview
    func validateImport(_ data: Data) -> Result<ImportPreview, ImportError> {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let export: EnvironmentExport
        do {
            export = try decoder.decode(EnvironmentExport.self, from: data)
        } catch {
            return .failure(.invalidJSON(error))
        }

        // Check version compatibility
        guard export.version == "1.0" else {
            return .failure(.unsupportedVersion(export.version))
        }

        let imported = export.environment

        // Check for empty data
        guard !imported.name.isEmpty else {
            return .failure(.emptyEnvironment)
        }

        // Validate IP addresses
        for interface in imported.interfaces {
            if !isValidIPAddress(interface.ip) {
                return .failure(.invalidIPFormat(interface.ip))
            }
        }

        // Check for name conflicts
        let existingNames = Set(environments.map { $0.name.lowercased() })
        let hasNameConflict = existingNames.contains(imported.name.lowercased())
        let suggestedName = hasNameConflict ? generateUniqueImportName(imported.name) : imported.name

        // Check for IP conflicts
        let usedIPs = Set(environments.flatMap { $0.interfaceIPs })
        let importedIPs = Set(imported.interfaces.map { $0.ip })
        let conflictingIPs = importedIPs.intersection(usedIPs)
        let hasIPConflicts = !conflictingIPs.isEmpty
        let suggestedInterfaces = hasIPConflicts
            ? suggestAlternativeInterfaces(for: imported.interfaces)
            : imported.interfaces

        return .success(ImportPreview(
            originalName: imported.name,
            originalInterfaces: imported.interfaces,
            services: imported.services,
            suggestedName: suggestedName,
            suggestedInterfaces: suggestedInterfaces,
            hasNameConflict: hasNameConflict,
            hasIPConflicts: hasIPConflicts,
            conflictingIPs: conflictingIPs
        ))
    }

    /// Import an environment from a validated preview
    @discardableResult
    func importEnvironment(_ preview: ImportPreview, name: String, useSuggestedIPs: Bool = true) -> DevEnvironment {
        let interfaces = useSuggestedIPs ? preview.suggestedInterfaces : preview.originalInterfaces

        // Create services with new UUIDs
        var newServices: [Service] = []
        for exportedService in preview.services {
            let service = Service(
                id: UUID(),
                name: exportedService.name,
                ports: exportedService.ports,
                command: exportedService.command,
                isEnabled: exportedService.isEnabled,
                order: exportedService.order
            )
            newServices.append(service)
        }

        let newEnv = DevEnvironment(
            id: UUID(),
            name: name,
            interfaces: interfaces,
            services: newServices,
            order: environments.count
        )

        environments.append(newEnv)
        selectedEnvironmentId = newEnv.id

        // Update cache for new services
        for service in newServices {
            serviceToEnvironmentCache[service.id] = newEnv.id
        }

        return newEnv
    }

    private func generateUniqueImportName(_ baseName: String) -> String {
        let existingNames = Set(environments.map { $0.name.lowercased() })
        let importedName = "\(baseName) (Imported)"

        if !existingNames.contains(importedName.lowercased()) {
            return importedName
        }

        var counter = 2
        while existingNames.contains("\(baseName) (Imported \(counter))".lowercased()) {
            counter += 1
        }

        return "\(baseName) (Imported \(counter))"
    }

    private func suggestAlternativeInterfaces(for interfaces: [Interface]) -> [Interface] {
        var usedIPs = Set(environments.flatMap { $0.interfaceIPs })
        var suggestedInterfaces: [Interface] = []

        for interface in interfaces {
            let nextIP = findNextAvailableIP(excluding: usedIPs)
            suggestedInterfaces.append(Interface(ip: nextIP, domain: interface.domain))
            usedIPs.insert(nextIP)
        }

        return suggestedInterfaces
    }

    private func findNextAvailableIP(excluding usedIPs: Set<String>) -> String {
        // Try 127.0.0.x range first
        for i in 2...254 {
            let candidate = "127.0.0.\(i)"
            if !usedIPs.contains(candidate) {
                return candidate
            }
        }

        // Fallback to 127.0.1.x range
        for i in 1...254 {
            let candidate = "127.0.1.\(i)"
            if !usedIPs.contains(candidate) {
                return candidate
            }
        }

        return "127.0.0.2"
    }

    private func isValidIPAddress(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return false }

        for part in parts {
            guard let num = Int(part), num >= 0, num <= 255 else {
                return false
            }
        }

        return true
    }
}

// MARK: - App Errors

enum AppError: LocalizedError, Identifiable {
    case configLoadFailed(String)
    case activationFailed(String)
    case privilegeError(String)

    var id: String { localizedDescription }

    var errorDescription: String? {
        switch self {
        case .configLoadFailed(let reason):
            return "Failed to load configuration: \(reason)"
        case .activationFailed(let reason):
            return "Failed to activate environment: \(reason)"
        case .privilegeError(let reason):
            return "Privilege error: \(reason)"
        }
    }
}
