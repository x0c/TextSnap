import AppKit
import Foundation

/// Process-launch hooks exclusively for background `macos-e2e` runs.
/// Inactive unless `--e2e-testing` is present on the command line.
nonisolated enum E2ERuntime {
    static let isEnabled: Bool = arguments().contains("--e2e-testing")

    static var rootURL: URL? {
        guard isEnabled, let path = value(for: "--e2e-root") ?? value(for: "--e2e-data-root") else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    static var captureImageURL: URL? {
        guard isEnabled, let path = value(for: "--e2e-capture-image") else {
            return nil
        }
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    static var windowSize: NSSize? {
        guard isEnabled, let raw = value(for: "--e2e-window-size") else {
            return nil
        }
        let parts = raw.split(separator: "x", maxSplits: 1)
        guard parts.count == 2,
              let width = Double(parts[0]),
              let height = Double(parts[1]),
              width > 0,
              height > 0
        else {
            return nil
        }
        return NSSize(width: width, height: height)
    }

    private static func arguments() -> [String] {
        CommandLine.arguments
    }

    private static func value(for flag: String) -> String? {
        let args = arguments()
        for (index, arg) in args.enumerated() {
            if arg == flag, index + 1 < args.count {
                let candidate = args[index + 1]
                return candidate.isEmpty ? nil : candidate
            }
            let prefix = flag + "="
            if arg.hasPrefix(prefix) {
                let candidate = String(arg.dropFirst(prefix.count))
                return candidate.isEmpty ? nil : candidate
            }
        }
        return nil
    }
}
