import AppIntents
import Foundation
import SwiftUI

/// Core action for Shortcuts / Spotlight: capture a screen region with the
/// system selector, recognize text on-device, copy it to the clipboard.
/// Baseline B5: the tool's core action must be automatable without forcing UI.
/// Label strings live in the xcstrings (intent.capture.*) so both languages work.
struct CaptureTextIntent: AppIntent {
    static var title: LocalizedStringResource {
        LocalizedStringResource(
            "intent.capture.title",
            defaultValue: "Capture Screen Text",
            table: "Localizable"
        )
    }

    static var description: IntentDescription {
        IntentDescription(
            LocalizedStringResource(
                "intent.capture.description",
                defaultValue: "Capture a screen region and copy its text to the clipboard.",
                table: "Localizable"
            )
        )
    }

    /// The capture flow uses the system region selector and may show a
    /// one-shot alert, so the app must come forward when run headless.
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        await CaptureEngine.shared.captureNow()
        let text = CaptureEngine.shared.lastText
        guard !text.isEmpty else {
            throw CaptureIntentError.noText
        }
        return .result(value: text)
    }
}

enum CaptureIntentError: Error, LocalizedError {
    case noText

    var errorDescription: String? {
        String(localized: "capture.empty.body")
    }
}
