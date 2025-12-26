import Foundation

/// Manages spawning, monitoring, and terminating service processes
final class ProcessManager {
    static let shared = ProcessManager()

    /// Active processes keyed by service ID
    private var processes: [UUID: Process] = [:]

    /// Process group IDs for reliable cleanup (PGID == PID when we create new group)
    private var processGroups: [UUID: pid_t] = [:]

    /// Pipes for capturing output, keyed by service ID
    private var pipes: [UUID: (stdout: Pipe, stderr: Pipe)] = [:]

    /// Lock for thread-safe access to processes dictionary
    private let lock = NSLock()

    /// Callback for log output
    var onLogOutput: ((UUID, LogEntry) -> Void)?

    /// Callback for process exit
    var onProcessExit: ((UUID, Int32) -> Void)?

    private init() {}

    // MARK: - Process Lifecycle

    /// Spawns a process for the given service
    /// - Parameters:
    ///   - service: The service configuration
    ///   - interfaces: Array of IPs for variable substitution
    /// - Returns: true if spawn succeeded, false otherwise
    func spawnProcess(for service: Service, interfaces: [String]) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        // Prevent duplicate spawns
        guard processes[service.id] == nil else {
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")

        // Resolve variables in command
        let resolvedCommand = VariableResolver.resolve(service.command, interfaces: interfaces)

        // Get our app's PID for orphan detection
        let appPid = ProcessInfo.processInfo.processIdentifier

        // Wrap command with:
        // 1. trap to kill process group on exit (handles graceful termination)
        // 2. background monitor that watches parent PID and kills group if parent dies (handles force-quit/crash)
        // Note: We use 'kill 0' which sends signal to entire process group
        // The monitor polls every 0.5s for faster cleanup on parent death
        // We escape single quotes in the command to prevent bash injection
        let escapedCommand = resolvedCommand.replacingOccurrences(of: "'", with: "'\\''")
        let wrappedCommand = """
        trap 'kill 0 2>/dev/null' EXIT TERM INT HUP
        (while kill -0 \(appPid) 2>/dev/null; do sleep 0.5; done; kill 0 2>/dev/null) &
        _MONITOR_PID=$!
        eval '\(escapedCommand)'
        _EXIT_CODE=$?
        kill $_MONITOR_PID 2>/dev/null
        exit $_EXIT_CODE
        """
        process.arguments = ["-c", wrappedCommand]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        // Setup environment
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment

        // Setup pipes for stdout/stderr
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Capture stdout
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            if let str = String(data: data, encoding: .utf8) {
                let entry = LogEntry(
                    message: str.trimmingCharacters(in: .newlines),
                    stream: .stdout
                )
                self?.onLogOutput?(service.id, entry)
            }
        }

        // Capture stderr
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            if let str = String(data: data, encoding: .utf8) {
                let entry = LogEntry(
                    message: str.trimmingCharacters(in: .newlines),
                    stream: .stderr
                )
                self?.onLogOutput?(service.id, entry)
            }
        }

        // Handle termination
        process.terminationHandler = { [weak self] proc in
            self?.handleTermination(serviceId: service.id, process: proc)
        }

        do {
            try process.run()

            let pid = process.processIdentifier

            // Put process in its own process group for reliable cleanup
            // setpgid(pid, pid) creates a new process group with PGID == PID
            setpgid(pid, pid)
            processGroups[service.id] = pid

            processes[service.id] = process
            pipes[service.id] = (stdoutPipe, stderrPipe)

            // Log the startup
            let startEntry = LogEntry(
                message: "Starting: \(resolvedCommand) (PID: \(pid))",
                stream: .stdout
            )
            onLogOutput?(service.id, startEntry)

            return true
        } catch {
            let errorEntry = LogEntry(
                message: "Failed to start: \(error.localizedDescription)",
                stream: .stderr
            )
            onLogOutput?(service.id, errorEntry)
            return false
        }
    }

    /// Stops a process with graceful SIGTERM then forced SIGKILL
    /// - Parameters:
    ///   - serviceId: The service ID whose process to stop
    ///   - timeout: Seconds to wait before SIGKILL (default 3)
    ///   - completion: Called when process is fully stopped
    func stopProcess(for serviceId: UUID, timeout: TimeInterval = 3.0, completion: @escaping () -> Void) {
        lock.lock()
        guard let process = processes[serviceId] else {
            lock.unlock()
            completion()
            return
        }

        let pid = process.processIdentifier
        let pgid = processGroups[serviceId] ?? pid

        guard process.isRunning else {
            cleanup(serviceId: serviceId)
            lock.unlock()
            completion()
            return
        }
        lock.unlock()

        // Log the stop attempt
        let stopEntry = LogEntry(
            message: "Stopping process group (PGID: \(pgid))...",
            stream: .stdout
        )
        onLogOutput?(serviceId, stopEntry)

        // Kill entire process group with SIGTERM (negative PID kills the group)
        killpg(pgid, SIGTERM)

        // Also terminate the main process directly (belt and suspenders)
        process.terminate()

        // Poll for process exit - complete early if process dies quickly
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let startTime = Date()
            let pollInterval: TimeInterval = 0.1

            // Poll until process exits or timeout reached
            while process.isRunning && Date().timeIntervalSince(startTime) < timeout {
                Thread.sleep(forTimeInterval: pollInterval)
            }

            self?.lock.lock()
            defer { self?.lock.unlock() }

            if process.isRunning {
                // Log forced kill
                let killEntry = LogEntry(
                    message: "Force killing process group (timeout exceeded)",
                    stream: .stderr
                )
                self?.onLogOutput?(serviceId, killEntry)

                // Force kill entire process group
                killpg(pgid, SIGKILL)
                kill(pid, SIGKILL)

                // Brief wait for SIGKILL to take effect
                Thread.sleep(forTimeInterval: 0.1)
            }

            self?.cleanup(serviceId: serviceId)
            DispatchQueue.main.async {
                completion()
            }
        }
    }

    /// Checks if a process is running for the given service
    func isRunning(serviceId: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return processes[serviceId]?.isRunning ?? false
    }

    /// Stops all running processes (for app quit)
    func stopAllProcesses(completion: @escaping () -> Void) {
        lock.lock()
        let serviceIds = Array(processes.keys)
        lock.unlock()

        guard !serviceIds.isEmpty else {
            completion()
            return
        }

        let group = DispatchGroup()

        for serviceId in serviceIds {
            group.enter()
            stopProcess(for: serviceId, timeout: 3.0) {
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion()
        }
    }

    /// Get the process ID for a service (for debugging)
    func getProcessId(for serviceId: UUID) -> Int32? {
        lock.lock()
        defer { lock.unlock() }
        return processes[serviceId]?.processIdentifier
    }

    // MARK: - Private Methods

    private func handleTermination(serviceId: UUID, process: Process) {
        lock.lock()
        defer { lock.unlock() }

        // Clean up pipes
        if let servicePipes = pipes[serviceId] {
            servicePipes.stdout.fileHandleForReading.readabilityHandler = nil
            servicePipes.stderr.fileHandleForReading.readabilityHandler = nil
        }

        cleanup(serviceId: serviceId)

        // Notify about exit
        DispatchQueue.main.async { [weak self] in
            self?.onProcessExit?(serviceId, process.terminationStatus)
        }
    }

    private func cleanup(serviceId: UUID) {
        processes.removeValue(forKey: serviceId)
        processGroups.removeValue(forKey: serviceId)
        pipes.removeValue(forKey: serviceId)
    }
}
