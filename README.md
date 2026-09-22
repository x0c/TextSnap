**Languages:** English | [简体中文](README.zh-CN.md)

# TextSnap

<img src="docs/images/app-icon.png" width="96" height="96" alt="TextSnap app icon">

Press a shortcut, drag a region on screen, and the text in it lands in your clipboard. macOS menu-bar OCR powered entirely by on-device Apple Vision — no screenshots to manage, no cloud, no accounts.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Latest release](https://img.shields.io/github/v/release/x0c/TextSnap)](https://github.com/x0c/TextSnap/releases/latest)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-black)

> **macOS only.** TextSnap depends on macOS-only APIs (Vision, screen-capture permission, menu-bar extras) — there is no Windows or Linux version.

## Features

- **Shortcut capture** — factory shortcut `⌘⇧2`, re-recordable, clearable, restorable; taken or system-reserved combos are refused with a reason.
- **System selector** — the familiar crosshair; `Esc` cancels silently.
- **On-device OCR** — Apple Vision, accurate level, with language correction. Nothing leaves your Mac.
- **Silent success** — recognized text goes straight to the clipboard with a short sound. No result window.
- **Honest failure** — empty result or denied permission shows one explanatory alert with a way forward, never a retry loop.
- **Menu-bar native** — left click captures, right click menus; no dock icon, first launch stays silent.
- **Automatable** — a `Capture Screen Text` action for Shortcuts and Spotlight.

## Supported platforms

macOS 26 (Tahoe) and later, Apple silicon and Intel. No Windows or Linux version (see above).

## Install

Download the signed `.dmg` from the [latest release](https://github.com/x0c/TextSnap/releases/latest), open it, drag TextSnap to Applications, and launch it once. First launch is silent — look for the viewfinder icon in the menu bar, then press `⌘⇧2`.


Pressing the shortcut the first time asks for Screen Recording permission; without it TextSnap cannot see the region you select. If you denied it earlier, Settings offers a one-tap jump back to System Settings.

### Build from source

Requires Xcode 26 and [xcodegen](https://github.com/yonaskolb/XcodeGen):

```bash
xcodegen generate
xcodebuild -project TextSnap.xcodeproj -scheme TextSnap -configuration Release \
  -destination 'platform=macOS' build
```

## Usage

1. Press `⌘⇧2` (or left-click the menu-bar icon, or choose Capture from the menu).
2. Drag the region. Release to recognize, `Esc` to cancel.
3. Paste anywhere — the text is already in your clipboard.

Right-click the menu-bar icon for Settings: change the shortcut, check permission state, toggle Launch at Login, or copy the last result again. Settings live in `~/.config/textsnap/settings.json`; recognized text itself is memory-only and never written to disk.

## FAQ

**Permission denied. What now?**
Settings → Permission → Open System Settings, enable TextSnap under Screen Recording, then come back — the app re-checks automatically.

**It captured but found no text.**
The region probably had no readable text (or was too small). One alert explains it; press the shortcut and drag a tighter region.

**Does it upload my screen anywhere?**
No. Capture uses `/usr/sbin/screencapture`, recognition uses on-device Vision. No network code, no history database.

**Will it auto-update?**
The app checks the GitHub Releases feed once the first public release is out; until then "Check for Updates" says so honestly instead of claiming you are up to date.

**Shortcut does nothing / says taken.**
Another app already owns that combo — Settings tells you plainly instead of failing silently. Pick another combo with modifiers (`⌘⇧3/4/5/6` belong to macOS screenshots).

## License

[MIT](LICENSE)
