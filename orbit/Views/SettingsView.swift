import SwiftUI
import ServiceManagement
import os.log

private let logger = Logger(subsystem: "com.orbit.app", category: "SettingsView")

/// macOS Settings scene for Orbit. Opened via ⌘, or the Orbit menu.
///
/// Two sections:
/// - General: launch-at-login
/// - Network: automatic loopback management + helper install/uninstall
struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false
    @AppStorage("autoManageInterfaces") private var autoManageInterfaces: Bool = true

    @ObservedObject private var toolManager = ToolManager.shared

    @State private var loginItemError: String?
    @State private var helperBusy = false
    @State private var helperError: String?
    @State private var showRequiresApprovalAlert = false
    @State private var showingOrbKubectlInstall = false
    @State private var showingOrbKubectlUninstall = false
    @State private var orbKubectlError: String?

    var body: some View {
        Form {
            Section("General") {
                Toggle(isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        applyLaunchAtLogin(newValue)
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch Orbit at startup")
                        if let err = loginItemError {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

            Section("Network") {
                Toggle(isOn: $autoManageInterfaces) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatically configure loopback interfaces")
                        Text("When on, Orbit uses a privileged helper to add 127.x.x.x aliases on activation. When off, Orbit only spawns services for IPs you've aliased yourself (e.g., via sudo ifconfig).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(helperStatusLabel)
                            .font(.callout)
                        if let err = helperError {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer()
                    if helperBusy {
                        ProgressView().controlSize(.small)
                    } else if appState.isHelperInstalled {
                        Button("Uninstall helper…") {
                            Task { await runUninstallHelper() }
                        }
                    } else {
                        Button("Install helper…") {
                            Task { await runInstallHelper() }
                        }
                    }
                }
            }

            Section("Tools") {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(orbKubectlStatusLabel)
                            .font(.callout)
                        Text("kubectl with --retry for port-forwarding. Optional — Orbit's K8s import works with plain kubectl too.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let err = orbKubectlError {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer()
                    orbKubectlActionButton
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 460)
        .onAppear {
            // Sync the toggle with the actual system state in case the user changed
            // it in System Settings since the last app launch.
            let actual = LoginItemService.shared.isEnabled
            if actual != launchAtLogin {
                launchAtLogin = actual
            }
        }
        .alert("Login items need approval", isPresented: $showRequiresApprovalAlert) {
            Button("Open System Settings…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Open System Settings → General → Login Items and allow Orbit to run at login.")
        }
        .alert(isOrbKubectlInstallMode ? "Install orb-kubectl?" : "Update orb-kubectl?",
               isPresented: $showingOrbKubectlInstall) {
            Button(isOrbKubectlInstallMode ? "Download & Install" : "Download & Update") {
                orbKubectlError = nil
                Task { await toolManager.installOrUpdate() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(ToolManager.orbKubectlTrustDisclosure)
        }
        .alert("Uninstall orb-kubectl?", isPresented: $showingOrbKubectlUninstall) {
            Button("Uninstall", role: .destructive) {
                do {
                    try toolManager.uninstall()
                    orbKubectlError = nil
                } catch {
                    orbKubectlError = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes the binary from ~/Library/Application Support/Orbit/bin/. Plain kubectl from your $PATH will still work in the Kubernetes import sheet. You can reinstall any time.")
        }
    }

    // MARK: - orb-kubectl helpers

    private var orbKubectlStatusLabel: String {
        switch toolManager.orbKubectlStatus {
        case .checking:                       return "orb-kubectl — checking…"
        case .notInstalled:                   return "orb-kubectl — not installed"
        case .installed(let v):               return "orb-kubectl installed (v\(v))"
        case .updateAvailable(let i, let a):  return "orb-kubectl v\(i) installed (v\(a) available)"
        }
    }

    private var isOrbKubectlInstallMode: Bool {
        if case .notInstalled = toolManager.orbKubectlStatus { return true }
        return false
    }

    @ViewBuilder
    private var orbKubectlActionButton: some View {
        if toolManager.isDownloading {
            ProgressView(value: toolManager.downloadProgress).controlSize(.small).frame(width: 80)
        } else {
            switch toolManager.orbKubectlStatus {
            case .checking:
                ProgressView().controlSize(.small)
            case .notInstalled:
                Button("Install…") { showingOrbKubectlInstall = true }
            case .installed:
                Button("Uninstall…") { showingOrbKubectlUninstall = true }
            case .updateAvailable:
                HStack(spacing: 6) {
                    Button("Update…") { showingOrbKubectlInstall = true }
                    Button("Uninstall…") { showingOrbKubectlUninstall = true }
                }
            }
        }
    }

    // MARK: - Helpers

    private var helperStatusLabel: String {
        if appState.isHelperInstalled {
            if let v = appState.networkManagerInstalledVersion {
                return "Helper installed (v\(v))"
            }
            return "Helper installed"
        }
        return "Helper not installed"
    }

    private func applyLaunchAtLogin(_ newValue: Bool) {
        loginItemError = nil
        do {
            if newValue {
                try LoginItemService.shared.enable()
            } else {
                try LoginItemService.shared.disable()
            }
            launchAtLogin = newValue
        } catch {
            logger.error("Failed to update login item: \(error.localizedDescription, privacy: .public)")
            if LoginItemService.shared.requiresApproval {
                showRequiresApprovalAlert = true
            } else {
                loginItemError = error.localizedDescription
            }
            // Revert toggle to actual system state on next runloop tick.
            DispatchQueue.main.async {
                launchAtLogin = LoginItemService.shared.isEnabled
            }
        }
    }

    private func runInstallHelper() async {
        helperBusy = true
        helperError = nil
        await appState.installHelper()
        helperBusy = false
        if case let .privilegeError(message) = appState.lastError ?? .privilegeError("") {
            if !message.isEmpty {
                helperError = message
            }
        }
    }

    private func runUninstallHelper() async {
        helperBusy = true
        helperError = nil
        await appState.uninstallHelper()
        helperBusy = false
        if case let .privilegeError(message) = appState.lastError ?? .privilegeError("") {
            if !message.isEmpty {
                helperError = message
            }
        }
    }
}
