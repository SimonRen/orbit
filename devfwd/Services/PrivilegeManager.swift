import Foundation
import AppKit

/// Error types for privilege operations
enum PrivilegeError: LocalizedError {
    case scriptCreationFailed
    case authorizationDenied
    case executionFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .scriptCreationFailed:
            return "Failed to create privilege escalation script"
        case .authorizationDenied:
            return "Administrator privileges required. Please try again."
        case .executionFailed(let reason):
            return "Privileged operation failed: \(reason)"
        }
    }
}

/// Handles privileged operations requiring administrator access
final class PrivilegeManager {
    static let shared = PrivilegeManager()

    private init() {}

    // MARK: - Public Methods

    /// Executes a command with administrator privileges using osascript
    /// - Parameter command: The shell command to execute
    /// - Throws: PrivilegeError if authorization fails or command errors
    func executePrivileged(_ command: String) throws {
        // Ensure app is active so password dialog can receive input
        if Thread.isMainThread {
            NSApp.activate(ignoringOtherApps: true)
        } else {
            DispatchQueue.main.sync {
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        // Escape special characters for AppleScript
        let escapedCommand = escapeForAppleScript(command)

        let script = """
        do shell script "\(escapedCommand)" with administrator privileges
        """

        var error: NSDictionary?
        guard let scriptObject = NSAppleScript(source: script) else {
            throw PrivilegeError.scriptCreationFailed
        }

        let _ = scriptObject.executeAndReturnError(&error)

        if let error = error {
            let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            let errorNumber = error[NSAppleScript.errorNumber] as? Int ?? -1

            // -128 is user cancelled
            if errorNumber == -128 {
                throw PrivilegeError.authorizationDenied
            }

            throw PrivilegeError.executionFailed(reason: errorMessage)
        }
    }

    /// Executes a command with administrator privileges asynchronously
    /// - Parameter command: The shell command to execute
    /// - Returns: Result indicating success or failure
    func executePrivilegedAsync(_ command: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try self.executePrivileged(command)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Executes multiple commands with a single authorization prompt
    /// - Parameter commands: Array of shell commands to execute
    /// - Throws: PrivilegeError if authorization fails or any command errors
    func executePrivilegedBatch(_ commands: [String]) throws {
        let combinedCommand = commands.joined(separator: " && ")
        try executePrivileged(combinedCommand)
    }

    // MARK: - Private Methods

    private func escapeForAppleScript(_ string: String) -> String {
        var result = string
        // Escape backslashes first, then quotes
        result = result.replacingOccurrences(of: "\\", with: "\\\\")
        result = result.replacingOccurrences(of: "\"", with: "\\\"")
        return result
    }
}
