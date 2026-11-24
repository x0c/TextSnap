import AppKit
import MacKitLifecycle
import QuartzCore
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    var present: (() -> Void)?
    private weak var window: NSWindow?
    private var e2eWindow: NSWindow?
    private let activationSession = AccessoryActivationSession()
    private var observers: [NSObjectProtocol] = []

    func show() {
        if E2ERuntime.isEnabled {
            showForE2E()
            return
        }
        present?()
        NSApp.activate()
    }

    func showForE2E() {
        NSApp.appearance = NSAppearance(named: .aqua)
        if let existing = e2eWindow {
            existing.orderBack(nil)
            flushRedrawIfNeeded()
            return
        }
        let hosting = NSHostingView(rootView: SettingsView())
        let fitting = hosting.fittingSize
        let size = E2ERuntime.windowSize ?? NSSize(
            width: max(480, fitting.width),
            height: max(400, fitting.height)
        )
        let origin = centeredOrigin(for: size)
        let panel = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = String(localized: "settings.title")
        panel.contentView = hosting
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.appearance = NSAppearance(named: .aqua)
        panel.setFrameOrigin(origin)
        e2eWindow = panel
        window = panel
        observeWindow(panel, manageActivation: false)
        panel.orderBack(nil)
        flushRedrawIfNeeded()
    }

    func flushRedrawIfNeeded() {
        guard E2ERuntime.isEnabled, let target = e2eWindow ?? window else { return }
        target.contentView?.layoutSubtreeIfNeeded()
        target.displayIfNeeded()
        CATransaction.flush()
    }

    func close() {
        window?.performClose(nil)
    }

    func attach(_ window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        window.title = String(localized: "settings.title")
        window.setFrameAutosaveName("TextSnap.MainWindow")
        observeWindow(window, manageActivation: true)
        if window.isKeyWindow { activationSession.beginIfAccessory() }
        DispatchQueue.main.async { self.clampToVisibleIfNeeded() }
    }

    private func observeWindow(_ window: NSWindow, manageActivation: Bool) {
        observers.forEach(NotificationCenter.default.removeObserver)
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated {
                    if manageActivation {
                        Self.shared.activationSession.beginIfAccessory()
                    }
                    Self.shared.clampToVisibleIfNeeded()
                }
            },
            center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated {
                    HotkeyManager.shared.stopRecording()
                }
            },
            center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated { Self.shared.clampToVisibleIfNeeded() }
            },
            center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
                MainActor.assumeIsolated {
                    HotkeyManager.shared.stopRecording()
                    if manageActivation {
                        Self.shared.activationSession.endIfNeeded()
                    }
                }
            },
        ]
    }

    private func centeredOrigin(for size: NSSize) -> NSPoint {
        guard let visible = NSScreen.main?.visibleFrame else {
            return NSPoint(x: 200, y: 200)
        }
        return NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
    }

    private func clampToVisibleIfNeeded() {
        guard let window, let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        var frame = window.frame
        frame.origin.x = min(max(frame.minX, visible.minX), max(visible.minX, visible.maxX - frame.width))
        frame.origin.y = min(max(frame.minY, visible.minY), max(visible.minY, visible.maxY - frame.height))
        if frame.origin != window.frame.origin { window.setFrame(frame, display: true) }
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
