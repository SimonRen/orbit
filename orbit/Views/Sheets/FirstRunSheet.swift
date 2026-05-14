import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.orbit.app", category: "FirstRunSheet")

/// One-shot welcome sheet shown on first launch (when there's no helper installed
/// and no existing environments). Lets the user opt into launch-at-login and
/// automatic loopback management before they ever toggle an environment.
struct FirstRunSheet: View {
    @EnvironmentObject var appState: AppState

    @State private var enableLaunchAtLogin: Bool = true
    @State private var enableAutoManageInterfaces: Bool = true

    @State private var loginItemError: String?
    @State private var helperError: String?
    @State private var isApplying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to Orbit")
                    .font(.title2.weight(.semibold))
                Text("Two quick choices you can change anytime in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                Toggle(isOn: $enableLaunchAtLogin) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch Orbit at startup")
                        Text("Open Orbit automatically when you log in.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                if let err = loginItemError {
                    Text(err)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding(.leading, 24)
                }

                Toggle(isOn: $enableAutoManageInterfaces) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatically configure loopback interfaces")
                        Text("Installs a small privileged helper. Without it, you'll need to run sudo ifconfig manually before activating environments. Recommended.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let err = helperError {
                    Text(err)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding(.leading, 24)
                }
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Skip for now") {
                    appState.markFirstRunSetupComplete()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isApplying)

                Button("Continue") {
                    Task { await applyAndDismiss() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isApplying)
            }
        }
        .padding(28)
        .frame(width: 460)
    }

    private func applyAndDismiss() async {
        isApplying = true
        loginItemError = nil
        helperError = nil

        // 1. Persist the autoManageInterfaces preference (default to true if user
        //    leaves it on; explicitly false if they toggled off).
        UserDefaults.standard.set(enableAutoManageInterfaces, forKey: "autoManageInterfaces")

        // 2. Apply login-at-login state.
        UserDefaults.standard.set(enableLaunchAtLogin, forKey: "launchAtLogin")
        if enableLaunchAtLogin {
            do {
                try LoginItemService.shared.enable()
            } catch {
                logger.error("First-run: failed to enable login item: \(error.localizedDescription, privacy: .public)")
                loginItemError = "Couldn't enable launch at startup: \(error.localizedDescription)"
                UserDefaults.standard.set(false, forKey: "launchAtLogin")
            }
        }

        // 3. Install helper if the user opted in. This triggers the admin prompt.
        if enableAutoManageInterfaces {
            await appState.installHelper()
            if case .privilegeError(let msg) = appState.lastError ?? .privilegeError("") {
                if !msg.isEmpty {
                    helperError = "Couldn't install helper: \(msg)"
                }
            }
        }

        isApplying = false

        // If both succeeded (or the user opted out of both), dismiss.
        // If either errored, leave the sheet visible so the user can adjust and retry.
        if loginItemError == nil && helperError == nil {
            appState.markFirstRunSetupComplete()
        }
    }
}
