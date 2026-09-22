import Foundation
@testable import TextSnap
import Testing

private struct SettingsFile: Codable {
    var hotkeyKeyCode: Int?
    var hotkeyModifiers: Int?
    var hotkeyEnabled: Bool?
}

@Test func settingsFileRoundTrip() throws {
    let fm = FileManager.default
    let tmp = fm.temporaryDirectory.appendingPathComponent("TextSnapTests-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }
    let url = tmp.appendingPathComponent("settings.json")
    let sample = SettingsFile(hotkeyKeyCode: 120, hotkeyModifiers: 1_048_576, hotkeyEnabled: true)
    try JSONEncoder().encode(sample).write(to: url, options: .atomic)
    let back = try JSONDecoder().decode(SettingsFile.self, from: Data(contentsOf: url))
    #expect(back.hotkeyKeyCode == 120)
    #expect(back.hotkeyEnabled == true)
}

@Test func blankTrimmedTextCountsAsEmpty() {
    let blank = "  \n \t ".trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(blank.isEmpty)
}

@Test func recognizedLinesKeepBreaks() {
    let lines = ["第一行", "second line"]
    #expect(lines.joined(separator: "\n") == "第一行\nsecond line")
}

@Test func settingsDirectoryNameIsTextSnap() {
    #expect(TextSnapSettings.directoryURL().lastPathComponent == "textsnap")
}

@Test @MainActor func textSnapSettingsPersistsHotkey() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("TextSnapTests-\(UUID().uuidString)", isDirectory: true)
    let first = TextSnapSettings(directory: tmp)
    #expect(first.storedHotkey() == nil)
    first.saveHotkey(keyCode: 120, modifiers: 1_048_576)
    let second = TextSnapSettings(directory: tmp)
    #expect(second.storedHotkey()?.keyCode == 120)
    #expect(second.storedHotkey()?.modifiers == 1_048_576)
    try? FileManager.default.removeItem(at: tmp)
}

@Test @MainActor func textSnapSettingsClearDisablesHotkey() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("TextSnapTests-\(UUID().uuidString)", isDirectory: true)
    let settings = TextSnapSettings(directory: tmp)
    settings.saveHotkey(keyCode: 120, modifiers: 1_048_576)
    settings.clearHotkey()
    #expect(settings.storedHotkey() == nil)
    let reloaded = TextSnapSettings(directory: tmp)
    #expect(reloaded.storedHotkey() == nil)
    try? FileManager.default.removeItem(at: tmp)
}
