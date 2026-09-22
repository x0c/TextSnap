import AppKit
import Foundation
import SwiftUI

/// One capture run: permission → system selector → Vision → pasteboard.
/// A second trigger while a run is in flight is dropped, never queued.
@MainActor
@Observable
final class CaptureEngine {
    static let shared = CaptureEngine()

    var lastText: String = ""
    var isCapturing = false

    func captureNow() async {
        // Re-entrant triggers while a run is in flight are dropped, never queued.
        if isCapturing { return }
        isCapturing = true
        defer { isCapturing = false }

        if !ScreenCapturePermission.isGranted {
            ScreenCapturePermission.request()
            if !ScreenCapturePermission.isGranted {
                showPermissionAlert()
                return
            }
        }

        let imageURL: URL
        do {
            imageURL = try await ScreenCapture.captureRegion()
        } catch {
            // Esc cancel: stay silent.
            return
        }
        defer { try? FileManager.default.removeItem(at: imageURL) }

        let text: String
        do {
            text = try TextRecognizer.recognizeText(in: imageURL)
        } catch {
            showAlert(
                title: String(localized: "capture.failed.title"),
                body: String(localized: "capture.failed.body")
            )
            return
        }

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
    }

    func copyLastAgain() {
        guard !lastText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastText, forType: .string)
        playConfirmSound()
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
