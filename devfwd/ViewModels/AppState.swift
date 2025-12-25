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

    /// Whether the privileged helper is installed
    var isHelperInstalled: Bool {
        networkManager?.isHelperInstalled ?? false
    }

    // MARK: - Runtime State

    /// Previously active environments before guest mode
    var previouslyActiveEnvironmentIds: [UUID] = []

    /// Cooldown tracking to prevent rapid toggle clicks
    private var lastEnvironmentToggleTime: [UUID: Date] = [:]
    private var lastServiceToggleTime: [UUID: Date] = [:]

    /// Minimum cooldown period between toggles (milliseconds)
    private let toggleCooldownMs: Double = 500

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
            interfaces: [nextIP],
            services: [],
            order: environments.count
        )
        environments.append(newEnv)
        selectedEnvironmentId = newEnv.id
        return newEnv
    }

    func updateEnvironment(_ environment: DevEnvironment) {
        guard let index = environments.firstIndex(where: { $0.id == environment.id }) else { return }
        // Preserve runtime state
        var updated = environment
        updated.isEnabled = environments[index].isEnabled
        updated.isTransitioning = environments[index].isTransitioning
        environments[index] = updated
    }

    func deleteEnvironment(_ id: UUID) {
        guard let env = environments.first(where: { $0.id == id }) else { return }

        // Deactivate first if active
        if env.isEnabled {
            deactivateEnvironment(id)
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

        // Check if helper is installed before activating
        if !env.isEnabled && !isHelperInstalled {
            showHelperInstallPrompt = true
            return
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

    /// Install the privileged helper (one-time admin auth)
    func installHelper() async {
        guard let networkManager = networkManager else { return }

        do {
            try await networkManager.installHelper()
            showHelperInstallPrompt = false
        } catch {
            lastError = .privilegeError(error.localizedDescription)
        }
    }

    // MARK: - Service Process Management

    private func startService(serviceId: UUID, in environmentIndex: Int) {
        guard let serviceIndex = environments[environmentIndex].services.firstIndex(where: { $0.id == serviceId }),
              let processManager = processManager
        else { return }

        let service = environments[environmentIndex].services[serviceIndex]
        let interfaces = environments[environmentIndex].interfaces

        environments[environmentIndex].services[serviceIndex].status = .starting

        if processManager.spawnProcess(for: service, interfaces: interfaces) {
            // Schedule transition to running after 3 seconds if still running
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard let self = self else { return }

                if let envIdx = self.environments.firstIndex(where: { $0.id == self.environments[environmentIndex].id }),
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
        guard let serviceIndex = environments[environmentIndex].services.firstIndex(where: { $0.id == serviceId }),
              let processManager = processManager
        else { return }

        environments[environmentIndex].services[serviceIndex].status = .stopping

        processManager.stopProcess(for: serviceId) { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }

                if let envIdx = self.environments.firstIndex(where: { $0.id == self.environments[environmentIndex].id }),
                   let svcIdx = self.environments[envIdx].services.firstIndex(where: { $0.id == serviceId }) {
                    self.environments[envIdx].services[svcIdx].status = .stopped
                }
            }
        }
    }

    // MARK: - Log Management

    private func appendLog(serviceId: UUID, entry: LogEntry) {
        for envIndex in environments.indices {
            if let serviceIndex = environments[envIndex].services.firstIndex(where: { $0.id == serviceId }) {
                environments[envIndex].services[serviceIndex].logs.append(entry)

                // Enforce ring buffer limit (10k entries)
                if environments[envIndex].services[serviceIndex].logs.count > 10000 {
                    environments[envIndex].services[serviceIndex].logs.removeFirst()
                }
                return
            }
        }
    }

    func clearLogs(for serviceId: UUID) {
        for envIndex in environments.indices {
            if let serviceIndex = environments[envIndex].services.firstIndex(where: { $0.id == serviceId }) {
                environments[envIndex].services[serviceIndex].logs.removeAll()
                return
            }
        }
    }

    // MARK: - Process Exit Handling

    private func handleProcessExit(serviceId: UUID, exitCode: Int32) {
        for envIndex in environments.indices {
            if let serviceIndex = environments[envIndex].services.firstIndex(where: { $0.id == serviceId }) {
                let wasExpected = environments[envIndex].services[serviceIndex].status == .stopping

                if wasExpected {
                    environments[envIndex].services[serviceIndex].status = .stopped
                } else {
                    environments[envIndex].services[serviceIndex].status = .failed
                    environments[envIndex].services[serviceIndex].lastError = "Process exited with code \(exitCode)"
                }
                return
            }
        }
    }

    // MARK: - App Lifecycle

    func stopAllEnvironments(completion: @escaping () -> Void) {
        let activeIds = environments.filter { $0.isEnabled }.map { $0.id }

        guard !activeIds.isEmpty else {
            completion()
            return
        }

        let group = DispatchGroup()

        for id in activeIds {
            group.enter()
            deactivateEnvironment(id)
            // Give some time for deactivation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion()
        }
    }

    // MARK: - Helper Methods

    func suggestNextIP() -> String {
        let usedIPs = Set(environments.flatMap { $0.interfaces })

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
