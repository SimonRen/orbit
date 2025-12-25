import Foundation

/// Privileged helper tool for devfwd
/// Runs as root via launchd and handles network interface operations
class HelperTool: NSObject, NSXPCListenerDelegate, HelperProtocol {
    private let listener: NSXPCListener

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
        // Verify the connecting app is our main app
        // In production, add code signing verification here
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
