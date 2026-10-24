import AppKit
@preconcurrency import Carbon
import SwiftUI

/// Global hotkey. Factory default is Command Shift 2. Never hard-code except the default.
@MainActor
final class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    struct Shortcut: Equatable {
        let keyCode: UInt32
        let modifiers: UInt32

        /// Factory default: Command Shift 2.
        static let factoryDefault = Shortcut(
            keyCode: UInt32(kVK_ANSI_2),
            modifiers: UInt32(cmdKey | shiftKey)
        )

        var displayName: String {
            let parts: [(UInt32, String)] = [
                (UInt32(cmdKey), "⌘"),
                (UInt32(optionKey), "⌥"),
                (UInt32(controlKey), "⌃"),
                (UInt32(shiftKey), "⇧"),
            ]
            let prefix = parts.compactMap { modifiers & $0.0 != 0 ? $0.1 : nil }.joined()
            return prefix + Self.keyName(for: keyCode)
        }

        static func keyName(for keyCode: UInt32) -> String {
            switch Int(keyCode) {
            case kVK_ANSI_A: return "A"
            case kVK_ANSI_B: return "B"
            case kVK_ANSI_C: return "C"
            case kVK_ANSI_D: return "D"
            case kVK_ANSI_E: return "E"
            case kVK_ANSI_F: return "F"
            case kVK_ANSI_G: return "G"
            case kVK_ANSI_H: return "H"
            case kVK_ANSI_I: return "I"
            case kVK_ANSI_J: return "J"
            case kVK_ANSI_K: return "K"
            case kVK_ANSI_L: return "L"
            case kVK_ANSI_M: return "M"
            case kVK_ANSI_N: return "N"
            case kVK_ANSI_O: return "O"
            case kVK_ANSI_P: return "P"
            case kVK_ANSI_Q: return "Q"
            case kVK_ANSI_R: return "R"
            case kVK_ANSI_S: return "S"
            case kVK_ANSI_T: return "T"
            case kVK_ANSI_U: return "U"
            case kVK_ANSI_V: return "V"
            case kVK_ANSI_W: return "W"
            case kVK_ANSI_X: return "X"
            case kVK_ANSI_Y: return "Y"
            case kVK_ANSI_Z: return "Z"
            case kVK_ANSI_0: return "0"
            case kVK_ANSI_1: return "1"
            case kVK_ANSI_2: return "2"
            case kVK_ANSI_3: return "3"
            case kVK_ANSI_4: return "4"
            case kVK_ANSI_5: return "5"
            case kVK_ANSI_6: return "6"
            case kVK_ANSI_7: return "7"
            case kVK_ANSI_8: return "8"
            case kVK_ANSI_9: return "9"
            case kVK_ANSI_Equal: return "="
            case kVK_ANSI_Minus: return "-"
            case kVK_ANSI_RightBracket: return "]"
            case kVK_ANSI_LeftBracket: return "["
            case kVK_ANSI_Quote: return "'"
            case kVK_ANSI_Semicolon: return ";"
            case kVK_ANSI_Backslash: return "\\"
            case kVK_ANSI_Comma: return ","
            case kVK_ANSI_Slash: return "/"
            case kVK_ANSI_Period: return "."
            case kVK_ANSI_Grave: return "`"
            case kVK_F1: return "F1"
            case kVK_F2: return "F2"
            case kVK_F3: return "F3"
            case kVK_F4: return "F4"
            case kVK_F5: return "F5"
            case kVK_F6: return "F6"
            case kVK_F7: return "F7"
            case kVK_F8: return "F8"
            case kVK_F9: return "F9"
            case kVK_F10: return "F10"
            case kVK_F11: return "F11"
            case kVK_F12: return "F12"
            case kVK_LeftArrow: return "←"
            case kVK_RightArrow: return "→"
            case kVK_UpArrow: return "↑"
            case kVK_DownArrow: return "↓"
            case kVK_ForwardDelete: return "⌦"
            case kVK_Space: return String(localized: "hotkey.key.space")
            case kVK_Return: return "↩"
            case kVK_Tab: return "⇥"
            case kVK_Escape: return "⎋"
            default: return String(localized: "hotkey.key.unknown")
            }
        }
    }

    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var shortcut: Shortcut?
    @Published private(set) var isRecording = false

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var recordingMonitor: Any?
    private var nextHotKeyID: UInt32 = 1
    private var retryTask: Task<Void, Never>?
    private var settleTasks: [Task<Void, Never>] = []
    private var hotKeyObservers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    var onHotKey: (@MainActor () -> Void)?

    private init() {
        if let stored = TextSnapSettings.shared.storedHotkey() {
            shortcut = Shortcut(keyCode: stored.keyCode, modifiers: stored.modifiers)
        } else if TextSnapSettings.shared.hotkeyEnabled {
            shortcut = .factoryDefault
        } else {
            shortcut = nil
        }
    }

    /// Launch entry point: register before any window or system-service work,
    /// then keep trying and re-assert across session activation. A login-time
    /// WindowServer stall must not leave the shortcut dead until the next restart.
    func startFromLaunch() {
        observeLifecycle()
        guard let shortcut else {
            TextSnapLog.hotkey.notice("launch registration skipped: shortcut cleared")
            return
        }
        TextSnapLog.hotkey.notice(
            "launch registration begin keyCode=\(shortcut.keyCode, privacy: .public) modifiers=\(shortcut.modifiers, privacy: .public)"
        )
        register(shortcut, persist: false)
        scheduleSettleReasserts()
        if hotKeyRef == nil { scheduleRetry(reason: "launch") }
    }

    func register() {
        guard let shortcut else { return }
        register(shortcut, persist: false)
    }

    /// Force a fresh Carbon registration. Safe while already registered; used
    /// after wake/unlock and during the first minutes of a login session, when
    /// the WindowServer may still be settling.
    func reassertRegistration(reason: String) {
        guard let shortcut else { return }
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        TextSnapLog.hotkey.notice("reassert reason=\(reason, privacy: .public)")
        register(shortcut, persist: false)
        if hotKeyRef == nil { scheduleRetry(reason: reason) }
    }

    func unregister() {
        retryTask?.cancel()
        retryTask = nil
        settleTasks.forEach { $0.cancel() }
        settleTasks = []
        for observer in hotKeyObservers {
            observer.center.removeObserver(observer.token)
        }
        hotKeyObservers = []
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    /// Bounded exponential retry: a failed launch registration is retried until
    /// it succeeds, but never in a tight loop.
    private func scheduleRetry(reason: String) {
        retryTask?.cancel()
        retryTask = Task { @MainActor [weak self] in
            for (index, delay) in HotkeyRetryPolicy.delays.enumerated() {
                if Task.isCancelled { return }
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self, let shortcut = self.shortcut else { return }
                if self.hotKeyRef != nil { return }
                TextSnapLog.hotkey.notice(
                    "retry attempt \(index + 1, privacy: .public) reason=\(reason, privacy: .public)"
                )
                self.register(shortcut, persist: false)
                if self.hotKeyRef != nil {
                    TextSnapLog.hotkey.notice("retry succeeded")
                    return
                }
            }
            TextSnapLog.hotkey.error("retries exhausted; shortcut remains unregistered")
        }
    }

    /// Re-register a few times while a login session finishes bootstrapping.
    /// These passes are idempotent and cost nothing when already healthy.
    private func scheduleSettleReasserts() {
        settleTasks.forEach { $0.cancel() }
        settleTasks = HotkeySettlePolicy.delays.map { delay in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                self?.reassertRegistration(reason: "settle")
            }
        }
    }

    private func observeLifecycle() {
        guard hotKeyObservers.isEmpty else { return }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let workspaceNames: [Notification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ]
        for name in workspaceNames {
            let token = workspaceCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reassertRegistration(reason: name.rawValue)
                }
            }
            hotKeyObservers.append((workspaceCenter, token))
        }
        let unlockName = Notification.Name("com.apple.screenIsUnlocked")
        let unlockToken = DistributedNotificationCenter.default().addObserver(
            forName: unlockName, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reassertRegistration(reason: "unlock")
            }
        }
        hotKeyObservers.append((DistributedNotificationCenter.default(), unlockToken))
    }

    func beginRecording() {
        stopRecording()
        lastErrorMessage = nil
        isRecording = true
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated {
                self.finishRecording(event)
            }
            return nil
        }
    }

    func stopRecording() {
        if let recordingMonitor {
            NSEvent.removeMonitor(recordingMonitor)
            self.recordingMonitor = nil
        }
        isRecording = false
    }

    func clearShortcut() {
        stopRecording()
        retryTask?.cancel()
        retryTask = nil
        settleTasks.forEach { $0.cancel() }
        settleTasks = []
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        shortcut = nil
        TextSnapSettings.shared.clearHotkey()
        lastErrorMessage = nil
        TextSnapLog.hotkey.notice("shortcut cleared")
    }

    func restoreFactoryDefault() {
        stopRecording()
        register(.factoryDefault, persist: true)
    }

    private func finishRecording(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            return
        }
        let candidate = Shortcut(keyCode: UInt32(event.keyCode), modifiers: carbonModifiers(from: event.modifierFlags))
        stopRecording()
        guard candidate.modifiers != 0 else {
            lastErrorMessage = String(localized: "settings.hotkey.needModifier")
            return
        }
        guard !isReservedBySystem(candidate) else {
            lastErrorMessage = String(localized: "settings.hotkey.reserved")
            return
        }
        register(candidate, persist: true)
    }

    private func register(_ candidate: Shortcut, persist: Bool) {
        guard installEventHandler() else { return }
        if candidate == shortcut, hotKeyRef != nil { return }
        var newRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5453_4E50), id: nextHotKeyID) // 'TSNP'
        nextHotKeyID &+= 1
        let status = RegisterEventHotKey(candidate.keyCode, candidate.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &newRef)
        guard status == noErr, let newRef else {
            TextSnapLog.hotkey.error(
                "RegisterEventHotKey failed status=\(status, privacy: .public) keyCode=\(candidate.keyCode, privacy: .public) modifiers=\(candidate.modifiers, privacy: .public)"
            )
            lastErrorMessage = String(localized: "settings.hotkey.taken")
            return
        }
        if let oldRef = hotKeyRef { UnregisterEventHotKey(oldRef) }
        hotKeyRef = newRef
        shortcut = candidate
        lastErrorMessage = nil
        retryTask?.cancel()
        retryTask = nil
        TextSnapLog.hotkey.notice(
            "registered keyCode=\(candidate.keyCode, privacy: .public) modifiers=\(candidate.modifiers, privacy: .public) persisted=\(persist, privacy: .public)"
        )
        if persist {
            TextSnapSettings.shared.saveHotkey(keyCode: candidate.keyCode, modifiers: candidate.modifiers)
        }
    }

    private func installEventHandler() -> Bool {
        guard eventHandler == nil else { return true }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.dispatchHotKey()
            return noErr
        }, 1, &eventType, selfPtr, &eventHandler)
        guard status == noErr else {
            TextSnapLog.hotkey.error("InstallEventHandler failed status=\(status, privacy: .public)")
            lastErrorMessage = String(localized: "settings.hotkey.initFailed")
            return false
        }
        return true
    }

    nonisolated private func dispatchHotKey() {
        TextSnapLog.hotkey.notice("pressed")
        Task { @MainActor in self.onHotKey?() }
    }

    private func carbonModifiers(from modifiers: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    private func isReservedBySystem(_ shortcut: Shortcut) -> Bool {
        let command = UInt32(cmdKey)
        let shift = UInt32(shiftKey)
        let commandOnlyKeys: Set<UInt32> = [
            UInt32(kVK_Space),
            UInt32(kVK_Tab),
            UInt32(kVK_ANSI_Q),
            UInt32(kVK_ANSI_W),
            UInt32(kVK_ANSI_H),
            UInt32(kVK_ANSI_M),
            UInt32(kVK_ANSI_Grave),
        ]
        if shortcut.modifiers == command, commandOnlyKeys.contains(shortcut.keyCode) {
            return true
        }
        // System screenshot family.
        let screenshotKeys: Set<UInt32> = [
            UInt32(kVK_ANSI_3),
            UInt32(kVK_ANSI_4),
            UInt32(kVK_ANSI_5),
            UInt32(kVK_ANSI_6),
        ]
        return shortcut.modifiers == (command | shift) && screenshotKeys.contains(shortcut.keyCode)
    }
}

/// Backoff for a failed launch registration. Delays are absolute per attempt,
/// so a persistently blocked shortcut never spins the main thread.
enum HotkeyRetryPolicy {
    nonisolated static let delays: [Duration] = [
        .seconds(1), .seconds(2), .seconds(4), .seconds(8),
        .seconds(15), .seconds(30), .seconds(60), .seconds(120),
    ]
}

/// Re-registration points while a login session finishes bootstrapping.
enum HotkeySettlePolicy {
    nonisolated static let delays: [Duration] = [
        .seconds(5), .seconds(30), .seconds(90),
    ]
}
