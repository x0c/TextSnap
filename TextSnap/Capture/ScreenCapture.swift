import CoreGraphics
import Foundation
import ImageIO

nonisolated enum ScreenCapture {
    struct CaptureResult: Sendable {
        let url: URL
        let pixelWidth: Int
        let pixelHeight: Int
        let fileBytes: Int
    }

    enum CaptureError: Error, Equatable, CustomStringConvertible {
        case cancelled
        case failed(status: Int32, stderr: String)
        case missingFile(status: Int32)

        var description: String {
            switch self {
            case .cancelled:
                return "cancelled"
            case .failed(let status, let stderr):
                if stderr.isEmpty {
                    return "failed(status=\(status))"
                }
                return "failed(status=\(status), stderr=\(stderr))"
            case .missingFile(let status):
                return "missingFile(status=\(status))"
            }
        }
    }

    private static var tempDirectoryURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("TextSnap", isDirectory: true)
    }

    /// Removes orphaned capture PNGs left behind by a crash or forced kill.
    static func cleanupOrphanedTempFiles(maxAge: TimeInterval = 3600) {
        let fm = FileManager.default
        let dir = tempDirectoryURL
        guard let entries = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        let cutoff = Date().addingTimeInterval(-maxAge)
        var removed = 0
        for url in entries where url.lastPathComponent.hasPrefix("TextSnap-") && url.pathExtension == "png" {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if modified < cutoff {
                try? fm.removeItem(at: url)
                removed += 1
            }
        }
        if removed > 0 {
            TextSnapLog.capture.notice("cleaned up \(removed) orphaned temp capture(s)")
        }
    }

    static func inspectImage(at url: URL) -> (width: Int, height: Int, bytes: Int) {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return (0, 0, bytes)
        }
        let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        return (width, height, bytes)
    }

    /// Classifies `screencapture` exit state so silent Esc cancellations remain silent
    /// while non-empty `stderr` or abnormal exit codes surface as failures.
    static func classifyExit(status: Int32, fileExists: Bool, stderr: String, wasCancelled: Bool) -> CaptureError? {
        if wasCancelled {
            return .cancelled
        }
        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if fileExists {
            if status == 0 {
                return nil
            }
            return .failed(status: status, stderr: trimmed)
        }
        if !trimmed.isEmpty {
            return .failed(status: status, stderr: trimmed)
        }
        if status == 0 || status == 1 {
            return .cancelled
        }
        return .failed(status: status, stderr: trimmed)
    }

    /// Runs `/usr/sbin/screencapture -i -s` without blocking Swift's cooperative pool.
    static func captureRegion() async throws -> CaptureResult {
        let dir = tempDirectoryURL
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("TextSnap-\(UUID().uuidString).png")
        try? FileManager.default.removeItem(at: file)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-s", "-x", "-t", "png", file.path]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        let state = ProcessState(process: process, stderrHandle: stderrPipe.fileHandleForReading)

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty {
                state.appendStderr(chunk)
            }
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.setContinuation(continuation)
                process.terminationHandler = { terminated in
                    state.finish(status: terminated.terminationStatus, fileURL: file)
                }
                do {
                    try process.run()
                    try? stderrPipe.fileHandleForWriting.close()
                    if state.isCancelled {
                        terminatedIfNeeded(process)
                    }
                } catch {
                    try? stderrPipe.fileHandleForWriting.close()
                    state.failLaunch(error, fileURL: file)
                }
            }
        } onCancel: {
            state.markCancelled()
            terminatedIfNeeded(process)
        }
    }

    private static func terminatedIfNeeded(_ process: Process) {
        if process.isRunning {
            process.terminate()
        }
    }

    private final class ProcessState: @unchecked Sendable {
        private let lock = NSLock()
        private let process: Process
        private let stderrHandle: FileHandle
        private var stderrBuffer = Data()
        private var continuation: CheckedContinuation<CaptureResult, Error>?
        private var cancelled = false
        private var resolved = false

        init(process: Process, stderrHandle: FileHandle) {
            self.process = process
            self.stderrHandle = stderrHandle
        }

        var isCancelled: Bool {
            lock.withLock { cancelled }
        }

        func setContinuation(_ continuation: CheckedContinuation<CaptureResult, Error>) {
            lock.withLock {
                self.continuation = continuation
            }
        }

        func appendStderr(_ data: Data) {
            lock.withLock {
                stderrBuffer.append(data)
            }
        }

        func markCancelled() {
            lock.withLock {
                cancelled = true
            }
        }

        func failLaunch(_ error: Error, fileURL: URL) {
            stderrHandle.readabilityHandler = nil
            try? FileManager.default.removeItem(at: fileURL)
            let cont = takeContinuationOnce()
            cont?.resume(throwing: CaptureError.failed(status: -1, stderr: error.localizedDescription))
        }

        func finish(status: Int32, fileURL: URL) {
            stderrHandle.readabilityHandler = nil
            let tail = stderrHandle.readDataToEndOfFile()
            let (stderrString, wasCancelled) = lock.withLock { () -> (String, Bool) in
                if !tail.isEmpty {
                    stderrBuffer.append(tail)
                }
                let text = String(data: stderrBuffer, encoding: .utf8) ?? ""
                return (text, cancelled)
            }

            let fm = FileManager.default
            let exists = fm.fileExists(atPath: fileURL.path)
            if let error = ScreenCapture.classifyExit(
                status: status,
                fileExists: exists,
                stderr: stderrString,
                wasCancelled: wasCancelled
            ) {
                try? fm.removeItem(at: fileURL)
                takeContinuationOnce()?.resume(throwing: error)
                return
            }

            let meta = ScreenCapture.inspectImage(at: fileURL)
            takeContinuationOnce()?.resume(
                returning: CaptureResult(
                    url: fileURL,
                    pixelWidth: meta.width,
                    pixelHeight: meta.height,
                    fileBytes: meta.bytes
                )
            )
        }

        private func takeContinuationOnce() -> CheckedContinuation<CaptureResult, Error>? {
            lock.withLock {
                guard !resolved else { return nil }
                resolved = true
                let cont = continuation
                continuation = nil
                return cont
            }
        }
    }
}
