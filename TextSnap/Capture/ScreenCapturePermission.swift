import AppKit
import CoreGraphics

/// Screen recording permission is pure TCC. No entitlement can replace the user tap.
enum ScreenCapturePermission {
    nonisolated static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Only prompts when undecided. Returns false when already denied.
    @discardableResult
    nonisolated static func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openSystemSettings() {
        let specific = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.security")
        if let specific, NSWorkspace.shared.open(specific) {
            TextSnapLog.settings.notice("opened System Settings Privacy_ScreenCapture")
            return
        }
        if let fallback, NSWorkspace.shared.open(fallback) {
            TextSnapLog.settings.notice("opened System Settings privacy root fallback")
            return
        }
        TextSnapLog.settings.error("failed to open System Settings for screen recording")
    }
}
