import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var hotkeyManager = HotkeyManager.shared
    @Bindable private var launchAtLogin = LaunchAtLoginManager.shared
    @Bindable private var engine = CaptureEngine.shared
    @State private var permissionGranted = ScreenCapturePermission.isGranted
    @State private var contentHeight: CGFloat = 400

    var body: some View {
        Form {
            Section(String(localized: "settings.capture.section")) {
                shortcutRow
                permissionRow
                LabeledContent(String(localized: "settings.capture.row")) {
                    Button(String(localized: "menu.captureNow")) {
                        AppDelegate.shared?.captureNow()
                    }
                    .disabled(engine.isCapturing)
                }
            }
            Section(String(localized: "settings.lastResult.section")) {
                if engine.lastText.isEmpty {
                    Text(String(localized: "settings.lastResult.empty"))
                        .foregroundStyle(.secondary)
                } else {
                    LabeledContent(String(localized: "settings.lastResult.text")) {
                        Button(String(localized: "settings.lastResult.copyAgain")) {
                            engine.copyLastAgain()
                        }
                    }
                    Text(engine.lastText)
                        .lineLimit(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Section(String(localized: "settings.general.section")) {
                Toggle(String(localized: "settings.launchAtLogin.toggle"), isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
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
        .background(SettingsWindowObserver())
        .onAppear(perform: refreshStatus)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshStatus()
        }
        .onDisappear { hotkeyManager.stopRecording() }
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
            }
        }
        if let message = hotkeyManager.lastErrorMessage {
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var permissionRow: some View {
        LabeledContent(String(localized: "settings.permission.section")) {
            if permissionGranted {
                Text(String(localized: "settings.permission.granted"))
                    .foregroundStyle(.secondary)
            } else {
                Button(String(localized: "settings.permission.openSettings")) {
                    ScreenCapturePermission.openSystemSettings()
                }
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
            .help(String(localized: "menu.about"))
            Spacer(minLength: 8)
            Button(String(localized: "menu.checkForUpdates")) { AppDelegate.shared?.checkForUpdates() }
            Button(String(localized: "settings.quit")) { AppDelegate.shared?.requestTermination() }
        }
    }

    private func refreshStatus() {
        permissionGranted = ScreenCapturePermission.isGranted
        launchAtLogin.refresh()
    }
}
