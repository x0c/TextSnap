import Foundation
import Vision

/// On-device text recognition. No network.
enum TextRecognizer {
    enum RecognizeError: Error {
        case unreadableImage
        case visionFailed(Error)
    }

    /// Returns trimmed recognized text, or "" when nothing readable is found.
    static func recognizeText(in imageURL: URL) throws -> String {
        let handler = VNImageRequestHandler(url: imageURL, options: [:])
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US", "zh-Hans", "zh-Hant", "ja-JP"]
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
