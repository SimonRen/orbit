import Foundation

/// Manages orphan cleanup registration with the privileged helper
///
/// This component registers the app with the helper daemon so that if the app
/// crashes or is force-quit, the helper can clean up any orphaned subprocesses.
@MainActor
final class OrphanRegistrar: ObservableObject {
    static let shared = OrphanRegistrar()

    @Published private(set) var isRegistered = false

    private let helperClient = HelperClient.shared
    private var processGroups: Set<pid_t> = []

    private init() {}

    // MARK: - Lifecycle

    /// Register this app with the helper for orphan monitoring
    func register() async {
        let myPid = ProcessInfo.processInfo.processIdentifier

        do {
            try await helperClient.registerApp(pid: myPid)
            isRegistered = true
            NSLog("OrphanRegistrar: Registered with helper (PID: \(myPid))")
        } catch {
            NSLog("OrphanRegistrar: Failed to register: \(error)")
            // Non-fatal - app continues without helper-based orphan protection
        }
    }

    /// Unregister from helper (graceful shutdown)
    func unregister() async {
        guard isRegistered else { return }

        do {
            try await helperClient.unregisterApp()
            isRegistered = false
            NSLog("OrphanRegistrar: Unregistered (graceful shutdown)")
        } catch {
            NSLog("OrphanRegistrar: Failed to unregister: \(error)")
            // Non-fatal - helper will detect app death anyway
        }
    }

    // MARK: - Process Group Management

    /// Add a process group to track
    func addProcessGroup(_ pgid: pid_t) {
        processGroups.insert(pgid)
        Task { await syncProcessGroups() }
    }

    /// Remove a process group from tracking
    func removeProcessGroup(_ pgid: pid_t) {
        processGroups.remove(pgid)
        Task { await syncProcessGroups() }
    }

    /// Sync all current process groups with helper
    private func syncProcessGroups() async {
        // Lazy re-registration: if not registered, try to register first
        if !isRegistered {
            await register()
        }

        guard isRegistered else { return }  // Still failed, skip sync

        let pgids = Array(processGroups).map { Int32($0) }

        do {
            try await helperClient.updateProcessGroups(pgids)
            NSLog("OrphanRegistrar: Synced \(pgids.count) process groups")
        } catch {
            NSLog("OrphanRegistrar: Failed to sync process groups: \(error)")
            // Helper may have restarted - mark as unregistered to force re-registration
            isRegistered = false
            // Retry registration and sync once
            await register()
            if isRegistered {
                try? await helperClient.updateProcessGroups(pgids)
            }
        }
    }
}
