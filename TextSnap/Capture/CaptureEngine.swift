import AppKit
import Foundation
import SwiftUI

/// One capture run: permission → system selector → Vision → pasteboard.
/// A second trigger while a run is in flight is dropped, never queued.
/// Vision runs off the main actor so a cold first OCR can never freeze the
/// menu bar, the hotkey or the rest of the app.
@MainActor
@Observable
final class CaptureEngine {
    static let shared = CaptureEngine()

    var lastText: String = ""
    var isCapturing = false

    func captureNow() async {
        // Re-entrant triggers while a run is in flight are dropped, never queued.
        if isCapturing {
            TextSnapLog.capture.notice("trigger dropped: capture already in flight")
            return
        }
        isCapturing = true
        defer { isCapturing = false }

        let captureStarted = DispatchTime.now()
        TextSnapLog.capture.notice("capture requested")

        // TCC can answer slowly while the login session is settling; keep the
        // check off the main thread so the app stays responsive.
        let granted = await Task.detached(priority: .userInitiated) {
            ScreenCapturePermission.isGranted
        }.value
        if !granted {
            ScreenCapturePermission.request()
            let grantedAfterPrompt = await Task.detached(priority: .userInitiated) {
                ScreenCapturePermission.isGranted
            }.value
            if !grantedAfterPrompt {
                TextSnapLog.capture.notice("capture blocked: screen recording not granted")
                showPermissionAlert()
                return
            }
        }

        let imageURL: URL
        do {
            imageURL = try await ScreenCapture.captureRegion()
        } catch {
            // Esc cancel: stay silent.
            TextSnapLog.capture.notice(
                "selector ended without an image after \(TextSnapLog.milliseconds(since: captureStarted), privacy: .public)ms"
            )
            return
        }
        defer { try? FileManager.default.removeItem(at: imageURL) }
        TextSnapLog.capture.notice(
            "selector finished after \(TextSnapLog.milliseconds(since: captureStarted), privacy: .public)ms"
        )

        let ocrStarted = DispatchTime.now()
        let text: String
        do {
            text = try await Task.detached(priority: .userInitiated) {
                try TextRecognizer.recognizeText(in: imageURL)
            }.value
        } catch {
            TextSnapLog.capture.error(
                "ocr failed after \(TextSnapLog.milliseconds(since: ocrStarted), privacy: .public)ms: \(String(describing: error), privacy: .public)"
            )
            showAlert(
                title: String(localized: "capture.failed.title"),
                body: String(localized: "capture.failed.body")
            )
            return
        }
        TextSnapLog.capture.notice(
            "ocr finished in \(TextSnapLog.milliseconds(since: ocrStarted), privacy: .public)ms chars=\(text.count, privacy: .public)"
        )

        if text.isEmpty {
            showAlert(
                title: String(localized: "capture.empty.title"),
                body: String(localized: "capture.empty.body")
            )
            return
        }

        lastText = text
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        playConfirmSound()
        TextSnapLog.capture.notice(
            "copied to pasteboard; total \(TextSnapLog.milliseconds(since: captureStarted), privacy: .public)ms"
        )
    }

    func copyLastAgain() {
        guard !lastText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastText, forType: .string)
        playConfirmSound()
        TextSnapLog.capture.notice("copied last result again")
    }

    private func playConfirmSound() {
        if let sound = NSSound(named: "Glass") {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = String(localized: "permission.denied.title")
        alert.informativeText = String(localized: "permission.denied.body")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "permission.openSettings"))
        alert.addButton(withTitle: String(localized: "alert.ok"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            ScreenCapturePermission.openSystemSettings()
        }
    }

    private func showAlert(title: String, body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "alert.ok"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
