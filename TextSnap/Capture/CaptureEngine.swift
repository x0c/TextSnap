import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class CaptureEngine {
    enum CaptureSource: String, Sendable {
        case hotkey
        case menuBarLeftClick
        case menuBarMenu
        case settingsButton
        case appIntent
    }

    enum CapturePhase: String, Sendable {
        case idle
        case checkingPermission
        case selecting
        case recognizing
    }

    enum CaptureOutcome: Equatable, Sendable {
        case copied(String)
        case cancelled
        case empty
        case permissionDenied
        case failed
        case droppedInFlight
    }

    static let shared = CaptureEngine()

    var lastText: String = ""
    var isCapturing = false

    private var phase: CapturePhase = .idle
    private var activeCaptureID = 0
    private var activeCaptureStarted: DispatchTime?
    private var activeSelectorTask: Task<ScreenCapture.CaptureResult, Error>?
    private var nextCaptureID = 0
    private var isShowingAlert = false
    private var lifecycleObservers: [NSObjectProtocol] = []

    private init() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let cancelNotifications: [Notification.Name] = [
            NSWorkspace.willSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
        ]
        for name in cancelNotifications {
            let token = workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.cancelActiveSelectorIfNeeded(reason: name.rawValue)
                }
            }
            lifecycleObservers.append(token)
        }
    }

    @discardableResult
    func captureNow(source: CaptureSource = .hotkey) async -> CaptureOutcome {
        // Dismiss any leftover modal alert so a fresh shortcut trigger never stalls on it.
        if isShowingAlert {
            TextSnapLog.capture.notice("dismissing stale alert for new capture source=\(source.rawValue)")
            NSApp.abortModal()
        }

        // Re-entrant triggers while a run is in flight are dropped, never queued.
        if phase != .idle {
            let elapsedMs = activeCaptureStarted.map { TextSnapLog.milliseconds(since: $0) } ?? 0
            TextSnapLog.capture.notice(
                "trigger dropped source=\(source.rawValue) blockingId=#\(activeCaptureID) phase=\(phase.rawValue) inFlightMs=\(elapsedMs)"
            )
            return .droppedInFlight
        }

        nextCaptureID += 1
        let captureID = nextCaptureID
        let captureStarted = DispatchTime.now()
        activeCaptureID = captureID
        activeCaptureStarted = captureStarted
        phase = .checkingPermission
        isCapturing = true

        func releaseInFlight() {
            activeSelectorTask = nil
            activeCaptureStarted = nil
            phase = .idle
            isCapturing = false
        }

        defer {
            if phase != .idle || isCapturing {
                releaseInFlight()
            }
        }

        TextSnapLog.capture.notice("capture requested id=#\(captureID) source=\(source.rawValue)")

        // Isolated E2E hook: bypass TCC & interactive selector with a deterministic fixture image,
        // still exercising the real Vision OCR pipeline without touching the user's clipboard.
        if E2ERuntime.isEnabled, let fixtureURL = E2ERuntime.captureImageURL {
            return await runE2ECapture(
                captureID: captureID,
                captureStarted: captureStarted,
                fixtureURL: fixtureURL,
                releaseInFlight: releaseInFlight
            )
        }

        // TCC can answer slowly while the login session is settling; keep the
        // check off the main thread so the app stays responsive.
        let permissionStart = DispatchTime.now()
        let granted = await Task.detached(priority: .userInitiated) {
            ScreenCapturePermission.isGranted
        }.value
        TextSnapLog.capture.notice(
            "permission check id=#\(captureID) granted=\(granted) ms=\(TextSnapLog.milliseconds(since: permissionStart))"
        )
        if !granted {
            ScreenCapturePermission.request()
            let grantedAfterPrompt = await Task.detached(priority: .userInitiated) {
                ScreenCapturePermission.isGranted
            }.value
            TextSnapLog.capture.notice(
                "permission recheck after prompt id=#\(captureID) granted=\(grantedAfterPrompt)"
            )
            if !grantedAfterPrompt {
                TextSnapLog.capture.notice("capture blocked id=#\(captureID): screen recording not granted")
                releaseInFlight()
                showPermissionAlert()
                return .permissionDenied
            }
        }

        phase = .selecting
        let selectorTask = Task {
            try await ScreenCapture.captureRegion()
        }
        activeSelectorTask = selectorTask

        let captureResult: ScreenCapture.CaptureResult
        do {
            captureResult = try await selectorTask.value
        } catch let error as ScreenCapture.CaptureError {
            activeSelectorTask = nil
            switch error {
            case .cancelled:
                TextSnapLog.capture.notice(
                    "selector cancelled id=#\(captureID) after \(TextSnapLog.milliseconds(since: captureStarted))ms"
                )
                return .cancelled
            case .failed(let status, let stderr):
                TextSnapLog.capture.error(
                    "selector failed id=#\(captureID) status=\(status) ms=\(TextSnapLog.milliseconds(since: captureStarted)) stderr=\(stderr)"
                )
                releaseInFlight()
                showAlert(
                    title: String(localized: "capture.failed.title"),
                    body: String(localized: "capture.failed.body")
                )
                return .failed
            case .missingFile(let status):
                TextSnapLog.capture.error(
                    "selector missingFile id=#\(captureID) status=\(status) ms=\(TextSnapLog.milliseconds(since: captureStarted))"
                )
                releaseInFlight()
                showAlert(
                    title: String(localized: "capture.failed.title"),
                    body: String(localized: "capture.failed.body")
                )
                return .failed
            }
        } catch {
            activeSelectorTask = nil
            TextSnapLog.capture.error(
                "selector unexpected error id=#\(captureID) ms=\(TextSnapLog.milliseconds(since: captureStarted)) error=\(String(describing: error))"
            )
            releaseInFlight()
            showAlert(
                title: String(localized: "capture.failed.title"),
                body: String(localized: "capture.failed.body")
            )
            return .failed
        }
        activeSelectorTask = nil
        defer { try? FileManager.default.removeItem(at: captureResult.url) }

        TextSnapLog.capture.notice(
            "selector finished id=#\(captureID) ms=\(TextSnapLog.milliseconds(since: captureStarted)) image=\(captureResult.pixelWidth)x\(captureResult.pixelHeight) bytes=\(captureResult.fileBytes)"
        )

        phase = .recognizing
        let ocrStarted = DispatchTime.now()
        let result: TextRecognizer.RecognizeResult
        do {
            let imageURL = captureResult.url
            result = try await Task.detached(priority: .userInitiated) {
                try TextRecognizer.recognizeWithDiagnostics(in: imageURL)
            }.value
        } catch {
            TextSnapLog.capture.error(
                "ocr failed id=#\(captureID) after \(TextSnapLog.milliseconds(since: ocrStarted))ms: \(String(describing: error))"
            )
            releaseInFlight()
            showAlert(
                title: String(localized: "capture.failed.title"),
                body: String(localized: "capture.failed.body")
            )
            return .failed
        }

        let lineCount = result.text.isEmpty ? 0 : result.text.split(separator: "\n", omittingEmptySubsequences: false).count
        TextSnapLog.capture.notice(
            "ocr ok id=#\(captureID) ms=\(result.durationMs) device=\(result.deviceName) attempts=\(result.attemptCount) normalized=\(result.usedNormalizedFallback) chars=\(result.text.count) lines=\(lineCount)"
        )

        if result.text.isEmpty {
            TextSnapLog.capture.notice(
                "ocr empty id=#\(captureID) image=\(captureResult.pixelWidth)x\(captureResult.pixelHeight)"
            )
            releaseInFlight()
            showAlert(
                title: String(localized: "capture.empty.title"),
                body: String(localized: "capture.empty.body")
            )
            return .empty
        }

        lastText = result.text
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result.text, forType: .string)
        playConfirmSound()
        TextSnapLog.capture.notice(
            "copied to pasteboard id=#\(captureID) totalMs=\(TextSnapLog.milliseconds(since: captureStarted)) chars=\(result.text.count)"
        )
        return .copied(result.text)
    }

    func copyLastAgain() {
        guard !lastText.isEmpty else { return }
        if !E2ERuntime.isEnabled {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(lastText, forType: .string)
            playConfirmSound()
        } else {
            let e2ePasteboard = NSPasteboard.withUniqueName()
            e2ePasteboard.clearContents()
            e2ePasteboard.setString(lastText, forType: .string)
            e2ePasteboard.releaseGlobally()
        }
        TextSnapLog.capture.notice("copied last result again chars=\(lastText.count)")
    }

    private func runE2ECapture(
        captureID: Int,
        captureStarted: DispatchTime,
        fixtureURL: URL,
        releaseInFlight: () -> Void
    ) async -> CaptureOutcome {
        let meta = ScreenCapture.inspectImage(at: fixtureURL)
        TextSnapLog.capture.notice(
            "e2e fixture id=#\(captureID) image=\(meta.width)x\(meta.height) bytes=\(meta.bytes)"
        )
        phase = .recognizing
        let ocrStarted = DispatchTime.now()
        let result: TextRecognizer.RecognizeResult
        do {
            result = try await Task.detached(priority: .userInitiated) {
                try TextRecognizer.recognizeWithDiagnostics(in: fixtureURL)
            }.value
        } catch {
            TextSnapLog.capture.error(
                "ocr failed id=#\(captureID) after \(TextSnapLog.milliseconds(since: ocrStarted))ms: \(String(describing: error))"
            )
            releaseInFlight()
            return .failed
        }
        let lineCount = result.text.isEmpty ? 0 : result.text.split(separator: "\n", omittingEmptySubsequences: false).count
        TextSnapLog.capture.notice(
            "ocr ok id=#\(captureID) ms=\(result.durationMs) device=\(result.deviceName) attempts=\(result.attemptCount) normalized=\(result.usedNormalizedFallback) chars=\(result.text.count) lines=\(lineCount)"
        )
        if result.text.isEmpty {
            TextSnapLog.capture.notice("ocr empty id=#\(captureID) image=\(meta.width)x\(meta.height)")
            releaseInFlight()
            return .empty
        }
        lastText = result.text
        let e2ePasteboard = NSPasteboard.withUniqueName()
        e2ePasteboard.clearContents()
        e2ePasteboard.setString(result.text, forType: .string)
        e2ePasteboard.releaseGlobally()
        TextSnapLog.capture.notice(
            "copied to pasteboard id=#\(captureID) totalMs=\(TextSnapLog.milliseconds(since: captureStarted)) chars=\(result.text.count) e2e=true"
        )
        return .copied(result.text)
    }

    private func cancelActiveSelectorIfNeeded(reason: String) {
        guard phase == .selecting, let activeSelectorTask else { return }
        TextSnapLog.capture.notice("selector cancelled by system id=#\(activeCaptureID) reason=\(reason)")
        activeSelectorTask.cancel()
    }

    private func playConfirmSound() {
        if let sound = NSSound(named: "Glass") {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    private func showPermissionAlert() {
        isShowingAlert = true
        defer { isShowingAlert = false }
        let alert = NSAlert()
        alert.messageText = String(localized: "permission.denied.title")
        alert.informativeText = String(localized: "permission.denied.body")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "permission.openSettings"))
        alert.addButton(withTitle: String(localized: "alert.ok"))
        alert.window.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            ScreenCapturePermission.openSystemSettings()
        }
    }

    private func showAlert(title: String, body: String) {
        isShowingAlert = true
        defer { isShowingAlert = false }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "alert.ok"))
        alert.window.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
