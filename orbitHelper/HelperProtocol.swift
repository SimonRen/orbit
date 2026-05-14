import Foundation

/// XPC Protocol for privileged helper communication
@objc(HelperProtocol)
protocol HelperProtocol {
    /// Add a loopback interface alias
    /// - Parameters:
    ///   - ip: The IP address to add (e.g., "127.0.0.2")
    ///   - reply: Callback with success status and optional error message
    func addInterfaceAlias(_ ip: String, withReply reply: @escaping (Bool, String?) -> Void)

    /// Remove a loopback interface alias
    /// - Parameters:
    ///   - ip: The IP address to remove
    ///   - reply: Callback with success status and optional error message
    func removeInterfaceAlias(_ ip: String, withReply reply: @escaping (Bool, String?) -> Void)

    /// Check if the helper is running and responsive
    /// - Parameter reply: Callback with the helper version string
    func getVersion(withReply reply: @escaping (String) -> Void)

    // MARK: - Orphan Cleanup

    /// Register this app for orphan process monitoring
    /// - Parameters:
    ///   - pid: The app's process ID
    ///   - reply: Callback with success status and optional error message
    func registerApp(pid: Int32, withReply reply: @escaping (Bool, String?) -> Void)

    /// Update the list of process groups to clean up if the app dies
    /// - Parameters:
    ///   - pgids: Array of process group IDs
    ///   - reply: Callback with success status and optional error message
    func updateProcessGroups(_ pgids: [Int32], withReply reply: @escaping (Bool, String?) -> Void)

    /// Unregister from orphan monitoring (graceful shutdown)
    /// - Parameter reply: Callback with success status and optional error message
    func unregisterApp(withReply reply: @escaping (Bool, String?) -> Void)

    // MARK: - Self-Destruct (helper v1.3.0+)

    /// Delete the helper's own on-disk binary and launchd plist as root,
    /// then exit. Called by the app immediately before SMJobRemove so the
    /// uninstall is a real uninstall (SMJobRemove alone leaves the files
    /// at /Library/PrivilegedHelperTools/ and /Library/LaunchDaemons/
    /// intact, where they linger forever as root-owned dead files).
    ///
    /// Added in helper v1.3.0. Old helpers don't implement this — the
    /// client should fall back to plain SMJobRemove if this call fails.
    func selfDestruct(withReply reply: @escaping (Bool, String?) -> Void)
}

/// Protocol for the app to receive callbacks from helper
@objc(HelperProgressProtocol)
protocol HelperProgressProtocol {
    /// Report progress or status updates
    func progressUpdate(_ message: String)
}

/// Helper identification constants
enum HelperConstants {
    static let machServiceName = "com.orbit.helper"
    static let helperVersion = "1.3.0"  // Added selfDestruct + PGID descendant validation
}
