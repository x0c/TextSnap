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

    private var generation = 0
    var onDidCaptureText: ((String) -> Void)?

    func captureNow() async {
        if isCapturing { return }
        generation &+= 1
        let mine = generation
        isCapturing = true
        defer { isCapturing = false }
        guard mine == generation else { return }

        if !ScreenCapturePermission.isGranted {
            ScreenCapturePermission.request()
            if !ScreenCapturePermission.isGranted {
                showPermissionAlert()
                return
            }
        }
        guard mine == generation else { return }

        let imageURL: URL
        do {
            imageURL = try await ScreenCapture.captureRegion()
        } catch {
            // Esc cancel: stay silent.
            return
        }
        defer { try? FileManager.default.removeItem(at: imageURL) }
        guard mine == generation else { return }

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
        guard mine == generation else { return }

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
        onDidCaptureText?(text)
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
        alert.addButton(withTitle: String(localized: "updates.unavailable.ok"))
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
        alert.addButton(withTitle: String(localized: "updates.unavailable.ok"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
