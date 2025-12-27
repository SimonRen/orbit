import SwiftUI

/// Menu items for orb-kubectl install/update (similar to CheckForUpdatesView)
struct OrbKubectlMenuView: View {
    @ObservedObject var toolManager: ToolManager

    var body: some View {
        Group {
            switch toolManager.orbKubectlStatus {
            case .checking:
                Text("Checking orb-kubectl...")
                    .disabled(true)

            case .notInstalled:
                Button("Install orb-kubectl...") {
                    Task {
                        await toolManager.installOrUpdate()
                    }
                }
                .disabled(toolManager.isDownloading)

            case .installed(let version):
                Text("orb-kubectl v\(version) Installed")
                    .disabled(true)

            case .updateAvailable(_, let available):
                Button("Update orb-kubectl to v\(available)...") {
                    Task {
                        await toolManager.installOrUpdate()
                    }
                }
                .disabled(toolManager.isDownloading)
            }
        }
    }
}
