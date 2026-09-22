import AppKit
import MacKitCore
import MacKitLifecycle
import MacKitStatusItem
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) static weak var shared: AppDelegate?

    private var statusItemController: StatusItemController?
    private var becomeActiveObserver: NSObjectProtocol?
    private var readyAt = Date()
    private let appUpdater = AppUpdater()
    private let terminationGuard = TerminationGuard()
    let captureEngine = CaptureEngine.shared

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        terminationGuard.isUpdateSessionInProgress = { false }

        statusItemController = StatusItemController(
            commands: makeCommands(),
            onPrimaryAction: { [weak self] in
                Task { @MainActor in await self?.captureEngine.captureNow() }
            }
        )
        statusItemController?.setTemplateImage(
            StatusBarIcon.image(pointSize: 18),
            accessibilityLabel: String(localized: "status.item.accessibility")
        )
        statusItemController?.isIconVisible = true

        HotkeyManager.shared.onHotKey = { [weak self] in
            Task { @MainActor in await self?.captureEngine.captureNow() }
        }
        HotkeyManager.shared.register()
        #if DEBUG
        NSLog("[TextSnap] hotkey registered: %@", HotkeyManager.shared.shortcut?.displayName ?? "none")
        #endif

        becomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshCommands() }
        }

        // First launch and login launch stay silent. No window.
        readyAt = Date()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        terminationGuard.shouldTerminate() ? .terminateNow : .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if MenuBarReopenPolicy.presentation(
            iconVisible: true,
            isReopenOrLaunch: true,
            isLoginLaunch: false,
            menubarIsPrimaryEntry: true,
            secondsSinceReady: Date().timeIntervalSince(readyAt)
        ) == .showRecoveryWindow {
            showMainWindow()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregister()
        if let becomeActiveObserver {
            NotificationCenter.default.removeObserver(becomeActiveObserver)
        }
    }

    func requestTermination(terminate: () -> Void = { NSApplication.shared.terminate(nil) }) {
        terminationGuard.allowTermination = true
        terminate()
    }

    func showMainWindow() {
        SettingsWindowController.shared.show()
    }

    func captureNow() {
        Task { @MainActor in await captureEngine.captureNow() }
    }

    func checkForUpdates() {
        appUpdater.checkForUpdates(nil)
    }

    func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "TextSnap",
            .credits: NSAttributedString(string: String(localized: "about.credits")),
        ])
    }

    private func refreshCommands() {
        statusItemController?.setCommands(makeCommands())
    }

    private func makeCommands() -> [StatusItemCommand] {
        [
            StatusItemCommand(title: String(localized: "menu.captureNow"), action: { [weak self] in
                self?.captureNow()
            }),
            StatusItemCommand(title: String(localized: "menu.settings"), keyEquivalent: ",", action: { [weak self] in
                self?.showMainWindow()
            }),
            .separator(),
            StatusItemCommand(
                title: String(localized: "menu.launchAtLogin"),
                action: {
                    let manager = LaunchAtLoginManager.shared
                    manager.setEnabled(!manager.isEnabled)
                },
                state: {
                    LaunchAtLoginManager.shared.refresh()
                    switch LaunchAtLoginManager.shared.status {
                    case .on: return .on
                    case .needsApproval: return .mixed
                    case .off: return .off
                    }
                }
            ),
            .separator(),
            StatusItemCommand(title: String(localized: "menu.checkForUpdates"), action: { [weak self] in
                self?.checkForUpdates()
            }),
            StatusItemCommand(title: String(localized: "menu.about"), action: { [weak self] in
                self?.showAbout()
            }),
            StatusItemCommand(title: String(localized: "menu.quit"), keyEquivalent: "q", action: { [weak self] in
                self?.requestTermination()
            }),
        ]
    }
}
