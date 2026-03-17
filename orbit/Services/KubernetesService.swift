import Foundation
import os.log

private let logger = Logger(subsystem: "com.orbit.app", category: "KubernetesService")

// MARK: - Models

struct K8sService: Identifiable, Hashable {
    /// Deterministic ID from namespace/name — stable across refetches
    var id: String { "\(namespace)/\(name)" }
    let name: String
    let namespace: String
    let type: String
    let ports: [K8sPort]

    var hasPorts: Bool { !ports.isEmpty }
}

struct K8sPort: Hashable {
    let port: Int
    let name: String?
    let transportProtocol: String
}

// MARK: - Service

final class KubernetesService {
    private static let timeout: TimeInterval = 15

    // MARK: - Shell Execution

    /// Run a shell command and return stdout. Throws on timeout or non-zero exit.
    /// Dispatches to a background queue to avoid blocking the cooperative thread pool.
    /// Supports Swift Concurrency cancellation — terminates the process when the Task is cancelled.
    static func run(_ arguments: [String]) async throws -> String {
        let process = Process()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                    process.arguments = arguments

                    // GUI apps get minimal PATH — include common tool locations + Orbit's bin
                    var environment = ProcessInfo.processInfo.environment
                    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                    let orbitBinPath = appSupport.appendingPathComponent("Orbit/bin").path
                    let commonPaths = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                    let existingPath = environment["PATH"] ?? ""
                    environment["PATH"] = "\(orbitBinPath):\(commonPaths):\(existingPath)"
                    process.environment = environment

                    let stdout = Pipe()
                    let stderr = Pipe()
                    process.standardOutput = stdout
                    process.standardError = stderr

                    // Thread-safe accumulation of pipe data
                    let dataQueue = DispatchQueue(label: "com.orbit.k8s.pipedata")
                    var outData = Data()
                    var errData = Data()
                    stdout.fileHandleForReading.readabilityHandler = { handle in
                        let chunk = handle.availableData
                        dataQueue.sync { outData.append(chunk) }
                    }
                    stderr.fileHandleForReading.readabilityHandler = { handle in
                        let chunk = handle.availableData
                        dataQueue.sync { errData.append(chunk) }
                    }

                    do {
                        try process.run()
                    } catch {
                        continuation.resume(throwing: K8sError.commandFailed(error.localizedDescription))
                        return
                    }

                    // Timeout
                    let deadline = DispatchTime.now() + timeout
                    DispatchQueue.global().asyncAfter(deadline: deadline) {
                        if process.isRunning { process.terminate() }
                    }

                    process.waitUntilExit()

                    // Clean up handlers and read remaining data
                    stdout.fileHandleForReading.readabilityHandler = nil
                    stderr.fileHandleForReading.readabilityHandler = nil
                    let remainingOut = stdout.fileHandleForReading.readDataToEndOfFile()
                    let remainingErr = stderr.fileHandleForReading.readDataToEndOfFile()

                    let finalOut: Data = dataQueue.sync {
                        outData.append(remainingOut)
                        return outData
                    }
                    let finalErr: Data = dataQueue.sync {
                        errData.append(remainingErr)
                        return errData
                    }

                    guard process.terminationStatus == 0 else {
                        let errStr = String(data: finalErr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
                        continuation.resume(throwing: K8sError.commandFailed(errStr))
                        return
                    }

                    let output = String(data: finalOut, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    continuation.resume(returning: output)
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    // MARK: - Fetching

    static func fetchContexts() async throws -> [String] {
        let output = try await run(["kubectl", "config", "get-contexts", "-o", "name"])
        return parseContexts(from: output)
    }

    static func fetchCurrentContext() async throws -> String {
        try await run(["kubectl", "config", "current-context"])
    }

    static func fetchNamespaces(context: String) async throws -> [String] {
        let output = try await run(["kubectl", "get", "ns", "-o", "json", "--context", context])
        guard let data = output.data(using: .utf8) else { throw K8sError.parseError }
        return try parseNamespaces(from: data)
    }

    static func fetchServices(namespace: String, context: String) async throws -> [K8sService] {
        let output = try await run(["kubectl", "get", "svc", "-n", namespace, "-o", "json", "--context", context])
        guard let data = output.data(using: .utf8) else { throw K8sError.parseError }
        return try parseServices(from: data)
    }

    // MARK: - Parsing (static for testability)

    static func parseContexts(from output: String) -> [String] {
        output.components(separatedBy: .newlines).filter { !$0.isEmpty }
    }

    static func parseNamespaces(from data: Data) throws -> [String] {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let items = json?["items"] as? [[String: Any]] else { throw K8sError.parseError }
        return items.compactMap { item in
            (item["metadata"] as? [String: Any])?["name"] as? String
        }.sorted()
    }

    static func parseServices(from data: Data) throws -> [K8sService] {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let items = json?["items"] as? [[String: Any]] else { throw K8sError.parseError }

        return items.compactMap { item -> K8sService? in
            guard let metadata = item["metadata"] as? [String: Any],
                  let name = metadata["name"] as? String,
                  let namespace = metadata["namespace"] as? String,
                  let spec = item["spec"] as? [String: Any],
                  let type = spec["type"] as? String
            else { return nil }

            let portsArray = (spec["ports"] as? [[String: Any]]) ?? []
            let ports = portsArray.compactMap { portDict -> K8sPort? in
                guard let port = portDict["port"] as? Int else { return nil }
                return K8sPort(
                    port: port,
                    name: portDict["name"] as? String,
                    transportProtocol: (portDict["protocol"] as? String) ?? "TCP"
                )
            }

            return K8sService(name: name, namespace: namespace, type: type, ports: ports)
        }.sorted { $0.name < $1.name }
    }

    // MARK: - Service Generation

    static func generateCommand(for svc: K8sService, tool: String, context: String) -> String {
        let portMappings = svc.ports.map { "\($0.port):\($0.port)" }.joined(separator: " ")
        let escapedContext = shellEscape(context)
        let escapedNamespace = shellEscape(svc.namespace)
        let escapedName = shellEscape(svc.name)
        return "\(tool) port-forward --address $IP svc/\(escapedName) \(portMappings) -n \(escapedNamespace) --context \(escapedContext)"
    }

    static func portsString(for svc: K8sService) -> String {
        svc.ports.map { String($0.port) }.joined(separator: ",")
    }

    static func deduplicateName(_ name: String, existing: [String]) -> String {
        if !existing.contains(name) { return name }
        var suffix = 2
        while existing.contains("\(name)-\(suffix)") { suffix += 1 }
        return "\(name)-\(suffix)"
    }

    /// Shell-escape a string by wrapping in single quotes (handles internal single quotes)
    private static func shellEscape(_ value: String) -> String {
        // If it's a simple identifier, no escaping needed
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./:"))
        if value.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return value
        }
        // Wrap in single quotes, escaping internal single quotes
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}

// MARK: - Errors

enum K8sError: LocalizedError {
    case commandFailed(String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .commandFailed(let msg): return msg
        case .parseError: return "Failed to parse kubectl output"
        }
    }
}
