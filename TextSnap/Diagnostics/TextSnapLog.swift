import Foundation
import os

/// Dual-sink, privacy-safe diagnostics for launch, hotkey, capture, and settings.
///
/// Writes to Unified Logging (`subsystem == "top.caozc.TextSnap"`) and a rotating
/// local log file (`~/.config/textsnap/logs/textsnap.log`, `$XDG_CONFIG_HOME` aware).
/// Never log recognized text, image pixels, or clipboard contents.
nonisolated enum TextSnapLog {
    private static let subsystem = "top.caozc.TextSnap"

    static let lifecycle = DiagnosticLogger(
        category: "lifecycle",
        osLogger: Logger(subsystem: subsystem, category: "lifecycle")
    )
    static let hotkey = DiagnosticLogger(
        category: "hotkey",
        osLogger: Logger(subsystem: subsystem, category: "hotkey")
    )
    static let capture = DiagnosticLogger(
        category: "capture",
        osLogger: Logger(subsystem: subsystem, category: "capture")
    )
    static let settings = DiagnosticLogger(
        category: "settings",
        osLogger: Logger(subsystem: subsystem, category: "settings")
    )

    static var logDirectoryURL: URL {
        TextSnapFileLogger.shared.directoryURL
    }

    static var activeLogFileURL: URL {
        TextSnapFileLogger.shared.activeFileURL
    }

    static func flush() {
        TextSnapFileLogger.shared.flush()
    }

    /// Milliseconds elapsed since a monotonic start mark.
    static func milliseconds(since start: DispatchTime) -> Int {
        Int((DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
    }
}

nonisolated struct DiagnosticLogger: Sendable {
    let category: String
    let osLogger: Logger

    func notice(_ message: String) {
        osLogger.notice("\(message, privacy: .public)")
        TextSnapFileLogger.shared.append(level: "NOTICE", category: category, message: message)
    }

    func warning(_ message: String) {
        osLogger.warning("\(message, privacy: .public)")
        TextSnapFileLogger.shared.append(level: "WARN", category: category, message: message)
    }

    func error(_ message: String) {
        osLogger.error("\(message, privacy: .public)")
        TextSnapFileLogger.shared.append(level: "ERROR", category: category, message: message)
    }
}

/// Thread-safe rotating file logger storing privacy-safe diagnostics under
/// `~/.config/textsnap/logs/textsnap.log` with `0700` directory and `0600` file permissions.
nonisolated final class TextSnapFileLogger: @unchecked Sendable {
    static let defaultMaxBytes = 2 * 1024 * 1024
    static let defaultMaxBackups = 3

    static let shared = TextSnapFileLogger(
        directory: TextSnapSettings.directoryURL().appendingPathComponent("logs", isDirectory: true)
    )

    let directoryURL: URL
    let activeFileURL: URL
    private let maxBytes: Int
    private let maxBackups: Int
    private let queue = DispatchQueue(label: "top.caozc.TextSnap.filelog", qos: .utility)
    private let pid = ProcessInfo.processInfo.processIdentifier

    // Accessed exclusively on `queue`.
    private var formatter: ISO8601DateFormatter?

    init(
        directory: URL,
        maxBytes: Int = TextSnapFileLogger.defaultMaxBytes,
        maxBackups: Int = TextSnapFileLogger.defaultMaxBackups
    ) {
        self.directoryURL = directory
        self.activeFileURL = directory.appendingPathComponent("textsnap.log")
        self.maxBytes = max(1, maxBytes)
        self.maxBackups = max(1, maxBackups)
    }

    func append(level: String, category: String, message: String) {
        let singleLine = message
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        let now = Date()
        queue.async { [self] in
            writeLine(date: now, level: level, category: category, message: singleLine)
        }
    }

    func flush() {
        queue.sync {}
    }

    private func writeLine(date: Date, level: String, category: String, message: String) {
        let fm = FileManager.default
        let configDir = directoryURL.deletingLastPathComponent()
        try? fm.createDirectory(at: configDir, withIntermediateDirectories: true)
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: configDir.path)
        try? fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)

        let timestamp = isoTimestamp(for: date)
        let line = "\(timestamp) [\(level)] [\(category)] [pid=\(pid)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        rotateIfNeeded(incomingBytes: data.count, fileManager: fm)

        if !fm.fileExists(atPath: activeFileURL.path) {
            fm.createFile(
                atPath: activeFileURL.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            )
        }

        if let handle = try? FileHandle(forWritingTo: activeFileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: activeFileURL.path)
        }
    }

    private func rotateIfNeeded(incomingBytes: Int, fileManager fm: FileManager) {
        guard let attrs = try? fm.attributesOfItem(atPath: activeFileURL.path),
              let size = (attrs[.size] as? NSNumber)?.intValue,
              size + incomingBytes > maxBytes
        else {
            return
        }

        let oldest = backupURL(index: maxBackups)
        try? fm.removeItem(at: oldest)

        if maxBackups > 1 {
            for index in stride(from: maxBackups - 1, through: 1, by: -1) {
                let source = backupURL(index: index)
                let destination = backupURL(index: index + 1)
                if fm.fileExists(atPath: source.path) {
                    try? fm.removeItem(at: destination)
                    try? fm.moveItem(at: source, to: destination)
                }
            }
        }

        let firstBackup = backupURL(index: 1)
        try? fm.removeItem(at: firstBackup)
        try? fm.moveItem(at: activeFileURL, to: firstBackup)
        if fm.fileExists(atPath: firstBackup.path) {
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: firstBackup.path)
        }
    }

    private func backupURL(index: Int) -> URL {
        directoryURL.appendingPathComponent("textsnap.\(index).log")
    }

    private func isoTimestamp(for date: Date) -> String {
        if formatter == nil {
            let iso = ISO8601DateFormatter()
            iso.timeZone = TimeZone.current
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            formatter = iso
        }
        return formatter?.string(from: date) ?? ""
    }
}
