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
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
