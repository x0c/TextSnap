import MacKitLifecycle
import SwiftUI

@main
struct TextSnapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        AutofillHeuristicGuard.install()
    }

    var body: some Scene {
        // Settings remains demand-only; the AppKit status item owns launch.
        Settings {
            SettingsView()
        }
        .commands {
            SettingsPresenterCommands()
        }
    }
}
