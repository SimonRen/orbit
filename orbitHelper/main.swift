import Foundation
import Security
import os.log

private let orphanLog = Logger(subsystem: "com.orbit.helper", category: "OrphanMonitor")
private let helperLog = Logger(subsystem: "com.orbit.helper", category: "HelperTool")

// MARK: - OrphanMonitor

/// Monitors the registered app and cleans up orphaned process groups on app death
class OrphanMonitor {
    struct Registration {
        let appPid: pid_t
        let registeredAt: Date
        var processGroups: Set<pid_t>
    }

    private var registration: Registration?
    private var dispatchSource: DispatchSourceProcess?
    private let queue = DispatchQueue(label: "com.orbit.helper.orphan-monitor")

    // MARK: - Public API

    func register(appPid: pid_t) -> (success: Bool, error: String?) {
        return queue.sync {
            // If different app was registered, clean it up first
            if let existing = registration, existing.appPid != appPid {
                orphanLog.info("Cleaning up stale registration for PID \(existing.appPid)")
                performCleanup(for: existing)
            }

            // Verify the PID is valid
            guard kill(appPid, 0) == 0 else {
                return (false, "Invalid PID: process does not exist")
            }

            // Create new registration
            registration = Registration(
                appPid: appPid,
                registeredAt: Date(),
                processGroups: []
            )

            // Start watching
            startWatching(pid: appPid)

            orphanLog.info("Registered app PID \(appPid)")
            return (true, nil)
        }
    }

    func updateProcessGroups(_ pgids: [pid_t]) -> (success: Bool, error: String?) {
        return queue.sync {
            guard let reg = registration else {
                return (false, "No app registered")
            }

            // Validate every PGID before accepting it: each must reference a
            // live process whose parent (or transitive ancestor) is the
            // registered app. This prevents a compromised app (or any signed
            // peer impersonating it) from convincing root to killpg unrelated
            // process groups on shutdown.
            var accepted = Set<pid_t>()
            for pgid in pgids {
                guard pgid > 0 else { continue }
                if pgidIsDescendantOf(pgid: pgid, ancestorPid: reg.appPid) {
                    accepted.insert(pgid)
                } else {
                    orphanLog.warning("Rejected PGID \(pgid): not a descendant of app PID \(reg.appPid)")
                }
            }

            registration?.processGroups = accepted
            orphanLog.info("Updated PGIDs (accepted): \(accepted)")
            return (true, nil)
        }
    }

    /// Check that a PGID belongs to a process whose ancestor chain includes
    /// the registered app PID. Walks parent PIDs via `kinfo_proc` until we
    /// hit the registered app, init (pid 1), or a missing process.
    private func pgidIsDescendantOf(pgid: pid_t, ancestorPid: pid_t) -> Bool {
        // The PGID is itself a PID — the process group leader. Start there.
        var current: pid_t = pgid
        var hops = 0
        while current > 1 && hops < 64 {
            if current == ancestorPid { return true }
            guard let parent = parentPid(of: current) else { return false }
            current = parent
            hops += 1
        }
        return false
    }

