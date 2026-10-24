import CoreGraphics
import CoreText
import Foundation
import Vision

/// On-device text recognition. No network.
enum TextRecognizer {
    enum RecognizeError: Error {
        case visionFailed(Error)
    }

    /// Language priority: Chinese varieties first, then English, then Japanese.
    /// Resolved once because `supportedRecognitionLanguages()` initializes the
    /// recognition engine; calling it on every capture is unnecessarily slow.
    private nonisolated static let preferredLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP"]

    private nonisolated static let recognitionLanguages: [String] = {
        let request = VNRecognizeTextRequest()
        request.revision = 3
        guard let supported = try? request.supportedRecognitionLanguages() else {
            return preferredLanguages
        }
        let filtered = preferredLanguages.filter(supported.contains)
        return filtered.isEmpty ? preferredLanguages : filtered
    }()

    nonisolated static func recognizeText(in imageURL: URL) throws -> String {
        try recognize(in: VNImageRequestHandler(url: imageURL, options: [:]))
    }

    nonisolated static func recognizeText(in image: CGImage) throws -> String {
        try recognize(in: VNImageRequestHandler(cgImage: image, options: [:]))
    }

    /// Loads Vision's text recognizer once, off the main thread, so the first
    /// real capture after boot does not pay the model cold-start cost.
    ///
    /// The probe image must contain text: a blank image is short-circuited by
    /// Vision and does not load the recognition model (measured).
    nonisolated static func warmUp() {
        guard let image = warmUpImage() else {
            TextSnapLog.capture.error("ocr warmup skipped: probe image unavailable")
            return
        }
        let started = DispatchTime.now()
        let text = (try? recognizeText(in: image)) ?? ""
        TextSnapLog.capture.notice(
            "ocr warmup \(TextSnapLog.milliseconds(since: started), privacy: .public)ms chars=\(text.count, privacy: .public)"
        )
    }

    private nonisolated static func recognize(in handler: VNImageRequestHandler) throws -> String {
        let request = VNRecognizeTextRequest()
        request.revision = 3
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        request.recognitionLanguages = recognitionLanguages
        do {
            try handler.perform([request])
        } catch {
            throw RecognizeError.visionFailed(error)
        }
        guard let observations = request.results else {
            return ""
        }
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func warmUpImage() -> CGImage? {
        let width = 320
        let height = 64
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

        let font = CTFontCreateWithName("Helvetica" as CFString, 28, nil)
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(gray: 0, alpha: 1),
        ]
        guard let attributed = CFAttributedStringCreate(
            nil,
            "TextSnap OCR warmup 12345" as CFString,
            attributes as CFDictionary
        ) else { return nil }
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = CGPoint(x: 6, y: 18)
        CTLineDraw(line, context)
        return context.makeImage()
    }
}
