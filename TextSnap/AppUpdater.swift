import AppKit
import Foundation
import MacKitCore

/// Self-use build: honestly reports no public feed. Never claims up to date.
@MainActor
final class AppUpdater: NSObject {
    private let checker = PersonalBuildUpdateChecker()

    @objc
    func checkForUpdates(_ sender: Any?) {
        _ = checker.check()
        let alert = NSAlert()
        alert.messageText = String(localized: "updates.unavailable.title")
        alert.informativeText = String(localized: "updates.unavailable.body")
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "updates.unavailable.ok"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
