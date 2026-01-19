import Foundation

// MARK: - Bulk Export Models

/// Manifest for bulk export ZIP archive
struct BulkExportManifest: Codable {
    let version: String
    let exportedAt: Date
    let appVersion: String
    let environmentCount: Int
    let environments: [BulkExportEnvironmentRef]

    init(environments: [DevEnvironment], appVersion: String) {
        self.version = "1.0"
        self.exportedAt = Date()
        self.appVersion = appVersion
        self.environmentCount = environments.count

        // Generate unique filenames for each environment
        var usedFilenames = Set<String>()
        var refs: [BulkExportEnvironmentRef] = []

        for env in environments {
            let filename = BulkExportManifest.uniqueFilename(for: env.name, excluding: usedFilenames)
            usedFilenames.insert(filename)
            refs.append(BulkExportEnvironmentRef(filename: filename, name: env.name))
        }

        self.environments = refs
    }

    /// Generate a unique safe filename from environment name
    static func uniqueFilename(for name: String, excluding usedFilenames: Set<String>) -> String {
        let baseFilename = sanitizedFilename(for: name)
        if !usedFilenames.contains(baseFilename) {
            return baseFilename
        }

        // Find unique suffix
        var counter = 2
        let baseName = baseFilename.replacingOccurrences(of: ".orbit.json", with: "")
        while usedFilenames.contains("\(baseName)-\(counter).orbit.json") {
            counter += 1
        }
        return "\(baseName)-\(counter).orbit.json"
    }

    /// Generate a safe filename from environment name
    static func sanitizedFilename(for name: String) -> String {
        let invalidChars = CharacterSet.alphanumerics.inverted
        var sanitized = name.components(separatedBy: invalidChars).joined(separator: "-")

        // Remove leading/trailing hyphens and collapse multiple hyphens
        while sanitized.contains("--") {
            sanitized = sanitized.replacingOccurrences(of: "--", with: "-")
        }
        sanitized = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        // Fallback if empty or only hyphens
        if sanitized.isEmpty {
            sanitized = "environment"
        }

        return "\(sanitized).orbit.json"
    }
}

/// Reference to an environment file within the ZIP
struct BulkExportEnvironmentRef: Codable {
    let filename: String
    let name: String
}

// MARK: - Bulk Import Models

/// Preview for bulk import - contains all environments to be imported
struct BulkImportPreview: Identifiable {
    let id = UUID()
    let manifestVersion: String
    let appVersion: String
    let exportedAt: Date
    let environmentPreviews: [BulkEnvironmentPreview]
}

/// Individual environment preview within bulk import
struct BulkEnvironmentPreview: Identifiable {
    let id = UUID()
    let originalFilename: String
    let preview: ImportPreview

    /// Whether this environment should be included in the import
    var isSelected: Bool = true

    /// User-edited name for this environment
    var editedName: String

    /// Whether to use suggested IPs for this environment
    var useSuggestedIPs: Bool = true

    /// Whether this environment has conflicts with OTHER environments being imported
    var hasInterImportConflict: Bool = false

    init(filename: String, preview: ImportPreview) {
        self.originalFilename = filename
        self.preview = preview
        self.editedName = preview.suggestedName
    }
}

/// Errors specific to bulk import operations
enum BulkImportError: LocalizedError {
    case invalidArchive
    case missingManifest
    case invalidManifest(Error)
    case unsupportedVersion(String)
    case missingEnvironmentFile(String)
    case invalidEnvironmentFile(String, Error)
    case noEnvironments

    var errorDescription: String? {
        switch self {
        case .invalidArchive:
            return "The file is not a valid ZIP archive."
        case .missingManifest:
            return "The archive is missing the manifest.json file."
        case .invalidManifest(let error):
            return "Failed to parse manifest: \(error.localizedDescription)"
        case .unsupportedVersion(let version):
            return "Unsupported archive version: \(version). This archive may have been created with a newer version of Orbit."
        case .missingEnvironmentFile(let filename):
            return "Missing environment file in archive: \(filename)"
        case .invalidEnvironmentFile(let filename, let error):
            return "Failed to parse \(filename): \(error.localizedDescription)"
        case .noEnvironments:
            return "The archive contains no environments."
        }
    }
}
