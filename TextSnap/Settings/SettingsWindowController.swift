import AppKit
import MacKitLifecycle
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private let activationSession = AccessoryActivationSession()

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            hosting.sizingOptions = [.intrinsicContentSize]
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 480),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = String(localized: "settings.title")
            window.contentViewController = hosting
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            window.setFrameAutosaveName("TextSnap.MainWindow")
            self.window = window
        }

        // Clamp the (possibly autosaved) frame into the visible screen: display
        // changes must never strand the window off-screen. No orderFrontRegardless:
        // returning from System Settings must not yank this window over it.
        if let window, let visible = NSScreen.main?.visibleFrame {
            var frame = window.frame
            frame.origin.x = min(max(frame.origin.x, visible.minX), max(visible.minX, visible.maxX - frame.width))
            frame.origin.y = min(max(frame.origin.y, visible.minY), max(visible.minY, visible.maxY - frame.height))
            window.setFrame(frame, display: false)
        }

        activationSession.beginIfAccessory()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        HotkeyManager.shared.stopRecording()
        activationSession.endIfNeeded()
    }
}
