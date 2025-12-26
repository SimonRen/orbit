import Foundation

/// Configuration file structure
struct AppConfig: Codable {
    var version: String = "1.0"
    var environments: [DevEnvironment]

    init(environments: [DevEnvironment] = []) {
        self.environments = environments
    }
}

/// Error types for configuration operations
enum ConfigError: LocalizedError {
    case directoryCreationFailed(Error)
    case saveFailed(Error)
    case loadFailed(Error)
    case corruptedFile

    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let error):
            return "Failed to create config directory: \(error.localizedDescription)"
        case .saveFailed(let error):
            return "Failed to save configuration: \(error.localizedDescription)"
        case .loadFailed(let error):
            return "Failed to load configuration: \(error.localizedDescription)"
        case .corruptedFile:
            return "Configuration file is corrupted"
        }
    }
}

/// Manages JSON persistence for app configuration
final class ConfigManager {
    static let shared = ConfigManager()

    private let fileManager = FileManager.default

    /// Application support directory path
    private var appSupportDirectory: URL {
        let paths = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("Orbit", isDirectory: true)
    }

    /// Configuration file path
    private var configFileURL: URL {
        appSupportDirectory.appendingPathComponent("config.json")
    }

    private init() {}

    // MARK: - Public Methods

    /// Load configuration from disk
    /// - Returns: AppConfig with environments, or empty config if file doesn't exist
    func load() throws -> AppConfig {
        // Return empty config if file doesn't exist
        guard fileManager.fileExists(atPath: configFileURL.path) else {
            return AppConfig()
        }

        do {
            let data = try Data(contentsOf: configFileURL)
            let decoder = JSONDecoder()
            let config = try decoder.decode(AppConfig.self, from: data)
            return config
        } catch let error as DecodingError {
            // Log the specific decoding error for debugging
            print("Config decoding error: \(error)")
            throw ConfigError.corruptedFile
        } catch {
            throw ConfigError.loadFailed(error)
        }
    }

    /// Save environments to disk
    /// - Parameter environments: Array of environments to persist
    func save(environments: [DevEnvironment]) throws {
        // Ensure directory exists
        try createDirectoryIfNeeded()

        let config = AppConfig(environments: environments)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(config)
            try data.write(to: configFileURL, options: .atomic)
        } catch {
            throw ConfigError.saveFailed(error)
        }
    }

    /// Delete configuration file (for testing or reset)
    func deleteConfig() throws {
        guard fileManager.fileExists(atPath: configFileURL.path) else { return }
        try fileManager.removeItem(at: configFileURL)
    }

    /// Get the config file path (for debugging)
    var configPath: String {
        configFileURL.path
    }

    // MARK: - Private Methods

    private func createDirectoryIfNeeded() throws {
        guard !fileManager.fileExists(atPath: appSupportDirectory.path) else { return }

        do {
            try fileManager.createDirectory(
                at: appSupportDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            throw ConfigError.directoryCreationFailed(error)
        }
    }
}
