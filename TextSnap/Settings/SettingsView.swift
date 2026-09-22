import AppKit
import Combine
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var hotkeyManager = HotkeyManager.shared
    @Bindable private var launchAtLogin = LaunchAtLoginManager.shared
    @Bindable private var engine = CaptureEngine.shared
    @State private var permissionGranted = ScreenCapturePermission.isGranted

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            shortcutCard
            permissionCard
            launchCard
            lastResultCard
            actionsCard
            Text(versionFooter)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(20)
        .frame(width: 460)
        .background(Color(nsColor: .windowBackgroundColor))
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

    private var shortcutCard: some View {
        GroupBox(label: Label(String(localized: "settings.hotkey.section"), systemImage: "keyboard")) {
            VStack(alignment: .leading, spacing: 8) {
                Text(hotkeyManager.shortcut?.displayName ?? String(localized: "settings.hotkey.cleared"))
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                    .accessibilityLabel(String(localized: "settings.hotkey.current"))
                    .accessibilityValue(hotkeyManager.shortcut?.displayName ?? String(localized: "settings.hotkey.cleared"))
                Text(hotkeyManager.isRecording
                    ? String(localized: "settings.hotkey.recordingHint")
                    : String(localized: "settings.hotkey.hint"))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var permissionCard: some View {
        GroupBox(label: Label(String(localized: "settings.permission.section"), systemImage: "record.circle")) {
            VStack(alignment: .leading, spacing: 8) {
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var launchCard: some View {
        GroupBox(label: Label(String(localized: "settings.launchAtLogin.section"), systemImage: "bolt.circle")) {
            VStack(alignment: .leading, spacing: 8) {
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
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var lastResultCard: some View {
        GroupBox(label: Label(String(localized: "settings.lastResult.section"), systemImage: "doc.on.clipboard")) {
            VStack(alignment: .leading, spacing: 8) {
                if engine.lastText.isEmpty {
                    Text(String(localized: "settings.lastResult.empty"))
                        .foregroundStyle(.secondary)
                } else {
                    Text(engine.lastText)
                        .lineLimit(4)
                        .textSelection(.enabled)
                    Button {
                        engine.copyLastAgain()
                    } label: {
                        Label(String(localized: "settings.lastResult.copyAgain"), systemImage: "doc.on.doc")
                    }
                    .focusEffectDisabled()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actionsCard: some View {
        GroupBox(label: Label(String(localized: "settings.actions.section"), systemImage: "ellipsis.circle")) {
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    AppDelegate.shared?.captureNow()
                } label: {
                    Label(String(localized: "menu.captureNow"), systemImage: "camera.viewfinder")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                .focusEffectDisabled()
                Divider()
                    .padding(.vertical, 4)
                actionRow(
                    title: String(localized: "menu.checkForUpdates"),
                    systemImage: "arrow.triangle.2.circlepath"
                ) {
                    AppDelegate.shared?.checkForUpdates()
                }
                Divider()
                actionRow(
                    title: String(localized: "menu.about"),
                    systemImage: "info.circle"
                ) {
                    AppDelegate.shared?.showAbout()
                }
                Divider()
                actionRow(
                    title: String(localized: "menu.quit"),
                    systemImage: "power"
                ) {
                    AppDelegate.shared?.requestTermination()
                }
            }
        }
    }

    private func actionRow(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, alignment: .center)
                    .accessibilityHidden(true)
                Text(title)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 3)
        }
        .buttonStyle(.borderless)
        .focusEffectDisabled()
    }

    /// Bundle version, read live so the xcconfig single source stays authoritative.
    private var versionFooter: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "\(String(localized: "settings.version.label")) \(short) (\(build))"
    }
}
