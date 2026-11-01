import Foundation
import MacKitCore
@testable import TextSnap
import Testing

@Test @MainActor func menuBarIconDefaultsToVisible() {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("TextSnapTests-\(UUID().uuidString)", isDirectory: true)
    #expect(TextSnapSettings(directory: directory).isMenuBarIconVisible)
}

@Test @MainActor func legacySettingsKeepShortcutAndVisibleIcon() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("TextSnapTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let legacy = Data(#"{"hotkeyKeyCode":120,"hotkeyModifiers":1048576,"hotkeyEnabled":true}"#.utf8)
    try legacy.write(to: directory.appendingPathComponent("settings.json"))
    let settings = TextSnapSettings(directory: directory)
    #expect(settings.isMenuBarIconVisible)
    #expect(settings.storedHotkey()?.keyCode == 120)
    #expect(settings.storedHotkey()?.modifiers == 1_048_576)
}

@Test @MainActor func menuBarVisibilityPersistsWithoutChangingShortcut() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("TextSnapTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let settings = TextSnapSettings(directory: directory)
    settings.saveHotkey(keyCode: 120, modifiers: 1_048_576)
    #expect(settings.setMenuBarIconVisible(false))
    let hidden = TextSnapSettings(directory: directory)
    #expect(!hidden.isMenuBarIconVisible)
    #expect(hidden.storedHotkey()?.keyCode == 120)
    #expect(hidden.storedHotkey()?.modifiers == 1_048_576)
    hidden.clearHotkey()
    let cleared = TextSnapSettings(directory: directory)
    #expect(!cleared.isMenuBarIconVisible)
    #expect(!cleared.hotkeyEnabled)
    #expect(cleared.setMenuBarIconVisible(true))
    let restored = TextSnapSettings(directory: directory)
    #expect(restored.isMenuBarIconVisible)
    #expect(!restored.hotkeyEnabled)
    let url = directory.appendingPathComponent("settings.json")
    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
    #expect(json?["menuBar.iconVisible"] as? Bool == true)
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
    #expect((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
}

@Test @MainActor func failedVisibilitySaveKeepsPreviousState() throws {
    let file = FileManager.default.temporaryDirectory
        .appendingPathComponent("TextSnapTests-\(UUID().uuidString)")
    try Data("not a directory".utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    let settings = TextSnapSettings(directory: file)
    #expect(!settings.setMenuBarIconVisible(false))
    #expect(settings.isMenuBarIconVisible)
}

@Test func hiddenIconRecoveryDistinguishesLoginFromUserRequests() {
    #expect(!MenuBarReopenPolicy.shouldShowRecoveryWindow(iconVisible: false, isLoginLaunch: true))
    #expect(MenuBarReopenPolicy.shouldShowRecoveryWindow(iconVisible: false, isLoginLaunch: false))
    #expect(!MenuBarReopenPolicy.shouldShowRecoveryWindow(iconVisible: true, isLoginLaunch: false))
    #expect(MenuBarReopenPolicy.presentation(
        iconVisible: false, isReopenOrLaunch: true, isLoginLaunch: false,
        menubarIsPrimaryEntry: true, secondsSinceReady: 3_600
    ) == .showRecoveryWindow)
    #expect(MenuBarReopenPolicy.presentation(
        iconVisible: true, isReopenOrLaunch: true, isLoginLaunch: false,
        menubarIsPrimaryEntry: true, secondsSinceReady: 3_600
    ) == .none)
}
