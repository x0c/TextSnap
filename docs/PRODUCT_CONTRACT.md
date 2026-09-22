# TextSnap product contract

Read this before changing, reviewing, or troubleshooting capture, hotkey, OCR, clipboard, menu, or "Check for Updates".

## One sentence

Press a shortcut, drag a region on screen, the text in it lands in the clipboard.

## Flow

1. User presses the global shortcut (factory: Command Shift 2) or clicks the menu bar icon (left click), or picks Capture from the menu / settings.
2. The system selector appears (`screencapture -i -s`). Esc cancels; nothing happens.
3. On-device Vision reads the captured PNG (accurate level, language correction). No network.
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

## Storage

- Settings file: `~/.config/textsnap/settings.json` (`$XDG_CONFIG_HOME` aware). Last recognized text is memory-only, never written to disk.
- No history database, no second copy under Application Support, no home-directory dotfiles.

## Updates

Default is public distribution: GitHub Releases feed the in-app updater (Sparkle); a signed, notarized `.dmg` is the first-install entry. Never claims to be up to date.
