import AppKit
import Foundation
import Sparkle

/// Public-update channel: Sparkle checks the signed feed on GitHub Releases.
/// Never claims "up to date" on its own; Sparkle owns all update UI.
@MainActor
final class AppUpdater: NSObject {
    private let updaterController: SPUStandardUpdaterController

    override init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    var sessionInProgress: Bool {
        updaterController.updater.sessionInProgress
    }

    @objc
    func checkForUpdates(_ sender: Any?) {
        updaterController.checkForUpdates(sender)
    }
}