    /// Return the parent PID for `pid`, or nil if the process doesn't exist.
    private func parentPid(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard result == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    func unregister() -> (success: Bool, error: String?) {
        return queue.sync {
            stopWatching()
            registration = nil
            orphanLog.info("Unregistered (graceful shutdown)")
            return (true, nil)
        }
    }

    // MARK: - Private

    private func startWatching(pid: pid_t) {
        stopWatching() // Clear any existing watch

        dispatchSource = DispatchSource.makeProcessSource(
            identifier: pid,
            eventMask: .exit,
            queue: queue
        )

        dispatchSource?.setEventHandler { [weak self] in
            self?.onAppDeath()
        }

        // Don't nil dispatchSource in cancelHandler - it may already point to a new source
        // This prevents a race condition when re-registering

        dispatchSource?.resume()
        orphanLog.info("Started watching PID \(pid)")
    }

    private func stopWatching() {
        if let source = dispatchSource {
            dispatchSource = nil  // Nil BEFORE cancel to prevent race with cancelHandler
            source.cancel()
        }
    }

    private func onAppDeath() {
        guard let reg = registration else { return }

        orphanLog.warning("App PID \(reg.appPid) died, cleaning up \(reg.processGroups.count) process groups")
        performCleanup(for: reg)
        registration = nil
    }

    private func performCleanup(for reg: Registration) {
        // Phase 1: SIGTERM (graceful)
        for pgid in reg.processGroups {
            if pgid > 0 {
                let result = killpg(pgid, SIGTERM)
                if result == 0 {
                    orphanLog.info("Sent SIGTERM to PGID \(pgid)")
                } else {
                    orphanLog.error("killpg SIGTERM failed for PGID \(pgid): errno=\(errno)")
                }
            }
        }

        // Phase 2: Wait then SIGKILL (forced)
        let pgidsToKill = reg.processGroups
        DispatchQueue.global().asyncAfter(deadline: .now() + 3.0) {
            for pgid in pgidsToKill {
                if pgid > 0 {
                    let result = killpg(pgid, SIGKILL)
                    if result == 0 {
                        orphanLog.info("Sent SIGKILL to PGID \(pgid)")
                    }
                    // Don't log errors for SIGKILL - process may already be dead
                }
            }
        }
    }
}

// MARK: - HelperTool

/// Privileged helper tool for Orbit
/// Runs as root via launchd and handles network interface operations
class HelperTool: NSObject, NSXPCListenerDelegate, HelperProtocol {
    private let listener: NSXPCListener
    private let orphanMonitor = OrphanMonitor()

    /// Code signing requirement for the main app
    /// Matches: signed by our team ID with the correct bundle identifier
    private let codeSigningRequirement: SecRequirement? = {
        // Requirement: Must be signed by Apple (anchor apple generic) with our team ID and bundle ID
        // This ensures only our legitimately signed main app can connect
        let requirementString = """
            anchor apple generic and \
            identifier "com.orbit.app" and \
            certificate leaf[subject.OU] = "DN4YAHWP2P"
            """ as CFString

        var requirement: SecRequirement?
        let status = SecRequirementCreateWithString(requirementString, [], &requirement)
        if status != errSecSuccess {
            // Log error but continue - verification will fail safely
            helperLog.error("Failed to create code signing requirement: \(status)")
        }
        return requirement
    }()

    override init() {
        self.listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
        super.init()
        self.listener.delegate = self
    }

    func run() {
        listener.resume()
        RunLoop.current.run()
    }

    // MARK: - NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        // Verify the connecting process is signed by our team with correct bundle ID
        guard verifyCodeSignature(of: newConnection) else {
            helperLog.warning("Rejected connection - code signature verification failed")
            return false
        }

        newConnection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        newConnection.exportedObject = self

        newConnection.invalidationHandler = {
            // Connection was invalidated
        }

        newConnection.interruptionHandler = {
            // Connection was interrupted
        }

        newConnection.resume()
        return true
    }

    // MARK: - Code Signature Verification

    /// Verify that the connecting process has a valid code signature from our team
    private func verifyCodeSignature(of connection: NSXPCConnection) -> Bool {
        guard let requirement = codeSigningRequirement else {
            helperLog.error("No code signing requirement available")
            return false
        }

        // Get the connecting process's PID
        let pid = connection.processIdentifier

        // Create a SecCode object for the connecting process
        var code: SecCode?
        let codeStatus = SecCodeCopyGuestWithAttributes(
            nil,
            [kSecGuestAttributePid: pid] as CFDictionary,
            [],
            &code
        )

        guard codeStatus == errSecSuccess, let secCode = code else {
            helperLog.error("Failed to get SecCode for PID \(pid): \(codeStatus)")
            return false
        }

        // Verify the code satisfies our requirement
        let verifyStatus = SecCodeCheckValidity(secCode, [], requirement)

        if verifyStatus != errSecSuccess {
            helperLog.warning("Code signature verification failed for PID \(pid): \(verifyStatus)")
            return false
        }

        return true
    }

