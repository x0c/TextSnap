import Foundation
import os

/// Persistent, privacy-safe diagnostics for launch, hotkey and capture timing.
///
/// Inspect after a boot with:
/// `log show --last boot --predicate 'subsystem == "top.caozc.TextSnap"' --style compact`
///
/// Never log recognized text or clipboard contents.
enum TextSnapLog {
    nonisolated private static let subsystem = "top.caozc.TextSnap"

    nonisolated static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    nonisolated static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    nonisolated static let capture = Logger(subsystem: subsystem, category: "capture")

    /// Milliseconds elapsed since a monotonic start mark.
    nonisolated static func milliseconds(since start: DispatchTime) -> Int {
        Int((DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
    }
}
