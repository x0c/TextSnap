import MacKitCore
@testable import TextSnap
import Testing

@Test func launchdStartWithoutOpenEventIsALoginLaunch() {
    // SMAppService.mainApp login launches reach launchd with no Apple Event.
    #expect(LaunchClassification.isLoginLaunch(hasLaunchAppleEvent: false, hasLegacyLoginMarker: false))
    // A legacy login item is a login launch even when it carries its marker event.
    #expect(LaunchClassification.isLoginLaunch(hasLaunchAppleEvent: true, hasLegacyLoginMarker: true))
    #expect(LaunchClassification.isLoginLaunch(hasLaunchAppleEvent: false, hasLegacyLoginMarker: true))
}

@Test func finderDockSpotlightAndOpenLaunchesAreUserLaunches() {
    #expect(!LaunchClassification.isLoginLaunch(hasLaunchAppleEvent: true, hasLegacyLoginMarker: false))
}

@Test func hiddenIconRecoveryStaysSilentForALaunchdStart() {
    let loginLaunch = LaunchClassification.isLoginLaunch(
        hasLaunchAppleEvent: false,
        hasLegacyLoginMarker: false
    )
    #expect(!MenuBarReopenPolicy.shouldShowRecoveryWindow(iconVisible: false, isLoginLaunch: loginLaunch))
}

@Test func hiddenIconRecoveryStillAnswersAUserLaunch() {
    let loginLaunch = LaunchClassification.isLoginLaunch(
        hasLaunchAppleEvent: true,
        hasLegacyLoginMarker: false
    )
    #expect(MenuBarReopenPolicy.shouldShowRecoveryWindow(iconVisible: false, isLoginLaunch: loginLaunch))
}
