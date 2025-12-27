import Foundation
import Sparkle

/// Manages Sparkle updater lifecycle and state
@MainActor
final class UpdaterManager: ObservableObject {
    static let shared = UpdaterManager()

    let updaterController: SPUStandardUpdaterController

    @Published var canCheckForUpdates = false

    private var observation: NSKeyValueObservation?

    private init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        observation = updaterController.updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] updater, _ in
            Task { @MainActor in
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    var lastUpdateCheckDate: Date? {
        updaterController.updater.lastUpdateCheckDate
    }
}
