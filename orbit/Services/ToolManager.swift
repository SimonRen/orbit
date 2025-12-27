import Foundation

/// Definition of a downloadable tool - update these when releasing new Orbit with new tool versions
struct ToolDefinition {
    let name: String
    let version: String
    let downloadURL: URL
    let sha256: String
    let description: String
}

/// Tool installation status
enum ToolStatus: Equatable {
    case notInstalled
    case installed(version: String)
    case updateAvailable(installed: String, available: String)
    case checking
}

/// Manages downloadable tools like orb-kubectl
@MainActor
final class ToolManager: ObservableObject {
    static let shared = ToolManager()

    // MARK: - Tool Definitions (update these when releasing new tool versions)

    /// Expected orb-kubectl version - update this when bundling new kubectl with Orbit
    static let orbKubectlDefinition = ToolDefinition(
        name: "orb-kubectl",
        version: "1.0.0",
        downloadURL: URL(string: "https://github.com/simonren/orbit/releases/download/orb-kubectl-v1.0.0/orb-kubectl-darwin-universal.zip")!,
        sha256: "e4fde23102e7f5db043a9d60fd468dcb4c95d9375edb62968cc5e9463dd763f0",
        description: "kubectl with retry support for port-forwarding"
    )

    // MARK: - Published State

    @Published var orbKubectlStatus: ToolStatus = .checking
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var downloadError: String?
    @Published var isToolInUse = false

    // MARK: - Private Properties

    private let binPath: URL
    private let orbKubectlURL: URL
    private let versionFileURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        binPath = appSupport.appendingPathComponent("Orbit/bin", isDirectory: true)
        orbKubectlURL = binPath.appendingPathComponent("orb-kubectl")
        versionFileURL = binPath.appendingPathComponent("orb-kubectl.version")

        // Defer check to avoid blocking app startup
        DispatchQueue.main.async { [weak self] in
            self?.checkInstallation()
        }
    }

    // MARK: - Public Methods

    /// Check installation status and compare versions
    func checkInstallation() {
        orbKubectlStatus = .checking
        isToolInUse = checkIfToolIsRunning()

        guard FileManager.default.fileExists(atPath: orbKubectlURL.path) else {
            orbKubectlStatus = .notInstalled
            return
        }

        let installedVersion = getInstalledVersion()
        let expectedVersion = Self.orbKubectlDefinition.version

        if let installed = installedVersion {
            if installed == expectedVersion {
                orbKubectlStatus = .installed(version: installed)
            } else {
                orbKubectlStatus = .updateAvailable(installed: installed, available: expectedVersion)
            }
        } else {
            // Binary exists but no version file - treat as needing update
            orbKubectlStatus = .updateAvailable(installed: "unknown", available: expectedVersion)
        }
    }

    /// Install or update orb-kubectl
    func installOrUpdate() async {
        isDownloading = true
        downloadProgress = 0
        downloadError = nil

        let backupURL = orbKubectlURL.appendingPathExtension("backup")

        do {
            // Create bin directory
            try FileManager.default.createDirectory(at: binPath, withIntermediateDirectories: true)

            // Download zip file
            let (zipURL, _) = try await downloadWithProgress(from: Self.orbKubectlDefinition.downloadURL)
            downloadProgress = 0.5

            // Unzip to temp location
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let unzipProcess = Process()
            unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzipProcess.arguments = ["-o", zipURL.path, "-d", tempDir.path]
            unzipProcess.standardOutput = FileHandle.nullDevice
            unzipProcess.standardError = FileHandle.nullDevice
            try unzipProcess.run()
            unzipProcess.waitUntilExit()

            guard unzipProcess.terminationStatus == 0 else {
                throw NSError(domain: "ToolManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to extract archive"])
            }

            downloadProgress = 0.7

            let extractedBinary = tempDir.appendingPathComponent("orb-kubectl")

            // Remove macOS quarantine attribute
            let xattrProcess = Process()
            xattrProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattrProcess.arguments = ["-d", "com.apple.quarantine", extractedBinary.path]
            xattrProcess.standardOutput = FileHandle.nullDevice
            xattrProcess.standardError = FileHandle.nullDevice
            try? xattrProcess.run()
            xattrProcess.waitUntilExit()

            downloadProgress = 0.8

            // Atomic update with rollback support
            if FileManager.default.fileExists(atPath: orbKubectlURL.path) {
                try? FileManager.default.removeItem(at: backupURL)
                try FileManager.default.moveItem(at: orbKubectlURL, to: backupURL)
            }

            do {
                try FileManager.default.moveItem(at: extractedBinary, to: orbKubectlURL)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: orbKubectlURL.path)

                // Write version file
                let version = Self.orbKubectlDefinition.version
                try version.write(to: versionFileURL, atomically: true, encoding: .utf8)

                // Success - remove backup
                try? FileManager.default.removeItem(at: backupURL)

            } catch {
                // Rollback
                if FileManager.default.fileExists(atPath: backupURL.path) {
                    try? FileManager.default.moveItem(at: backupURL, to: orbKubectlURL)
                }
                throw error
            }

            // Cleanup temp files
            try? FileManager.default.removeItem(at: tempDir)
            try? FileManager.default.removeItem(at: zipURL)

            downloadProgress = 1.0
            checkInstallation()

        } catch {
            downloadError = error.localizedDescription
        }

        isDownloading = false
    }

    /// Uninstall orb-kubectl
    func uninstall() throws {
        if isToolInUse {
            throw NSError(domain: "ToolManager", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Cannot uninstall while orb-kubectl is in use. Stop all environments first."])
        }
        try FileManager.default.removeItem(at: orbKubectlURL)
        try? FileManager.default.removeItem(at: versionFileURL)
        orbKubectlStatus = .notInstalled
    }

    /// Get the bin path for PATH environment variable
    var binPathString: String {
        binPath.path
    }

    /// Whether an update is available
    var hasUpdatesAvailable: Bool {
        if case .updateAvailable = orbKubectlStatus {
            return true
        }
        return false
    }

    // MARK: - Private Methods

    private func checkIfToolIsRunning() -> Bool {
        // Use synchronous shell check to avoid blocking main thread
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "pgrep -f orb-kubectl > /dev/null 2>&1 && echo 1 || echo 0"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                return output == "1"
            }
            return false
        } catch {
            return false
        }
    }

    private func getInstalledVersion() -> String? {
        guard let versionString = try? String(contentsOf: versionFileURL, encoding: .utf8) else {
            return nil
        }
        return versionString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func downloadWithProgress(from url: URL) async throws -> (URL, URLResponse) {
        let (localURL, response) = try await URLSession.shared.download(from: url)
        downloadProgress = 0.5
        return (localURL, response)
    }
}