    // MARK: - HelperProtocol

    func addInterfaceAlias(_ ip: String, withReply reply: @escaping (Bool, String?) -> Void) {
        // Validate IP format (must be 127.x.x.x)
        guard isValidLoopbackIP(ip) else {
            reply(false, "Invalid IP address. Must be in 127.x.x.x range.")
            return
        }

        let result = executeCommand("/sbin/ifconfig", arguments: ["lo0", "alias", ip])
        reply(result.success, result.error)
    }

    func removeInterfaceAlias(_ ip: String, withReply reply: @escaping (Bool, String?) -> Void) {
        // Validate IP format (must be 127.x.x.x)
        guard isValidLoopbackIP(ip) else {
            reply(false, "Invalid IP address. Must be in 127.x.x.x range.")
            return
        }

        let result = executeCommand("/sbin/ifconfig", arguments: ["lo0", "-alias", ip])
        reply(result.success, result.error)
    }

    func getVersion(withReply reply: @escaping (String) -> Void) {
        reply(HelperConstants.helperVersion)
    }

    // MARK: - Orphan Cleanup Protocol

    func registerApp(pid: Int32, withReply reply: @escaping (Bool, String?) -> Void) {
        let result = orphanMonitor.register(appPid: pid)
        reply(result.success, result.error)
    }

    func updateProcessGroups(_ pgids: [Int32], withReply reply: @escaping (Bool, String?) -> Void) {
        let result = orphanMonitor.updateProcessGroups(pgids.map { pid_t($0) })
        reply(result.success, result.error)
    }

    func unregisterApp(withReply reply: @escaping (Bool, String?) -> Void) {
        let result = orphanMonitor.unregister()
        reply(result.success, result.error)
    }

    // MARK: - Self-Destruct

    func selfDestruct(withReply reply: @escaping (Bool, String?) -> Void) {
        // Best-effort delete of the on-disk artifacts that SMJobBless places
        // (paths are stable per Apple's SMJobBless contract and have been since
        // macOS 10.6).
        let paths = [
            "/Library/LaunchDaemons/com.orbit.helper.plist",
            "/Library/PrivilegedHelperTools/com.orbit.helper",
        ]
        var lastError: String?
        for path in paths {
            do {
                try FileManager.default.removeItem(atPath: path)
                helperLog.info("Self-destruct removed: \(path, privacy: .public)")
            } catch {
                let ns = error as NSError
                // Don't fail on "doesn't exist" — that's fine.
                if ns.domain == NSCocoaErrorDomain && ns.code == NSFileNoSuchFileError { continue }
                helperLog.error("Self-destruct failed to remove \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                lastError = error.localizedDescription
            }
        }

        reply(lastError == nil, lastError)

        // The reply must flush before we exit, so schedule the exit on the
        // run loop a moment later. The app will follow up with SMJobRemove
        // regardless.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            exit(0)
        }
    }

    // MARK: - Private Methods

    private func isValidLoopbackIP(_ ip: String) -> Bool {
        let components = ip.split(separator: ".")
        guard components.count == 4,
              let first = Int(components[0]),
              first == 127 else {
            return false
        }

        // Verify all components are valid numbers 0-255
        for component in components {
            guard let value = Int(component), value >= 0, value <= 255 else {
                return false
            }
        }

        return true
    }

    private func executeCommand(_ path: String, arguments: [String]) -> (success: Bool, error: String?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                return (true, nil)
            } else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                return (false, errorString.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }
}

// Start the helper
let helper = HelperTool()
helper.run()
