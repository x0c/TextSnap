import AppKit
import MacKitLifecycle
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    var present: (() -> Void)?
    private weak var window: NSWindow?
    private let activationSession = AccessoryActivationSession()
    private var observers: [NSObjectProtocol] = []

    func show() {
        present?()
        NSApp.activate()
    }

    func close() {
        window?.performClose(nil)
    }

    func attach(_ window: NSWindow) {
        guard self.window !== window else { return }
        observers.forEach(NotificationCenter.default.removeObserver)
        self.window = window
        window.title = String(localized: "settings.title")
        window.setFrameAutosaveName("TextSnap.MainWindow")
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated { Self.shared.activationSession.beginIfAccessory() }
            },
            center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated {
                    HotkeyManager.shared.stopRecording()
                    Self.shared.activationSession.endIfNeeded()
                }
            }
        ]
        if window.isKeyWindow { activationSession.beginIfAccessory() }
    }
}

struct SettingsWindowObserver: NSViewRepresentable {
    func makeNSView(context: Context) -> ObserverView { ObserverView() }
    func updateNSView(_ nsView: ObserverView, context: Context) {}

    final class ObserverView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { SettingsWindowController.shared.attach(window) }
        }
    }
}

struct SettingsPresenterCommands: Commands {
    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        CommandGroup(after: .appSettings) {
            Color.clear.frame(width: 0, height: 0)
                .onAppear { SettingsWindowController.shared.present = { openSettings() } }
        }
    }
}
