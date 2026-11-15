import AppKit
import MacKitLifecycle

/// Classifies how the current process was started.
///
/// `SMAppService.mainApp` opens a login item through launchd without an
/// open-application Apple Event, while Finder, Dock, Spotlight and `open`
/// deliver `kAEOpenApplication`. AppKit only exposes that event from
/// `applicationDidFinishLaunching`; it is still nil in
/// `applicationWillFinishLaunching`, so the classification must not happen there.
///
/// A launchd-started process with no launch event counts as a login launch.
/// That keeps the hidden-icon recovery window off the login path, which is
/// exactly the path that used to pop it at every boot. A legacy login item is
/// also a login launch; it additionally marks the event with
/// `keyAELaunchedAsLogInItem`.
enum LaunchClassification {
    nonisolated static func isLoginLaunch(hasLaunchAppleEvent: Bool, hasLegacyLoginMarker: Bool) -> Bool {
        hasLegacyLoginMarker || !hasLaunchAppleEvent
    }

    /// Reads the live launch context. Only call after AppKit has dispatched the
    /// launch Apple Event, that is from `applicationDidFinishLaunching` onward.
    @MainActor
    static var isCurrentProcessLoginLaunch: Bool {
        isLoginLaunch(
            hasLaunchAppleEvent: NSAppleEventManager.shared().currentAppleEvent != nil,
            hasLegacyLoginMarker: LoginLaunchDetector.isLaunchedAsLoginItem
        )
    }
}
