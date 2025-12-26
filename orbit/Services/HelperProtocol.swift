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
    static let helperVersion = "1.0.0"
}
