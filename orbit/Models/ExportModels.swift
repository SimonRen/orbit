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
    let interfaces: [String]
    let services: [ExportedService]

    init(from environment: DevEnvironment) {
        self.name = environment.name
        self.interfaces = environment.interfaces
        self.services = environment.sortedServices.map { ExportedService(from: $0) }
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
    let originalInterfaces: [String]
    let services: [ExportedService]
    let suggestedName: String
    let suggestedInterfaces: [String]
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
