import AppKit
import Combine
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var hotkeyManager = HotkeyManager.shared
    @Bindable private var launchAtLogin = LaunchAtLoginManager.shared
    @Bindable private var engine = CaptureEngine.shared
    @State private var permissionGranted = ScreenCapturePermission.isGranted

    var body: some View {
        Form {
            shortcutSection
            permissionSection
            launchSection
            lastResultSection
            actionsSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 480)
        .padding(.bottom, 8)
        .focusEffectDisabled()
        .onAppear {
            permissionGranted = ScreenCapturePermission.isGranted
            launchAtLogin.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionGranted = ScreenCapturePermission.isGranted
            launchAtLogin.refresh()
        }
        .onDisappear {
            hotkeyManager.stopRecording()
        }
    }

    private var shortcutSection: some View {
        Section(String(localized: "settings.hotkey.section")) {
            Text(hotkeyManager.shortcut?.displayName ?? String(localized: "settings.hotkey.cleared"))
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .accessibilityLabel(String(localized: "settings.hotkey.current"))
                .accessibilityValue(hotkeyManager.shortcut?.displayName ?? String(localized: "settings.hotkey.cleared"))
            Text(hotkeyManager.isRecording
                ? String(localized: "settings.hotkey.recordingHint")
                : String(localized: "settings.hotkey.hint"))
                .foregroundStyle(.secondary)
            HStack {
                Button(hotkeyManager.isRecording
                    ? String(localized: "settings.hotkey.recording")
                    : String(localized: "settings.hotkey.record")) {
                        hotkeyManager.beginRecording()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(hotkeyManager.isRecording)
                    .focusEffectDisabled()
                Button(String(localized: "settings.hotkey.clear")) {
                    hotkeyManager.clearShortcut()
                }
                .buttonStyle(.bordered)
                .focusEffectDisabled()
                Button(String(localized: "settings.hotkey.restore")) {
                    hotkeyManager.restoreFactoryDefault()
                }
                .buttonStyle(.bordered)
                .focusEffectDisabled()
            }
            if let message = hotkeyManager.lastErrorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var permissionSection: some View {
        Section(String(localized: "settings.permission.section")) {
            Button(permissionGranted
                ? String(localized: "settings.permission.granted")
                : String(localized: "settings.permission.openSettings")) {
                    ScreenCapturePermission.openSystemSettings()
                }
                .focusEffectDisabled()
                .disabled(permissionGranted)
            if !permissionGranted {
                Text(String(localized: "settings.permission.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var launchSection: some View {
        Section(String(localized: "settings.launchAtLogin.section")) {
            Toggle(
                String(localized: "settings.launchAtLogin.toggle"),
                isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                )
            )
            .focusEffectDisabled()
            if launchAtLogin.requiresApproval {
                Text(String(localized: "settings.launchAtLogin.needsApproval"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(String(localized: "settings.launchAtLogin.openSettings")) {
                    launchAtLogin.openSystemSettings()
                }
                .focusEffectDisabled()
            }
            if let message = launchAtLogin.lastErrorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var lastResultSection: some View {
        Section(String(localized: "settings.lastResult.section")) {
            if engine.lastText.isEmpty {
                Text(String(localized: "settings.lastResult.empty"))
                    .foregroundStyle(.secondary)
            } else {
                Text(engine.lastText)
                    .lineLimit(4)
                    .textSelection(.enabled)
                Button(String(localized: "settings.lastResult.copyAgain")) {
                    engine.copyLastAgain()
                }
                .focusEffectDisabled()
            }
        }
    }

    private var actionsSection: some View {
        Section(String(localized: "settings.actions.section")) {
            Button(String(localized: "menu.captureNow")) {
                AppDelegate.shared?.captureNow()
            }
            .focusEffectDisabled()
            Button(String(localized: "menu.checkForUpdates")) {
                AppDelegate.shared?.checkForUpdates()
            }
            .focusEffectDisabled()
            Button(String(localized: "menu.about")) {
                AppDelegate.shared?.showAbout()
            }
            .focusEffectDisabled()
            Button(String(localized: "menu.quit")) {
                AppDelegate.shared?.requestTermination()
            }
            .focusEffectDisabled()
            Text(versionFooter)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Bundle version, read live so the xcconfig single source stays authoritative.
    private var versionFooter: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "\(String(localized: "settings.version.label")) \(short) (\(build))"
    }
}
