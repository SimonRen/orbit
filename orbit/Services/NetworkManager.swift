import Foundation

/// Error types for network operations
enum NetworkError: LocalizedError {
    case interfaceUpFailed(ip: String, reason: String)
    case interfaceDownFailed(ip: String, reason: String)
    case partialActivationFailed(activated: [String], failed: String, reason: String)
    case helperNotInstalled

    var errorDescription: String? {
        switch self {
        case .interfaceUpFailed(let ip, let reason):
            return "Failed to activate interface \(ip): \(reason)"
        case .interfaceDownFailed(let ip, let reason):
            return "Failed to deactivate interface \(ip): \(reason)"
        case .partialActivationFailed(let activated, let failed, let reason):
            return "Activation failed at \(failed): \(reason). Rolled back \(activated.count) interface(s)."
        case .helperNotInstalled:
            return "Privileged helper not installed. Please install it from Settings."
        }
    }
}

/// Manages loopback interface aliases via privileged helper
@MainActor
final class NetworkManager {
    static let shared = NetworkManager()

    private let helperClient = HelperClient.shared

    /// Whether the privileged helper is installed
    var isHelperInstalled: Bool {
        helperClient.isHelperInstalled
    }

    /// Whether the helper needs to be upgraded to a newer version
    var needsUpgrade: Bool {
        helperClient.needsUpgrade
    }

    /// The currently installed helper version (nil if not installed)
    var installedVersion: String? {
        helperClient.installedVersion
    }

    private init() {}

    // MARK: - Helper Installation

    /// Install the privileged helper (one-time, requires admin auth)
    func installHelper() async throws {
        try await helperClient.installHelper()
    }

    /// Check helper status
    func checkHelperStatus() {
        helperClient.checkHelperStatus()
    }

    // MARK: - Interface Operations

    /// Brings up an interface alias on lo0
    /// - Parameter ip: The IP address to alias (must be 127.x.x.x)
    /// - Throws: NetworkError if the operation fails
    func bringUpInterface(_ ip: String) async throws {
        do {
            try await helperClient.addInterfaceAlias(ip)
        } catch {
            throw NetworkError.interfaceUpFailed(ip: ip, reason: error.localizedDescription)
        }
    }

    /// Removes an interface alias from lo0
    /// - Parameter ip: The IP address to remove
    /// - Throws: NetworkError if the operation fails
    func bringDownInterface(_ ip: String) async throws {
        do {
            try await helperClient.removeInterfaceAlias(ip)
        } catch {
            throw NetworkError.interfaceDownFailed(ip: ip, reason: error.localizedDescription)
        }
    }

    /// Activates all interfaces for an environment with rollback on failure
    /// - Parameter interfaces: Array of Interface objects to activate
    /// - Throws: NetworkError if any interface fails (after rolling back)
    func activateInterfaces(_ interfaces: [Interface]) async throws {
        var activated: [String] = []

        for interface in interfaces {
            let ip = interface.ip
            do {
                try await bringUpInterface(ip)
                activated.append(ip)
            } catch {
                // Rollback: remove all interfaces we already added
                for activatedIP in activated {
                    try? await bringDownInterface(activatedIP)
                }

                throw NetworkError.partialActivationFailed(
                    activated: activated,
                    failed: ip,
                    reason: error.localizedDescription
                )
            }
        }
    }

    /// Deactivates all interfaces for an environment
    /// - Parameter interfaces: Array of Interface objects to deactivate
    /// - Note: This is best-effort and won't throw on individual failures
    func deactivateInterfaces(_ interfaces: [Interface]) async {
        for interface in interfaces {
            // Best effort - don't fail if some can't be removed
            try? await bringDownInterface(interface.ip)
        }
    }

    // MARK: - Utility Methods

    /// Check if an interface alias is currently active
    /// - Parameter ip: The IP address to check
    /// - Returns: true if the interface is active
    nonisolated func isInterfaceActive(_ ip: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
        process.arguments = ["lo0"]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                return output.contains(ip)
            }
        } catch {
            // Silently fail - assume not active
        }

        return false
    }
}
