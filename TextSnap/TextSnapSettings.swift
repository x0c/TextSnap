import Foundation

/// File-backed settings. Single truth for the hotkey. Last OCR text stays memory-only.
@MainActor
@Observable
final class TextSnapSettings {
    static let shared = TextSnapSettings()

    var hotkeyKeyCode: UInt32?
    var hotkeyModifiers: UInt32?
    var hotkeyEnabled: Bool

    private let fileURL: URL
    private var suppressPersist = false

    init(directory: URL? = nil) {
        let dir = directory ?? Self.directoryURL()
        self.fileURL = dir.appendingPathComponent("settings.json")
        let loaded = Self.load(from: fileURL)
        self.hotkeyKeyCode = loaded.keyCode
        self.hotkeyModifiers = loaded.modifiers
        self.hotkeyEnabled = loaded.enabled
    }

    nonisolated static func directoryURL() -> URL {
        let fm = FileManager.default
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            return URL(fileURLWithPath: xdg, isDirectory: true).appendingPathComponent("textsnap", isDirectory: true)
        }
        return fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("textsnap", isDirectory: true)
    }

    func saveHotkey(keyCode: UInt32, modifiers: UInt32) {
        hotkeyKeyCode = keyCode
        hotkeyModifiers = modifiers
        hotkeyEnabled = true
        persist()
    }

    func clearHotkey() {
        hotkeyKeyCode = nil
        hotkeyModifiers = nil
        hotkeyEnabled = false
        persist()
    }

    func storedHotkey() -> (keyCode: UInt32, modifiers: UInt32)? {
        guard hotkeyEnabled, let code = hotkeyKeyCode, let mods = hotkeyModifiers else { return nil }
        return (code, mods)
    }

    private struct Loaded: Sendable {
        var keyCode: UInt32?
        var modifiers: UInt32?
        var enabled: Bool
    }

    private struct File: Codable {
        var hotkeyKeyCode: Int?
        var hotkeyModifiers: Int?
        var hotkeyEnabled: Bool?
    }

    private static func load(from url: URL) -> Loaded {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(File.self, from: data)
        else {
            return Loaded(keyCode: nil, modifiers: nil, enabled: true)
        }
        let code = decoded.hotkeyKeyCode.map { UInt32($0) }
        let mods = decoded.hotkeyModifiers.map { UInt32($0) }
        return Loaded(keyCode: code, modifiers: mods, enabled: decoded.hotkeyEnabled ?? true)
    }

    private func persist() {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = File(
            hotkeyKeyCode: hotkeyKeyCode.map { Int($0) },
            hotkeyModifiers: hotkeyModifiers.map { Int($0) },
            hotkeyEnabled: hotkeyEnabled
        )
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
