import AppKit
import Foundation
import MacKitCore
import MacKitLaunchAtLogin
import Observation
import ServiceManagement

/// Launch-at-login state with no synchronous system query at app launch.
///
/// `SMAppService` is an XPC proxy and can answer slowly while `backgroundtaskmanagementd`
/// is busy at login. The cached `status` feeds menus and Settings instantly; reads
/// happen off the main thread and toggles remain explicit user actions.
@MainActor
@Observable
final class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()

    private(set) var status: LaunchAtLoginStatus = .off
    private(set) var lastErrorMessage: String?

    private var service: LaunchAtLoginService?
    private var refreshTask: Task<Void, Never>?

    private init() {}

    var isEnabled: Bool { status.isEffectivelyEnabled }
    var requiresApproval: Bool { status == .needsApproval }

    /// Cached tri-state for menu construction. Never touch `SMAppService` here:
    /// macOS rebuilds status menus while the login session is still settling.
    var menuState: NSControl.StateValue {
        switch status {
        case .on: return .on
        case .needsApproval: return .mixed
        case .off: return .off
        }
    }

    func setEnabled(_ enabled: Bool) {
        if requiresApproval, enabled {
            serviceNow().openSystemSettings()
            refreshInBackground()
            return
        }
        switch serviceNow().setEnabled(enabled) {
        case .success(let newStatus):
            status = newStatus
            lastErrorMessage = nil
            TextSnapLog.lifecycle.notice(
                "launch at login set enabled=\(enabled, privacy: .public) status=\(Self.diagnosticName(newStatus), privacy: .public)"
            )
        case .failure(let error):
            TextSnapLog.lifecycle.error(
                "launch at login toggle failed enabled=\(enabled, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
            refreshInBackground()
            lastErrorMessage = String(localized: "settings.launchAtLogin.failed")
        }
    }

    /// Coalesced background refresh, safe to call from launch, activation and
    /// Settings appearance.
    func refreshInBackground() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            let newStatus = await Self.readSystemStatus()
            guard !Task.isCancelled else { return }
            self?.status = newStatus
            TextSnapLog.lifecycle.notice(
                "launch at login status=\(Self.diagnosticName(newStatus), privacy: .public)"
            )
        }
    }

    func openSystemSettings() {
        serviceNow().openSystemSettings()
    }

    /// Creates the MacKit service only when a user explicitly acts on the
    /// toggle; its initializer performs a synchronous status read.
    private func serviceNow() -> LaunchAtLoginService {
        if let service { return service }
        let created = LaunchAtLoginService()
        service = created
        status = created.status
        return created
    }

    private nonisolated static func readSystemStatus() async -> LaunchAtLoginStatus {
        await Task.detached(priority: .utility) {
            let registration: SystemLaunchRegistration
            switch SMAppService.mainApp.status {
            case .enabled: registration = .enabled
            case .requiresApproval: registration = .requiresApproval
            case .notRegistered: registration = .notRegistered
            case .notFound: registration = .notFound
            @unknown default: registration = .unknown
            }
            return LaunchAtLoginStatusMapper.map(registration)
        }.value
    }

    private nonisolated static func diagnosticName(_ status: LaunchAtLoginStatus) -> String {
        switch status {
        case .on: return "on"
        case .off: return "off"
        case .needsApproval: return "needsApproval"
        }
    }
}
