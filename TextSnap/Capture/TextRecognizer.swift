import Foundation
import Vision

/// On-device text recognition. No network.
enum TextRecognizer {
    enum RecognizeError: Error {
        case unreadableImage
        case visionFailed(Error)
    }

    /// Returns trimmed recognized text, or "" when nothing readable is found.
    ///
    /// Language order matters: Vision tries `recognitionLanguages` in order,
    /// so English-first silently drops Chinese-only regions ("no text found")
    /// and mangles mixed regions. Chinese-first + automatic detection keeps
    /// EN / ZH-Hans / ZH-Hant / mixed all working (verified on macOS 26/27).
    static func recognizeText(in imageURL: URL) throws -> String {
        let handler = VNImageRequestHandler(url: imageURL, options: [:])
        let request = VNRecognizeTextRequest()
        request.revision = 3
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        // Priority order: Chinese varieties first, then English, then Japanese.
        // Filtered against what the current revision actually supports so a
        // future OS never gets asked for an unsupported language.
        let preferred = ["zh-Hans", "zh-Hant", "en-US", "ja-JP"]
        if let supported = try? request.supportedRecognitionLanguages() {
            let filtered = preferred.filter { supported.contains($0) }
            request.recognitionLanguages = filtered.isEmpty ? preferred : filtered
        } else {
            request.recognitionLanguages = preferred
        }
        do {
            try handler.perform([request])
        } catch {
            throw RecognizeError.visionFailed(error)
        }
        guard let observations = request.results as? [VNRecognizedTextObservation] else {
            return ""
        }
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
