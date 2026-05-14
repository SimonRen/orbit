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

    /// Uninstall the privileged helper.
    ///
    /// The helper is installed via the legacy SMJobBless API. The matching
    /// uninstall is SMJobRemove. (SMAppService.daemon(plistName:).unregister()
    /// is the newer API but it returns "Invalid argument" for daemons that
    /// were originally registered via SMJobBless, so we use SMJobRemove
    /// regardless of macOS version. It's deprecated but still functional and
    /// is the only API that reliably reverses an SMJobBless install.)
    ///
    /// SMJobRemove alone leaves the helper's launchd plist and binary on
    /// disk forever. To make uninstall a real uninstall we first ask the
    /// helper (v1.3.0+) to delete its own files via the selfDestruct RPC.
    /// Older helpers don't implement selfDestruct; that call will fail
    /// silently and we proceed with SMJobRemove anyway.
    func uninstallHelper() async throws {
        // Best-effort: ask the helper to self-destruct first. Ignore failures
        // (old helper, already gone, etc.) and proceed to SMJobRemove.
        try? await selfDestructHelper()

        var authRef: AuthorizationRef?
        let authStatus = AuthorizationCreate(nil, nil, [], &authRef)

        guard authStatus == errAuthorizationSuccess, let auth = authRef else {
            throw HelperClientError.installationFailed("Failed to create authorization")
        }

        defer { AuthorizationFree(auth, []) }

        var authItem = AuthorizationItem(
            name: kSMRightModifySystemDaemons,
            valueLength: 0,
            value: nil,
            flags: 0
        )
        var authRights = AuthorizationRights(count: 1, items: &authItem)
        let flags: AuthorizationFlags = [.interactionAllowed, .preAuthorize, .extendRights]
        let rightStatus = AuthorizationCopyRights(auth, &authRights, nil, flags, nil)

        guard rightStatus == errAuthorizationSuccess else {
            if rightStatus == errAuthorizationCanceled {
                throw HelperClientError.installationFailed("Authorization cancelled")
            }
            throw HelperClientError.installationFailed("Authorization failed: \(rightStatus)")
        }

        var error: Unmanaged<CFError>?
        let success = SMJobRemove(
            kSMDomainSystemLaunchd,
            "com.orbit.helper" as CFString,
            auth,
            true,
            &error
        )

        if success {
            isHelperInstalled = false
            needsUpgrade = false
            installedVersion = nil
            // Invalidate any cached XPC connection so a stale handle isn't reused.
            connection?.invalidate()
            connection = nil
        } else {
            let errorDesc = error?.takeRetainedValue().localizedDescription ?? "Unknown error"
            throw HelperClientError.installationFailed(errorDesc)
        }
    }

    /// Ask the helper (v1.3.0+) to delete its own binary and launchd plist.
    /// Always best-effort: old helpers don't implement this and will fail with
    /// a connection error; we silently fall through to SMJobRemove.
    private func selfDestructHelper() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumed = OnceFlag()
            getHelperProxy { proxy in
                guard let proxy = proxy else {
                    if resumed.trySet() {
                        continuation.resume(throwing: HelperClientError.connectionFailed)
                    }
                    return
                }
                proxy.selfDestruct { success, errorMessage in
                    guard resumed.trySet() else { return }
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: HelperClientError.operationFailed(
                            errorMessage ?? "selfDestruct unsupported (probably an older helper)"
                        ))
                    }
                }
            } errorHandler: {
                if resumed.trySet() {
                    continuation.resume(throwing: HelperClientError.connectionFailed)
                }
            }
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

    // MARK: - Orphan Monitoring

    /// Register this app for orphan process monitoring
    func registerApp(pid: Int32) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumed = OnceFlag()

            getHelperProxy { proxy in
                guard let proxy = proxy else {
                    if resumed.trySet() {
                        continuation.resume(throwing: HelperClientError.connectionFailed)
                    }
                    return
                }

                proxy.registerApp(pid: pid) { success, errorMessage in
                    guard resumed.trySet() else { return }
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: HelperClientError.operationFailed(
                            errorMessage ?? "Failed to register app"
                        ))
                    }
                }
            } errorHandler: {
                if resumed.trySet() {
                    continuation.resume(throwing: HelperClientError.connectionFailed)
                }
            }
        }
    }

    /// Update the list of process groups to clean up if the app dies
    func updateProcessGroups(_ pgids: [Int32]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumed = OnceFlag()

            getHelperProxy { proxy in
                guard let proxy = proxy else {
                    if resumed.trySet() {
                        continuation.resume(throwing: HelperClientError.connectionFailed)
                    }
                    return
                }

                proxy.updateProcessGroups(pgids) { success, errorMessage in
                    guard resumed.trySet() else { return }
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: HelperClientError.operationFailed(
                            errorMessage ?? "Failed to update process groups"
                        ))
                    }
                }
            } errorHandler: {
                if resumed.trySet() {
                    continuation.resume(throwing: HelperClientError.connectionFailed)
                }
            }
        }
    }

    /// Unregister from orphan monitoring (graceful shutdown)
    func unregisterApp() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumed = OnceFlag()

            getHelperProxy { proxy in
                guard let proxy = proxy else {
                    if resumed.trySet() {
                        continuation.resume(throwing: HelperClientError.connectionFailed)
                    }
                    return
                }

                proxy.unregisterApp { success, errorMessage in
                    guard resumed.trySet() else { return }
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: HelperClientError.operationFailed(
                            errorMessage ?? "Failed to unregister app"
                        ))
                    }
                }
            } errorHandler: {
                if resumed.trySet() {
                    continuation.resume(throwing: HelperClientError.connectionFailed)
                }
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
        // Clear handlers first to prevent them from being called during intentional invalidation
        if let oldConnection = self.connection {
            oldConnection.invalidationHandler = nil
            oldConnection.interruptionHandler = nil
            oldConnection.invalidate()
        }
        self.connection = connection
    }
}
