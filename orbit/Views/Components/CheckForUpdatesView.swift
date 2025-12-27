import SwiftUI

/// Menu bar button for triggering update checks
struct CheckForUpdatesView: View {
    @ObservedObject var updaterManager: UpdaterManager

    var body: some View {
        Button("Check for Updates...") {
            updaterManager.checkForUpdates()
        }
        .disabled(!updaterManager.canCheckForUpdates)
    }
}
