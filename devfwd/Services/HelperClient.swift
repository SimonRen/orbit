import Foundation
import ServiceManagement
import os.lock

/// Thread-safe flag that can only be set once (for continuation safety)
private final class OnceFlag: @unchecked Sendable {
    private var _value = false
    private let lock = OSAllocatedUnfairLock()

    /// Try to set the flag. Returns true if this call set it, false if already set.
    func trySet() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if _value { return false }
        _value = true
        return true
    }
}

/// Error types for helper operations
enum HelperClientError: LocalizedError {
    case helperNotInstalled
    case connectionFailed
    case operationFailed(String)
    case installationFailed(String)

    var errorDescription: String? {
        switch self {
        case .helperNotInstalled:
            return "Privileged helper not installed. Please install it first."
        case .connectionFailed:
            return "Failed to connect to privileged helper."
        case .operationFailed(let reason):
            return "Operation failed: \(reason)"
        case .installationFailed(let reason):
            return "Helper installation failed: \(reason)"
        }
    }
}

/// Client for communicating with the privileged helper tool
@MainActor
final class HelperClient: ObservableObject {
    static let shared = HelperClient()

    @Published private(set) var isHelperInstalled = false
    @Published private(set) var needsUpgrade = false
    @Published private(set) var installedVersion: String?

    private var connection: NSXPCConnection?

    private init() {
        checkHelperStatus()
    }

    // MARK: - Installation

    /// Check if helper is installed, running, and up-to-date
    func checkHelperStatus() {
        getHelperProxy { [weak self] proxy in
            proxy?.getVersion { version in
                DispatchQueue.main.async {
                    self?.isHelperInstalled = true
                    self?.installedVersion = version
                    // Compare versions - upgrade needed if installed version differs from expected
                    self?.needsUpgrade = (version != HelperConstants.helperVersion)
                }
            }
        } errorHandler: { [weak self] in
            DispatchQueue.main.async {
                self?.isHelperInstalled = false
                self?.needsUpgrade = false
                self?.installedVersion = nil
            }
        }
    }

    /// Install the privileged helper tool (requires admin auth once)
    func installHelper() async throws {
        // Use SMJobBless - works for development without notarization
        try installHelperWithSMJobBless()
    }

    private func installHelperWithSMJobBless() throws {
        var authRef: AuthorizationRef?
        var authStatus = AuthorizationCreate(nil, nil, [], &authRef)

        guard authStatus == errAuthorizationSuccess, let auth = authRef else {
            throw HelperClientError.installationFailed("Failed to create authorization")
        }

        defer { AuthorizationFree(auth, []) }

        var authItem = AuthorizationItem(
            name: kSMRightBlessPrivilegedHelper,
            valueLength: 0,
            value: nil,
            flags: 0
        )

        var authRights = AuthorizationRights(count: 1, items: &authItem)

        let flags: AuthorizationFlags = [.interactionAllowed, .preAuthorize, .extendRights]
        authStatus = AuthorizationCopyRights(auth, &authRights, nil, flags, nil)

        guard authStatus == errAuthorizationSuccess else {
            if authStatus == errAuthorizationCanceled {
                throw HelperClientError.installationFailed("Authorization cancelled")
            }
            throw HelperClientError.installationFailed("Authorization failed: \(authStatus)")
        }

        var error: Unmanaged<CFError>?
        let success = SMJobBless(
            kSMDomainSystemLaunchd,
            "com.orbit.helper" as CFString,
            auth,
            &error
        )

        if success {
            isHelperInstalled = true
            needsUpgrade = false
            installedVersion = HelperConstants.helperVersion
        } else {
            let errorDesc = error?.takeRetainedValue().localizedDescription ?? "Unknown error"
            throw HelperClientError.installationFailed(errorDesc)
        }
    }

    /// Uninstall the privileged helper
    func uninstallHelper() async throws {
        if #available(macOS 13.0, *) {
            let service = SMAppService.daemon(plistName: "com.orbit.helper.plist")
            try await service.unregister()
            isHelperInstalled = false
        }
    }

    // MARK: - Interface Operations

    /// Add a loopback interface alias
    func addInterfaceAlias(_ ip: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Use a class to track if continuation was already resumed (XPC can fire multiple handlers)
            let resumed = OnceFlag()

            getHelperProxy { proxy in
                proxy?.addInterfaceAlias(ip) { success, errorMessage in
                    guard resumed.trySet() else { return }
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: HelperClientError.operationFailed(errorMessage ?? "Unknown error"))
                    }
                }
            } errorHandler: {
                guard resumed.trySet() else { return }
                continuation.resume(throwing: HelperClientError.connectionFailed)
            }
        }
    }

    /// Remove a loopback interface alias
    func removeInterfaceAlias(_ ip: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumed = OnceFlag()

            getHelperProxy { proxy in
                proxy?.removeInterfaceAlias(ip) { success, errorMessage in
                    guard resumed.trySet() else { return }
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: HelperClientError.operationFailed(errorMessage ?? "Unknown error"))
                    }
                }
            } errorHandler: {
                guard resumed.trySet() else { return }
                continuation.resume(throwing: HelperClientError.connectionFailed)
            }
        }
    }

    // MARK: - Private Methods

    private func getHelperProxy(
        completion: @escaping (HelperProtocol?) -> Void,
        errorHandler: @escaping () -> Void
    ) {
        let connection = NSXPCConnection(machServiceName: HelperConstants.machServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)

        connection.invalidationHandler = {
            errorHandler()
        }

        connection.interruptionHandler = {
            errorHandler()
        }

        connection.resume()

        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
            errorHandler()
        } as? HelperProtocol

        completion(proxy)

        // Invalidate old connection before storing new one
        self.connection?.invalidate()
        self.connection = connection
    }
}
