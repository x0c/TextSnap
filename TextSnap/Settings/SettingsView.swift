import AppKit
import MacKitUpdater
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var hotkeyManager = HotkeyManager.shared
    @Bindable private var launchAtLogin = LaunchAtLoginManager.shared
    @Bindable private var engine = CaptureEngine.shared
    @Bindable private var settings = TextSnapSettings.shared
    @State private var permissionGranted = true
    @State private var permissionTask: Task<Void, Never>?
    @State private var contentHeight: CGFloat = 400

    var body: some View {
        Form {
            Section(String(localized: "settings.capture.section")) {
                shortcutRow
                permissionRow
                LabeledContent(String(localized: "settings.capture.row")) {
                    Button(String(localized: "menu.captureNow")) {
                        AppDelegate.shared?.captureNow(source: .settingsButton)
                    }
                    .disabled(engine.isCapturing)
                    .accessibilityIdentifier("settings.capture.now")
                }
            }
            Section(String(localized: "settings.lastResult.section")) {
                if engine.lastText.isEmpty {
                    Text(String(localized: "settings.lastResult.empty"))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.lastResult.empty")
                } else {
                    LabeledContent(String(localized: "settings.lastResult.text")) {
                        Button(String(localized: "settings.lastResult.copyAgain")) {
                            engine.copyLastAgain()
                        }
                        .accessibilityIdentifier("settings.lastResult.copyAgain")
                    }
                    Text(engine.lastText)
                        .lineLimit(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("settings.lastResult.text")
                }
            }
            Section(String(localized: "settings.general.section")) {
                Toggle(String(localized: "settings.launchAtLogin.toggle"), isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                .accessibilityIdentifier("settings.launchAtLogin.toggle")
                if launchAtLogin.requiresApproval {
                    LabeledContent {
                        Button(String(localized: "settings.launchAtLogin.openSettings")) {
                            launchAtLogin.openSystemSettings()
                        }
                    } label: {
                        Text(String(localized: "settings.launchAtLogin.needsApproval"))
                            .foregroundStyle(.secondary)
                    }
                }
                if let message = launchAtLogin.lastErrorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Toggle(String(localized: "settings.menuBar.showIcon"), isOn: Binding(
                    get: { settings.isMenuBarIconVisible },
                    set: { AppDelegate.shared?.setMenuBarIconVisible($0) }
                ))
                .help(String(localized: "settings.menuBar.recoveryHint"))
                .accessibilityIdentifier("settings.menuBar.showIcon")
            }
            Section { aboutRow }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .scrollDisabled(true)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { _, height in
            if height > 0 { contentHeight = height }
        }
        .frame(width: 480, height: contentHeight)
        .fixedSize()
        .focusEffectDisabled()
        .transaction { transaction in
            if E2ERuntime.isEnabled {
                transaction.animation = nil
            }
        }
        .background(SettingsWindowObserver())
        .onAppear(perform: refreshStatus)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshStatus()
        }
        .onChange(of: engine.lastText) { _, _ in
            DispatchQueue.main.async {
                SettingsWindowController.shared.flushRedrawIfNeeded()
            }
        }
        .onChange(of: settings.isMenuBarIconVisible) { _, _ in
            DispatchQueue.main.async {
                SettingsWindowController.shared.flushRedrawIfNeeded()
            }
        }
        .onChange(of: hotkeyManager.shortcut) { _, _ in
            DispatchQueue.main.async {
                SettingsWindowController.shared.flushRedrawIfNeeded()
            }
        }
        .onDisappear {
            permissionTask?.cancel()
            hotkeyManager.stopRecording()
        }
        .onExitCommand {
            if hotkeyManager.isRecording {
                hotkeyManager.stopRecording()
            } else {
                SettingsWindowController.shared.close()
            }
        }
    }

    @ViewBuilder
    private var shortcutRow: some View {
        LabeledContent(String(localized: "settings.hotkey.section")) {
            HStack(spacing: 8) {
                Button(hotkeyManager.isRecording
                    ? String(localized: "settings.hotkey.recording")
                    : hotkeyManager.shortcut?.displayName ?? String(localized: "settings.hotkey.record")) {
                    hotkeyManager.beginRecording()
                }
                .disabled(hotkeyManager.isRecording)
                .accessibilityLabel(String(localized: "settings.hotkey.current"))
                .accessibilityValue(hotkeyManager.shortcut?.displayName ?? String(localized: "settings.hotkey.cleared"))
                .accessibilityIdentifier("settings.hotkey.button")
                .help(String(localized: "settings.hotkey.recordingHint"))
                Menu {
                    Button(String(localized: "settings.hotkey.clear")) { hotkeyManager.clearShortcut() }
                    Button(String(localized: "settings.hotkey.restore")) { hotkeyManager.restoreFactoryDefault() }
                } label: {
                    Label(String(localized: "settings.hotkey.actions"), systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityIdentifier("settings.hotkey.actions")
            }
        }
        if let message = hotkeyManager.lastErrorMessage {
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .accessibilityIdentifier("settings.hotkey.error")
        }
    }

    @ViewBuilder
    private var permissionRow: some View {
        LabeledContent(String(localized: "settings.permission.section")) {
            if permissionGranted {
                Text(String(localized: "settings.permission.granted"))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.permission.status")
            } else {
                Button(String(localized: "settings.permission.openSettings")) {
                    ScreenCapturePermission.openSystemSettings()
                }
                .accessibilityIdentifier("settings.permission.openSettings")
            }
        }
        if !permissionGranted {
            Text(String(localized: "settings.permission.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var aboutRow: some View {
        HStack(spacing: 10) {
            Button {
                AppDelegate.shared?.showAbout()
            } label: {
                HStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 32, height: 32)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: "TextSnap").fontWeight(.medium)
                        Text(verbatim: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "menu.about"))
            .accessibilityIdentifier("settings.about.button")
            .help(String(localized: "menu.about"))
            Spacer(minLength: 8)
            UpdateCheckButton(availability: AppDelegate.shared?.updateAvailability)
            Button(String(localized: "settings.quit")) { AppDelegate.shared?.requestTermination() }
                .accessibilityIdentifier("settings.quit.button")
        }
    }

    private func refreshStatus() {
        if E2ERuntime.isEnabled {
            permissionGranted = true
            return
        }
        permissionTask?.cancel()
        permissionTask = Task {
            let granted = await Task.detached(priority: .userInitiated) {
                ScreenCapturePermission.isGranted
            }.value
            guard !Task.isCancelled else { return }
            permissionGranted = granted
        }
        launchAtLogin.refreshInBackground()
    }
}

private struct UpdateCheckButton: View {
    let availability: UpdateAvailabilityState?

    var body: some View {
        Button(title) {
            AppDelegate.shared?.checkForUpdates()
        }
        .accessibilityIdentifier("settings.updates.button")
    }

    private var title: String {
        if let version = availability?.availableVersion {
            return String(format: String(localized: "menu.installUpdate"), version)
        }
        return String(localized: "menu.checkForUpdates")
    }
}
