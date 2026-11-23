import AppKit
import Foundation
import MacKitUpdater

/// Public-update channel: Sparkle checks the signed feed on GitHub Releases.
/// Never claims "up to date" on its own; MacKitUpdater supplies gentle reminders and Sparkle owns update UI.
@MainActor
final class AppUpdater: NSObject {
    private let checker: SparkleUpdateChecker

    init(
        availability: UpdateAvailabilityState,
        onAvailableVersionChange: (@MainActor (String?) -> Void)? = nil
    ) {
        checker = SparkleUpdateChecker(
            gentleReminderMode: .menuBarOnly,
            availability: availability
        )
        super.init()
        checker.onAvailableVersionChange = onAvailableVersionChange
    }

    var sessionInProgress: Bool {
        checker.isSessionInProgress
    }

    @objc
    func checkForUpdates(_ sender: Any?) {
        checker.checkForUpdates(sender)
    }
}
