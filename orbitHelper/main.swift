import Foundation
import Security

/// Privileged helper tool for Orbit
/// Runs as root via launchd and handles network interface operations
class HelperTool: NSObject, NSXPCListenerDelegate, HelperProtocol {
    private let listener: NSXPCListener

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
            NSLog("HelperTool: Failed to create code signing requirement: \(status)")
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
            NSLog("HelperTool: Rejected connection - code signature verification failed")
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
            NSLog("HelperTool: No code signing requirement available")
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
            NSLog("HelperTool: Failed to get SecCode for PID \(pid): \(codeStatus)")
            return false
        }

        // Verify the code satisfies our requirement
        let verifyStatus = SecCodeCheckValidity(secCode, [], requirement)

        if verifyStatus != errSecSuccess {
            NSLog("HelperTool: Code signature verification failed for PID \(pid): \(verifyStatus)")
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
