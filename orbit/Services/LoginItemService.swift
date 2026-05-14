import Foundation
import ServiceManagement
import os.log

private let logger = Logger(subsystem: "com.orbit.app", category: "LoginItemService")

/// Manages whether Orbit launches automatically at login via SMAppService.mainApp.
///
/// This is independent of the privileged helper — it's just the GUI app
/// registering itself as a login item, no admin password required.
@MainActor
final class LoginItemService {
    static let shared = LoginItemService()

    private init() {}

    /// Current registration status for the main app login item.
    var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    /// Whether Orbit is currently registered to launch at login.
    var isEnabled: Bool {
        status == .enabled
    }

    /// Whether the user has denied login-item permission in System Settings;
    /// the toggle in this state needs to send the user to System Settings.
    var requiresApproval: Bool {
        status == .requiresApproval
    }

    /// Register Orbit as a login item. Throws if registration fails (e.g., app
    /// running from a non-`/Applications` path, or user has revoked permission).
    func enable() throws {
        try SMAppService.mainApp.register()
        logger.info("Login item registered (status: \(String(describing: SMAppService.mainApp.status), privacy: .public))")
    }

    /// Unregister Orbit from launch-at-login.
    func disable() throws {
        try SMAppService.mainApp.unregister()
        logger.info("Login item unregistered (status: \(String(describing: SMAppService.mainApp.status), privacy: .public))")
    }
}
