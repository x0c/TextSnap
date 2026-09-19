import MacKitLifecycle
import SwiftUI

@main
struct TextSnapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        AutofillHeuristicGuard.install()
    }

    var body: some Scene {
        // No WindowGroup / MenuBarExtra here: first launch and login launch stay
        // silent. The real entry is the AppKit status item owned by AppDelegate;
        // settings live in a single AppKit window shown on demand.
        Settings {
            EmptyView()
        }
        .commands {
            // Route the standard ⌘, to our AppKit settings window instead of the
            // empty Settings scene above (baseline A5 system entry point).
            CommandGroup(replacing: .appSettings) {
                Button(String(localized: "menu.settings")) {
                    AppDelegate.shared?.showMainWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
