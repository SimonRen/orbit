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
    static func run(_ arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = arguments

                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr

                // Read pipe data asynchronously to prevent buffer deadlock
                var outData = Data()
                var errData = Data()
                stdout.fileHandleForReading.readabilityHandler = { handle in
                    outData.append(handle.availableData)
                }
                stderr.fileHandleForReading.readabilityHandler = { handle in
                    errData.append(handle.availableData)
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
                outData.append(stdout.fileHandleForReading.readDataToEndOfFile())
                errData.append(stderr.fileHandleForReading.readDataToEndOfFile())

                guard process.terminationStatus == 0 else {
                    let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
                    continuation.resume(throwing: K8sError.commandFailed(errStr))
                    return
                }

                let output = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: output)
            }
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
        return "\(tool) port-forward --address $IP svc/\(svc.name) \(portMappings) -n \(svc.namespace) --context \(context)"
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
