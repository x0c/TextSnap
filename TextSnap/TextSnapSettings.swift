import Foundation

/// File-backed preferences for shortcuts and menu-bar visibility. OCR text stays memory-only.
@MainActor
@Observable
final class TextSnapSettings {
    static let shared = TextSnapSettings()

    var hotkeyKeyCode: UInt32?
    var hotkeyModifiers: UInt32?
    var hotkeyEnabled: Bool
    private(set) var isMenuBarIconVisible: Bool

    static let defaultMenuBarIconVisible = true

    private let fileURL: URL

    init(directory: URL? = nil) {
        let dir = directory ?? Self.directoryURL()
        self.fileURL = dir.appendingPathComponent("settings.json")
        let loaded = Self.load(from: fileURL)
        self.hotkeyKeyCode = loaded.keyCode
        self.hotkeyModifiers = loaded.modifiers
        self.hotkeyEnabled = loaded.enabled
        self.isMenuBarIconVisible = loaded.iconVisible
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

    /// Keep the current state if the preference cannot be saved.
    func setMenuBarIconVisible(_ visible: Bool) -> Bool {
        let previous = isMenuBarIconVisible
        isMenuBarIconVisible = visible
        guard persist() else {
            isMenuBarIconVisible = previous
            return false
        }
        return true
    }

    private struct Loaded: Sendable {
        var keyCode: UInt32?
        var modifiers: UInt32?
        var enabled: Bool
        var iconVisible: Bool
    }

    private struct File: Codable {
        var hotkeyKeyCode: Int?
        var hotkeyModifiers: Int?
        var hotkeyEnabled: Bool?
        var isMenuBarIconVisible: Bool?

        enum CodingKeys: String, CodingKey {
            case hotkeyKeyCode, hotkeyModifiers, hotkeyEnabled
            case isMenuBarIconVisible = "menuBar.iconVisible"
        }
    }

    private static func load(from url: URL) -> Loaded {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(File.self, from: data)
        else {
            return Loaded(keyCode: nil, modifiers: nil, enabled: true, iconVisible: defaultMenuBarIconVisible)
        }
        let code = decoded.hotkeyKeyCode.map { UInt32($0) }
        let mods = decoded.hotkeyModifiers.map { UInt32($0) }
        return Loaded(
            keyCode: code, modifiers: mods, enabled: decoded.hotkeyEnabled ?? true,
            iconVisible: decoded.isMenuBarIconVisible ?? defaultMenuBarIconVisible
        )
    }

    @discardableResult
    private func persist() -> Bool {
        let dir = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
            let file = File(
                hotkeyKeyCode: hotkeyKeyCode.map { Int($0) },
                hotkeyModifiers: hotkeyModifiers.map { Int($0) },
                hotkeyEnabled: hotkeyEnabled,
                isMenuBarIconVisible: isMenuBarIconVisible
            )
            let data = try JSONEncoder().encode(file)
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            return true
        } catch {
            #if DEBUG
            NSLog("[TextSnap] settings persist failed: %@", error.localizedDescription)
            #endif
            return false
        }
    }
}
