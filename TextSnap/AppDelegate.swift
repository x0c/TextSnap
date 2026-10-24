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
    private var appUpdater: AppUpdater?
    private var deferredStartupTasks: [Task<Void, Never>] = []
    private var isLoginLaunch = false
    private let terminationGuard = TerminationGuard()
    let captureEngine = CaptureEngine.shared

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    /// Registration must happen before any window, status-menu or system-service
    /// work. At login those settle slowly and used to delay (or block) the
    /// shortcut for minutes.
    func applicationWillFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        let launchedAtLogin = LoginLaunchDetector.isLaunchedAsLoginItem
        isLoginLaunch = launchedAtLogin
        TextSnapLog.lifecycle.notice(
            "willFinishLaunching loginLaunch=\(launchedAtLogin, privacy: .public)"
        )

        HotkeyManager.shared.onHotKey = { [weak self] in
            Task { @MainActor in await self?.captureEngine.captureNow() }
        }
        HotkeyManager.shared.startFromLaunch()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let launchStarted = DispatchTime.now()
        AppDelegate.shared = self
        terminationGuard.isUpdateSessionInProgress = { [weak self] in
            self?.appUpdater?.sessionInProgress ?? false
        }

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
        TextSnapLog.lifecycle.notice(
            "status item ready after \(TextSnapLog.milliseconds(since: launchStarted), privacy: .public)ms"
        )

        becomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshCommands()
                LaunchAtLoginManager.shared.refreshInBackground()
            }
        }

        // Cached tri-state first; the real read happens off-main.
        LaunchAtLoginManager.shared.refreshInBackground()

        // Sparkle startup, Vision warm-up and TCC preflight are useful but must
        // never sit between the user and the hotkey.
        deferredStartupTasks.append(Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.startUpdaterIfNeeded()
        })
        deferredStartupTasks.append(Task.detached(priority: .utility) {
            TextRecognizer.warmUp()
        })
        deferredStartupTasks.append(Task.detached(priority: .utility) {
            _ = ScreenCapturePermission.isGranted
        })

        // First launch and login launch stay silent. No window.
        readyAt = Date()
        TextSnapLog.lifecycle.notice(
            "didFinishLaunching complete after \(TextSnapLog.milliseconds(since: launchStarted), privacy: .public)ms"
        )
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
            isLoginLaunch: isLoginLaunch,
            menubarIsPrimaryEntry: true,
            secondsSinceReady: Date().timeIntervalSince(readyAt)
        ) == .showRecoveryWindow {
            showMainWindow()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        deferredStartupTasks.forEach { $0.cancel() }
        deferredStartupTasks = []
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
        startUpdaterIfNeeded()
        appUpdater?.checkForUpdates(nil)
    }

    func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "TextSnap",
            .credits: NSAttributedString(string: String(localized: "about.credits")),
        ])
    }

    /// Sparkle starts after the app is usable; its startup performs bundle and
    /// XPC-service checks that do not belong on the launch path.
    private func startUpdaterIfNeeded() {
        guard appUpdater == nil else { return }
        let started = DispatchTime.now()
        appUpdater = AppUpdater()
        TextSnapLog.lifecycle.notice(
            "updater started after \(TextSnapLog.milliseconds(since: started), privacy: .public)ms"
        )
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
                    // Cached value only: menu rebuilds must never query SMAppService.
                    LaunchAtLoginManager.shared.menuState
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
