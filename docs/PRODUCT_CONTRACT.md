# TextSnap product contract

Read this before changing, reviewing, or troubleshooting capture, hotkey, OCR, clipboard, menu, or "Check for Updates".

## One sentence

Press a shortcut, drag a region on screen, the text in it lands in the clipboard.

## Flow

1. User presses the global shortcut (factory: Command Shift 2) or clicks the menu bar icon (left click), or picks Capture from the menu / settings.
2. The system selector appears (`screencapture -i -s`). Esc cancels; nothing happens.
3. On-device Vision reads the captured PNG (accurate level, revision 3, language correction, automatic language detection, Chinese-varieties-first language order). No network.
4. Non-empty text goes straight to the general pasteboard; a short sound confirms. No result window.
5. Empty result, capture failure, or missing screen-recording permission shows a one-shot explanatory alert with a way forward. Never a silent failure, never a retry loop.

## Hotkey

- Factory default is Command Shift 2. User can record a new combination, clear it, or restore the default. Settings apply immediately and survive restart.
- A combination already taken fails loudly in settings; system-reserved combinations are refused with a reason.
- A second press while a capture is already in flight is dropped, never queued.

## Permission

- Screen recording is pure TCC. First capture triggers the system prompt; the usage description explains the capture-then-recognize purpose.
- Denied state is a first-class UI state: what is missing, what breaks, an Open System Settings button, and an explicit retry. Coming back from settings re-checks automatically.
- No other system permission is requested.

## Menu and settings parity

- Right-click menu: Capture Now / Settings / Launch at Login (tri-state) / Check for Updates / About / Quit. No hide-icon item.
- The single settings window offers the same: shortcut editor, permission state, launch toggle, last result with Copy Again, capture / check updates / about / quit, version.
- Left click is Capture Now.

## Settings layout (2026-10-18)

The current fleet-settings task explicitly authorizes opening this surface for installed visual acceptance; the normal silent-launch contract still applies. Use one public SwiftUI `Settings` scene, with a 480-point native grouped `Form` sized to its measured content. Four groups contain Capture (shortcut, screen-recording state and Capture Now), Last Result (memory-only text, at most four visible lines, plus Copy Again), General (the existing launch-at-login switch), and the app icon/name/version with About, Check for Updates and Quit. Preserve every existing menu/settings action; do not add a menu-icon visibility setting.

Replace stacked GroupBoxes and standalone action rows with native `Section`, `LabeledContent`, `Toggle`, `Button` and `Menu`. Keep shortcut editing on the existing recorder; its native value button starts recording and its action menu clears or restores the shortcut. Move ordinary recording guidance to help; show conflicts, denied permissions and pending login approval inline. The empty last-result message must not hardcode the factory shortcut because the user can change it. No custom backgrounds, focus frames or control lookalikes. Settings do not scroll; content height follows permission/error/result changes. Escape cancels recording first and otherwise closes Settings. Keep the existing autosave name and MacKit accessory activation session.

Reference selection: inspected this product's actual SettingsView, window controller and shortcut/permission/login implementations. Retain their business actions and state, and apply the grouped-Form/content-height recipe in the shared macOS settings and AppKit guides; no other product source is imported. Apple's public [Settings](https://developer.apple.com/documentation/swiftui/settings), [Form](https://developer.apple.com/documentation/swiftui/form) and [LabeledContent](https://developer.apple.com/documentation/swiftui/labeledcontent) APIs fit this macOS 26+ target and are present in the installed Xcode 27.2 SDK. The app's existing icon remains unchanged while its separate redesign is pending.

Acceptance: inspect the installed window in dark English and light Chinese, including keyboard/AX labels, recording cancellation, permission status, and the about/update actions. Verify settings opens only from explicit entry points, returns to accessory mode when closed, and restores position on normal restart. Run the existing tests and complete Release build/analyze diagnostics. Public signed distribution requires meaningful bilingual release and update notes; the coordinator commits before the archive/install and publishes the whole current workspace.

## Storage

- Settings file: `~/.config/textsnap/settings.json` (`$XDG_CONFIG_HOME` aware). Last recognized text is memory-only, never written to disk.
- No history database, no second copy under Application Support, no home-directory dotfiles.

## Updates

Default is public distribution: GitHub Releases feed the in-app updater (Sparkle); a signed, notarized `.dmg` is the first-install entry. Never claims to be up to date.

## Diagnostics and release notes

Release notes live in [CHANGELOG.md](../CHANGELOG.md); the publisher embeds the matching English and complete Simplified Chinese section in both Sparkle and GitHub. The archive explicitly builds arm64 and x86_64 for the supported Mac architectures. The existing Vision results property is already a typed optional array in the installed SDK, so its no-op conditional downcast is removed without changing recognition order or output.

The Sparkle 2.10.0 runtime warning about background scheduled checks without gentle reminders is retained for this settings revision. Origin: the existing standard updater has no user-driver delegate. Sparkle's [background-app behavior and examples](https://sparkle-project.org/documentation/gentle-reminders/) explain that scheduled alerts appear behind other apps after launch; implementing its background reminder example would add Dock/notification behavior beyond this settings task and the current screen-recording-only permission contract. Manual Check for Updates still uses Sparkle's standard user-initiated UI. Residual risk: a background-only user may miss a scheduled alert. Follow-up: design an in-menu reminder or adopt a separately approved background reminder policy; do not merely return true from the support flag without providing a reminder.
