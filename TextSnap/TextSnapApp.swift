import Darwin
import MacKitLifecycle
import SwiftUI

@main
enum TextSnapEntry {
    static func main() {
        if let index = CommandLine.arguments.firstIndex(of: "--ocr-once"),
           index + 1 < CommandLine.arguments.count {
            Darwin.exit(TextRecognizer.runCLIWorker(imagePath: CommandLine.arguments[index + 1]))
        }
        TextSnapApp.main()
    }
}

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
            CommandGroup(replacing: .appTermination) {
                Button(String(localized: "menu.quit")) {
                    AppDelegate.shared?.requestTermination()
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
}
