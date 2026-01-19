import Foundation

/// Wrapper for exported environment file
struct EnvironmentExport: Codable {
    let version: String
    let exportedAt: Date
    let environment: ExportedEnvironment

    init(environment: ExportedEnvironment) {
        self.version = "1.0"
        self.exportedAt = Date()
        self.environment = environment
    }
}

/// Environment data for export (excludes runtime state and IDs)
struct ExportedEnvironment: Codable {
    let name: String
    let interfaces: [Interface]
    let services: [ExportedService]

    private enum CodingKeys: String, CodingKey {
        case name, interfaces, services
    }

    init(from environment: DevEnvironment) {
        self.name = environment.name
        self.interfaces = environment.interfaces
        self.services = environment.sortedServices.map { ExportedService(from: $0) }
    }

    // Custom decoder to support both old [String] and new [Interface] formats
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        services = try container.decode([ExportedService].self, forKey: .services)

        // Try new Interface format first, fall back to old [String] format
        if let newInterfaces = try? container.decode([Interface].self, forKey: .interfaces) {
            interfaces = newInterfaces
        } else {
            let oldInterfaces = try container.decode([String].self, forKey: .interfaces)
            interfaces = oldInterfaces.map { Interface(ip: $0, domain: nil) }
        }
    }

    // Custom encoder for backward compatibility:
    // - If any interface has a domain, encode as [Interface] (new format)
    // - If no domains, encode as [String] (old format for older app versions)
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(services, forKey: .services)

        let hasDomains = interfaces.contains { $0.domain != nil && !$0.domain!.isEmpty }
        if hasDomains {
            // New format with Interface objects
            try container.encode(interfaces, forKey: .interfaces)
        } else {
            // Legacy format: just IP strings for backward compatibility
            try container.encode(interfaces.map { $0.ip }, forKey: .interfaces)
        }
    }
}

/// Service data for export (excludes runtime state and IDs)
struct ExportedService: Codable {
    let name: String
    let ports: String
    let command: String
    let isEnabled: Bool
    let order: Int

    init(from service: Service) {
        self.name = service.name
        self.ports = service.ports
        self.command = service.command
        self.isEnabled = service.isEnabled
        self.order = service.order
    }
}

// MARK: - Import Models

/// Result of validating an import file
struct ImportPreview: Identifiable {
    let id = UUID()
    let originalName: String
    let originalInterfaces: [Interface]
    let services: [ExportedService]
    let suggestedName: String
    let suggestedInterfaces: [Interface]
    let hasNameConflict: Bool
    let hasIPConflicts: Bool
    let conflictingIPs: Set<String>
}

/// Errors that can occur during import
enum ImportError: LocalizedError {
    case invalidFileFormat
    case unsupportedVersion(String)
    case invalidJSON(Error)
    case emptyEnvironment
    case invalidIPFormat(String)

    var errorDescription: String? {
        switch self {
        case .invalidFileFormat:
            return "The file format is not valid. Please select a valid .orbit.json file."
        case .unsupportedVersion(let version):
            return "Unsupported file version: \(version). This file may have been created with a newer version of Orbit."
        case .invalidJSON(let error):
            return "Failed to parse file: \(error.localizedDescription)"
        case .emptyEnvironment:
            return "The file contains no environment data."
        case .invalidIPFormat(let ip):
            return "Invalid IP address format: \(ip)"
        }
    }
}
