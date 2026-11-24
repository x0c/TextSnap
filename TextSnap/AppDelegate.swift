import AppKit
import MacKitCore
import MacKitLifecycle
import MacKitStatusItem
import MacKitUpdater
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) static weak var shared: AppDelegate?

    private var statusItemController: StatusItemController?
    private var becomeActiveObserver: NSObjectProtocol?
    private var readyAt = Date()
    private var appUpdater: AppUpdater?
    let updateAvailability = UpdateAvailabilityState()
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
        guard !E2ERuntime.isEnabled else { return }

        HotkeyManager.shared.onHotKey = { [weak self] in
            Task { @MainActor in await self?.captureEngine.captureNow(source: .hotkey) }
        }
        HotkeyManager.shared.startFromLaunch()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let launchStarted = DispatchTime.now()
        AppDelegate.shared = self
        logStartupBanner()

        if E2ERuntime.isEnabled {
            terminationGuard.allowTermination = true
            NSApp.appearance = NSAppearance(named: .aqua)
            SettingsWindowController.shared.showForE2E()
            TextSnapLog.lifecycle.notice(
                "e2e launch ready after \(TextSnapLog.milliseconds(since: launchStarted))ms"
            )
            return
        }

        terminationGuard.isUpdateSessionInProgress = { [weak self] in
            self?.appUpdater?.sessionInProgress ?? false
        }

        statusItemController = StatusItemController(
            commands: makeCommands(),
            onPrimaryAction: { [weak self] in
                Task { @MainActor in await self?.captureEngine.captureNow(source: .menuBarLeftClick) }
            }
        )
        statusItemController?.setTemplateImage(
            StatusBarIcon.image(pointSize: 18),
            accessibilityLabel: String(localized: "status.item.accessibility")
        )
        statusItemController?.isIconVisible = TextSnapSettings.shared.isMenuBarIconVisible
        TextSnapLog.lifecycle.notice(
            "status item ready after \(TextSnapLog.milliseconds(since: launchStarted))ms"
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

        // Sparkle startup and TCC preflight stay off the launch critical path.
        // We intentionally do NOT pre-warm Vision at launch: ANECompilerService
        // compilation on launch competes with the user's first capture and
        // caused 60s+ lockouts when paired with capture serialization.
        deferredStartupTasks.append(Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.startUpdaterIfNeeded()
        })
        deferredStartupTasks.append(Task.detached(priority: .utility) {
            _ = ScreenCapturePermission.isGranted
            ScreenCapture.cleanupOrphanedTempFiles()
        })

        // Classify the launch only here: AppKit still reports no Apple Event in
        // applicationWillFinishLaunching, and an SMAppService login launch never
        // gets one at all. Visible-icon first launch and every login launch stay silent.
        let launchEventID = NSAppleEventManager.shared().currentAppleEvent.map {
            String(format: "0x%08X", $0.eventID)
        } ?? "none"
        isLoginLaunch = LaunchClassification.isCurrentProcessLoginLaunch
        readyAt = Date()
        let iconVisible = TextSnapSettings.shared.isMenuBarIconVisible
        let showsRecoveryWindow = MenuBarReopenPolicy.shouldShowRecoveryWindow(
            iconVisible: iconVisible,
            isLoginLaunch: isLoginLaunch
        )
        TextSnapLog.lifecycle.notice(
            "didFinishLaunching complete after \(TextSnapLog.milliseconds(since: launchStarted))ms launchEvent=\(launchEventID) loginLaunch=\(self.isLoginLaunch) iconVisible=\(iconVisible) recoveryWindow=\(showsRecoveryWindow)"
        )
        if showsRecoveryWindow {
            showMainWindow()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        terminationGuard.shouldTerminate() ? .terminateNow : .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !E2ERuntime.isEnabled else { return true }
        if MenuBarReopenPolicy.presentation(
            iconVisible: statusItemController?.isIconVisible ?? TextSnapSettings.shared.isMenuBarIconVisible,
            isReopenOrLaunch: true,
            // This is a new user request, not the process's original login launch.
            isLoginLaunch: false,
            menubarIsPrimaryEntry: true,
            secondsSinceReady: Date().timeIntervalSince(readyAt)
        ) == .showRecoveryWindow {
            showMainWindow()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        TextSnapLog.lifecycle.notice("application terminating")
        deferredStartupTasks.forEach { $0.cancel() }
        deferredStartupTasks = []
        HotkeyManager.shared.unregister()
        if let becomeActiveObserver {
            NotificationCenter.default.removeObserver(becomeActiveObserver)
        }
        TextSnapLog.flush()
    }

    func requestTermination(terminate: () -> Void = { NSApplication.shared.terminate(nil) }) {
        terminationGuard.allowTermination = true
        terminate()
    }

    func showMainWindow() {
        SettingsWindowController.shared.show()
    }

    func setMenuBarIconVisible(_ visible: Bool) {
        guard TextSnapSettings.shared.setMenuBarIconVisible(visible) else {
            TextSnapLog.settings.error("menuBar iconVisible save failed target=\(visible)")
            let alert = NSAlert()
            alert.messageText = String(localized: "settings.menuBar.saveFailed.title")
            alert.informativeText = String(localized: "settings.menuBar.saveFailed.body")
            alert.addButton(withTitle: String(localized: "alert.ok"))
            alert.runModal()
            return
        }
        statusItemController?.isIconVisible = visible
        TextSnapLog.settings.notice("menuBar iconVisible set to \(visible)")
    }

    func captureNow(source: CaptureEngine.CaptureSource = .menuBarMenu) {
        Task { @MainActor in await captureEngine.captureNow(source: source) }
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

    private func logStartupBanner() {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = (info["CFBundleShortVersionString"] as? String) ?? "?"
        let build = (info["CFBundleVersion"] as? String) ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let pid = ProcessInfo.processInfo.processIdentifier
        let shortcutDesc = HotkeyManager.shared.shortcut?.displayName ?? "none"
        TextSnapLog.lifecycle.notice(
            "app_start version=\(version) build=\(build) os=\"\(os)\" pid=\(pid) iconVisible=\(TextSnapSettings.shared.isMenuBarIconVisible) hotkey=\(shortcutDesc) secureInput=\(HotkeyManager.isSecureEventInputActive) e2e=\(E2ERuntime.isEnabled)"
        )
    }

    /// Sparkle starts after the app is usable; its startup performs bundle and
    /// XPC-service checks that do not belong on the launch path.
    private func startUpdaterIfNeeded() {
        guard appUpdater == nil else { return }
        let started = DispatchTime.now()
        appUpdater = AppUpdater(
            availability: updateAvailability,
            onAvailableVersionChange: { [weak self] _ in
                self?.refreshCommands()
            }
        )
        if updateAvailability.availableVersion != nil {
            refreshCommands()
        }
        TextSnapLog.lifecycle.notice(
            "updater started after \(TextSnapLog.milliseconds(since: started))ms"
        )
    }

    private func refreshCommands() {
        statusItemController?.setCommands(makeCommands())
    }

    private func makeCommands() -> [StatusItemCommand] {
        let updateTitle: String = if let version = updateAvailability.availableVersion {
            String(format: String(localized: "menu.installUpdate"), version)
        } else {
            String(localized: "menu.checkForUpdates")
        }
        return [
            StatusItemCommand(title: String(localized: "menu.captureNow"), action: { [weak self] in
                self?.captureNow(source: .menuBarMenu)
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
            StatusItemCommand(title: String(localized: "menu.hideMenuBarIcon"), action: { [weak self] in
                self?.setMenuBarIconVisible(false)
            }),
            .separator(),
            StatusItemCommand(title: updateTitle, action: { [weak self] in
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
