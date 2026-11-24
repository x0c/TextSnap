import CoreGraphics
import CoreML
import CoreText
import Foundation
import ImageIO
import os
import Vision

nonisolated enum TextRecognizer {
    enum RecognizeError: Error, CustomStringConvertible {
        case visionFailed([String])
        case imageUnreadable
        case workerFailed(String)

        var description: String {
            switch self {
            case .visionFailed(let attempts):
                return "visionFailed(\(attempts.joined(separator: "; ")))"
            case .imageUnreadable:
                return "imageUnreadable"
            case .workerFailed(let detail):
                return "workerFailed(\(detail))"
            }
        }
    }

    struct RecognizeResult: Sendable, Codable {
        let text: String
        let deviceName: String
        let durationMs: Int
        let attemptCount: Int
        let usedNormalizedFallback: Bool
    }

    /// Language priority: Chinese varieties first, then English, then Japanese.
    /// Resolved once because `supportedRecognitionLanguages()` initializes the
    /// recognition engine; calling it on every capture is unnecessarily slow.
    private static let preferredLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP"]

    private static let recognitionLanguages: [String] = {
        let request = VNRecognizeTextRequest()
        request.revision = 3
        guard let supported = try? request.supportedRecognitionLanguages() else {
            return preferredLanguages
        }
        let filtered = preferredLanguages.filter(supported.contains)
        return filtered.isEmpty ? preferredLanguages : filtered
    }()

    /// Explicit `.gpu` -> `.cpu` compute-device order, with system default only
    /// when neither is reported.
    private static let candidateDevices: [(name: String, device: MLComputeDevice?)] = {
        let request = VNRecognizeTextRequest()
        request.revision = 3
        let supported = (try? request.supportedComputeStageDevices[.main]) ?? []
        var candidates: [(name: String, device: MLComputeDevice?)] = []
        if let gpu = supported.first(where: { if case .gpu = $0 { return true }; return false }) {
            candidates.append(("gpu", gpu))
        }
        if let cpu = supported.first(where: { if case .cpu = $0 { return true }; return false }) {
            candidates.append(("cpu", cpu))
        }
        if candidates.isEmpty {
            candidates.append(("default", nil))
        }
        return candidates
    }()

    /// Tracks warm-up / device fallback / poisoning state safely across concurrent OCR tasks.
    private static let hasCompletedRecognition = OSAllocatedUnfairLock(initialState: false)
    private static let gpuDemoted = OSAllocatedUnfairLock(initialState: false)
    private static let inProcessPoisoned = OSAllocatedUnfairLock(initialState: false)

    private static var orderedCandidates: [(name: String, device: MLComputeDevice?)] {
        guard gpuDemoted.withLock({ $0 }) else { return candidateDevices }
        let nonGPU = candidateDevices.filter { $0.name != "gpu" }
        return nonGPU.isEmpty ? candidateDevices : nonGPU
    }

    private static var isCLIWorkerProcess: Bool {
        CommandLine.arguments.contains("--ocr-once")
    }

    private static var canSpawnCLIWorker: Bool {
        !isCLIWorkerProcess && Bundle.main.executableURL?.lastPathComponent == "TextSnap"
    }

    static func isE5RTError(_ error: Error) -> Bool {
        let text = String(describing: error)
        return text.contains("e5rtError") || text.contains("CRImageReaderError")
    }

    static func recognizeText(in imageURL: URL) throws -> String {
        try recognizeWithDiagnostics(in: imageURL).text
    }

    static func recognizeText(in image: CGImage) throws -> String {
        try recognizeWithDiagnostics(in: image).text
    }

    static func recognizeWithDiagnostics(in imageURL: URL) throws -> RecognizeResult {
        if canSpawnCLIWorker && inProcessPoisoned.withLock({ $0 }) {
            return try runIsolatedWorker(imageURL: imageURL)
        }
        do {
            let result = try performInProcessRecognition(imageURL: imageURL)
            hasCompletedRecognition.withLock { $0 = true }
            return result
        } catch {
            if canSpawnCLIWorker && isE5RTError(error) {
                inProcessPoisoned.withLock { $0 = true }
                TextSnapLog.capture.warning("ocr in-process E5RT poisoned; switching to isolated worker")
                return try runIsolatedWorker(imageURL: imageURL)
            }
            throw error
        }
    }

    static func recognizeWithDiagnostics(in image: CGImage) throws -> RecognizeResult {
        let result = try performInProcessRecognition(cgImage: image)
        hasCompletedRecognition.withLock { $0 = true }
        return result
    }

    /// Headless worker entry invoked via `TextSnap --ocr-once <imagePath>`.
    static func runCLIWorker(imagePath: String) -> Int32 {
        let url = URL(fileURLWithPath: imagePath)
        do {
            let result = try performInProcessRecognition(imageURL: url)
            let data = try JSONEncoder().encode(result)
            FileHandle.standardOutput.write(data)
            return 0
        } catch {
            let message = "ocr worker error: \(String(describing: error))\n"
            if let data = message.data(using: .utf8) {
                FileHandle.standardError.write(data)
            }
            return 1
        }
    }

    /// Loads Vision's text recognizer once, off the main thread, so the first
    /// real capture after boot does not pay the model cold-start cost.
    ///
    /// Uses a `512x256` bilingual image: measured on macOS 27.3 that a small
    /// `320x64` strip triggers a 60s+ ANE compile and poisons E5RT (`e5rtError 13`),
    /// whereas `512x256` completes cleanly without poisoning subsequent calls.
    static func warmUp() {
        let alreadyWarmed = hasCompletedRecognition.withLock { $0 }
        if alreadyWarmed {
            TextSnapLog.capture.notice("ocr warmup skipped: already warmed")
            return
        }
        guard let image = warmUpImage() else {
            TextSnapLog.capture.error("ocr warmup skipped: probe image unavailable")
            return
        }
        do {
            let result = try recognizeWithDiagnostics(in: image)
            TextSnapLog.capture.notice(
                "ocr warmup \(result.durationMs)ms device=\(result.deviceName) chars=\(result.text.count)"
            )
        } catch {
            if isE5RTError(error) {
                inProcessPoisoned.withLock { $0 = true }
            }
            TextSnapLog.capture.error("ocr warmup failed: \(String(describing: error))")
        }
    }

    /// Centers tiny screenshots (< 256x160) on a clean sRGB canvas so narrow/small
    /// user crops never hit macOS 27's small-height E5RT poisoning path.
    static func padForVisionIfNeeded(_ image: CGImage) -> CGImage {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, (width < 256 || height < 160) else {
            return image
        }
        let targetWidth = max(width + 64, 320)
        let targetHeight = max(height + 64, 192)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: targetWidth,
                height: targetHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            return image
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        let x = (targetWidth - width) / 2
        let y = (targetHeight - height) / 2
        context.draw(image, in: CGRect(x: x, y: y, width: width, height: height))
        return context.makeImage() ?? image
    }

    private static func performInProcessRecognition(imageURL: URL) throws -> RecognizeResult {
        let meta = ScreenCapture.inspectImage(at: imageURL)
        if meta.width > 0 && meta.height > 0 && (meta.width < 256 || meta.height < 160),
           let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
           let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return try performInProcessRecognition(cgImage: decoded)
        }

        let overallStart = DispatchTime.now()
        var errors: [String] = []
        var attempts = 0

        for candidate in orderedCandidates {
            attempts += 1
            let attemptStart = DispatchTime.now()
            do {
                let handler = VNImageRequestHandler(url: imageURL, options: [:])
                let text = try performRequest(on: handler, device: candidate.device)
                return RecognizeResult(
                    text: text,
                    deviceName: candidate.name,
                    durationMs: TextSnapLog.milliseconds(since: overallStart),
                    attemptCount: attempts,
                    usedNormalizedFallback: false
                )
            } catch {
                if candidate.name == "gpu", isE5RTError(error) {
                    gpuDemoted.withLock { $0 = true }
                }
                let ms = TextSnapLog.milliseconds(since: attemptStart)
                let message = "\(candidate.name)(\(ms)ms): \(error)"
                errors.append(message)
                TextSnapLog.capture.warning("ocr attempt failed \(message)")
            }
        }

        // Fallback: decode and normalize wide-gamut/HDR/custom ICC screenshots into 8-bit sRGB + pad.
        if let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
           let rawImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
           let normalized = normalizeToSRGB(padForVisionIfNeeded(rawImage)) {
            attempts += 1
            let fallbackDevice = candidateDevices.last ?? ("default", nil)
            let attemptStart = DispatchTime.now()
            do {
                let handler = VNImageRequestHandler(cgImage: normalized, options: [:])
                let text = try performRequest(on: handler, device: fallbackDevice.device)
                return RecognizeResult(
                    text: text,
                    deviceName: "\(fallbackDevice.name)+srgb",
                    durationMs: TextSnapLog.milliseconds(since: overallStart),
                    attemptCount: attempts,
                    usedNormalizedFallback: true
                )
            } catch {
                let ms = TextSnapLog.milliseconds(since: attemptStart)
                let message = "\(fallbackDevice.name)+srgb(\(ms)ms): \(error)"
                errors.append(message)
                TextSnapLog.capture.warning("ocr normalized fallback failed \(message)")
            }
        }

        throw RecognizeError.visionFailed(errors)
    }

    private static func performInProcessRecognition(cgImage: CGImage) throws -> RecognizeResult {
        let prepared = padForVisionIfNeeded(cgImage)
        let overallStart = DispatchTime.now()
        var errors: [String] = []
        var attempts = 0

        for candidate in orderedCandidates {
            attempts += 1
            let attemptStart = DispatchTime.now()
            do {
                let handler = VNImageRequestHandler(cgImage: prepared, options: [:])
                let text = try performRequest(on: handler, device: candidate.device)
                return RecognizeResult(
                    text: text,
                    deviceName: candidate.name,
                    durationMs: TextSnapLog.milliseconds(since: overallStart),
                    attemptCount: attempts,
                    usedNormalizedFallback: false
                )
            } catch {
                if candidate.name == "gpu", isE5RTError(error) {
                    gpuDemoted.withLock { $0 = true }
                }
                let ms = TextSnapLog.milliseconds(since: attemptStart)
                let message = "\(candidate.name)(\(ms)ms): \(error)"
                errors.append(message)
                TextSnapLog.capture.warning("ocr attempt failed \(message)")
            }
        }

        if let normalized = normalizeToSRGB(prepared) {
            attempts += 1
            let fallbackDevice = candidateDevices.last ?? ("default", nil)
            let attemptStart = DispatchTime.now()
            do {
                let handler = VNImageRequestHandler(cgImage: normalized, options: [:])
                let text = try performRequest(on: handler, device: fallbackDevice.device)
                return RecognizeResult(
                    text: text,
                    deviceName: "\(fallbackDevice.name)+srgb",
                    durationMs: TextSnapLog.milliseconds(since: overallStart),
                    attemptCount: attempts,
                    usedNormalizedFallback: true
                )
            } catch {
                let ms = TextSnapLog.milliseconds(since: attemptStart)
                let message = "\(fallbackDevice.name)+srgb(\(ms)ms): \(error)"
                errors.append(message)
                TextSnapLog.capture.warning("ocr normalized fallback failed \(message)")
            }
        }

        throw RecognizeError.visionFailed(errors)
    }

    private static func runIsolatedWorker(imageURL: URL) throws -> RecognizeResult {
        guard let executableURL = Bundle.main.executableURL else {
            throw RecognizeError.workerFailed("executableURL unavailable")
        }
        let started = DispatchTime.now()
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--ocr-once", imageURL.path]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let elapsedMs = TextSnapLog.milliseconds(since: started)
        guard process.terminationStatus == 0 else {
            let errText = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw RecognizeError.workerFailed("status=\(process.terminationStatus) \(errText)")
        }

        do {
            let decoded = try JSONDecoder().decode(RecognizeResult.self, from: stdoutData)
            TextSnapLog.capture.notice(
                "ocr worker ok totalMs=\(elapsedMs) innerMs=\(decoded.durationMs) device=\(decoded.deviceName) chars=\(decoded.text.count)"
            )
            return RecognizeResult(
                text: decoded.text,
                deviceName: "worker/\(decoded.deviceName)",
                durationMs: elapsedMs,
                attemptCount: decoded.attemptCount,
                usedNormalizedFallback: decoded.usedNormalizedFallback
            )
        } catch {
            throw RecognizeError.workerFailed("decode failed: \(error.localizedDescription)")
        }
    }

    private static func performRequest(on handler: VNImageRequestHandler, device: MLComputeDevice?) throws -> String {
        let request = VNRecognizeTextRequest()
        request.revision = 3
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        request.recognitionLanguages = recognitionLanguages
        if let device {
            request.setComputeDevice(device, for: .main)
        }
        try handler.perform([request])
        guard let observations = request.results else {
            return ""
        }
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeToSRGB(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func warmUpImage() -> CGImage? {
        let width = 512
        let height = 256
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, 28, nil)
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(gray: 0, alpha: 1),
        ]
        guard let attributed = CFAttributedStringCreate(
            nil,
            "TextSnap 中文测试 12345" as CFString,
            attributes as CFDictionary
        ) else { return nil }
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = CGPoint(x: 24, y: Double(height) / 2 - 12)
        CTLineDraw(line, context)
        return context.makeImage()
    }
}
