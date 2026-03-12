import Foundation
import os.log

private let logger = Logger(subsystem: "com.orbit.app", category: "ConfigManager")

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

    /// Base directory for config storage (injectable for testing)
    private let baseDirectory: URL

    /// Application support directory path
    private var appSupportDirectory: URL {
        baseDirectory
    }

    /// Configuration file path
    private var configFileURL: URL {
        appSupportDirectory.appendingPathComponent("config.json")
    }

    private init() {
        let paths = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        self.baseDirectory = paths[0].appendingPathComponent("Orbit", isDirectory: true)
    }

    /// Creates a ConfigManager with a custom directory (for testing)
    init(directory: URL) {
        self.baseDirectory = directory
    }

    // MARK: - Public Methods

    /// Load configuration from disk (falls back to backup if main config is corrupted)
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
            // Config is corrupted — try loading from backup
            logger.error("Config corrupted: \(String(describing: error))")
            let backupURL = appSupportDirectory.appendingPathComponent("config.backup.json")
            if fileManager.fileExists(atPath: backupURL.path),
               let backupData = try? Data(contentsOf: backupURL),
               let backupConfig = try? JSONDecoder().decode(AppConfig.self, from: backupData) {
                logger.info("Restored config from backup")
                try? backupData.write(to: configFileURL, options: .atomic)
                return backupConfig
            }
            throw ConfigError.corruptedFile
        } catch {
            // I/O error — don't silently fall back to backup, surface the real error
            throw ConfigError.loadFailed(error)
        }
    }

    /// Save environments to disk (creates a backup of the previous config)
    /// - Parameter environments: Array of environments to persist
    func save(environments: [DevEnvironment]) throws {
        // Ensure directory exists
        try createDirectoryIfNeeded()

        // Backup existing config before overwriting
        if fileManager.fileExists(atPath: configFileURL.path) {
            let backupURL = appSupportDirectory.appendingPathComponent("config.backup.json")
            do {
                try? fileManager.removeItem(at: backupURL)
                try fileManager.copyItem(at: configFileURL, to: backupURL)
            } catch {
                logger.warning("Failed to create config backup: \(error.localizedDescription)")
            }
        }

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
