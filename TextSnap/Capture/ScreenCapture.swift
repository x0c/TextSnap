import AppKit
import Foundation

/// System region selector. Esc cancels (non-zero exit, no file).
enum ScreenCapture {
    enum CaptureError: Error {
        case cancelled
        case failed(Int32)
        case missingFile
    }

    /// Runs `/usr/sbin/screencapture -i -s` and returns the PNG file URL.
    static func captureRegion() async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("TextSnap", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent("capture-\(Int(Date().timeIntervalSince1970 * 1000)).png")
            try? FileManager.default.removeItem(at: file)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-i", "-s", "-x", "-t", "png", file.path]
            try process.run()
            process.waitUntilExit()
            let status = process.terminationStatus
            if status != 0 {
                try? FileManager.default.removeItem(at: file)
                throw CaptureError.cancelled
            }
            guard FileManager.default.fileExists(atPath: file.path) else {
                throw CaptureError.missingFile
            }
            return file
        }.value
    }
}
