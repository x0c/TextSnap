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

        clampToVisibleIfNeeded()

        activationSession.beginIfAccessory()
        window?.makeKeyAndOrderFront(nil)

        // Grow-only fit after the autosaved frame has been applied: a narrower
        // frame saved by an older layout must not clip the new content.
        // Never shrink, so a user-enlarged window stays as is.
        if let window, let hosting = window.contentViewController as? NSHostingController<SettingsView> {
            DispatchQueue.main.async {
                hosting.view.layoutSubtreeIfNeeded()
                let fitting = hosting.view.fittingSize
                let contentSize = window.contentRect(forFrameRect: window.frame).size
                let width = max(contentSize.width, min(fitting.width, 480))
                let height = max(contentSize.height, fitting.height)
                if width > contentSize.width + 0.5 || height > contentSize.height + 0.5 {
                    window.setContentSize(NSSize(width: width, height: height))
                    // Growing can push the bottom edge below the screen; clamp again.
                    self.clampToVisibleIfNeeded()
                }
            }
        }
    }

    /// Clamp the (possibly autosaved) frame into the visible screen: display
    /// changes must never strand the window off-screen. No orderFrontRegardless:
    /// returning from System Settings must not yank this window over it.
    private func clampToVisibleIfNeeded() {
        if let window, let visible = NSScreen.main?.visibleFrame {
            var frame = window.frame
            frame.origin.x = min(max(frame.origin.x, visible.minX), max(visible.minX, visible.maxX - frame.width))
            frame.origin.y = min(max(frame.origin.y, visible.minY), max(visible.minY, visible.maxY - frame.height))
            window.setFrame(frame, display: true)
        }
    }

    func windowWillClose(_ notification: Notification) {
        HotkeyManager.shared.stopRecording()
        activationSession.endIfNeeded()
    }
}
