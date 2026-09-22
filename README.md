**Languages:** English | [简体中文](README.zh-CN.md)

# TextSnap

<img src="docs/images/app-icon.png" width="96" height="96" alt="TextSnap app icon">

Press a shortcut, drag a region on screen, and the text in it lands in your clipboard. macOS menu-bar OCR powered entirely by on-device Apple Vision — no screenshots to manage, no cloud, no accounts.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Latest release](https://img.shields.io/github/v/release/x0c/TextSnap)](https://github.com/x0c/TextSnap/releases/latest)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-black)

![TextSnap settings window](docs/images/settings.png)

## Features

- **Shortcut capture** — factory shortcut `⌘⇧2`, re-recordable, clearable, restorable; system-reserved combos are refused with a reason.
- **System selector** — the familiar crosshair you already know; `Esc` cancels silently.
- **On-device OCR** — Apple Vision, accurate level, with language correction. Nothing leaves your Mac.
- **Silent success** — recognized text goes straight to the clipboard with a short sound. No result window.
- **Honest failure** — empty result or denied permission shows one explanatory alert with a way forward, never a retry loop.
- **Menu-bar native** — left click captures, right click menus; no dock icon, first launch stays silent.
- **Automatable** — a `Capture Screen Text` AppIntent exposes the core action to Shortcuts and Spotlight.

## Supported platforms

macOS 26 (Tahoe) and later, Apple silicon and Intel. TextSnap depends on macOS-only APIs (Vision, ScreenCapture TCC, menu-bar extras), so there is no Windows or Linux version.

## Install

Download the signed `.dmg` from the [latest release](https://github.com/x0c/TextSnap/releases/latest), open it, drag TextSnap to Applications, and launch it once. First launch is silent — look for the viewfinder icon in the menu bar, then press `⌘⇧2`.

Pressing the shortcut the first time asks for Screen Recording permission; without it TextSnap cannot see the region you select. If you denied it earlier, open Settings for a one-tap jump back to System Settings.

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

Open Settings (right-click the menu-bar icon) to change the shortcut, check permission state, toggle Launch at Login, or copy the last result again. Settings live in `~/.config/textsnap/settings.json`; recognized text itself is memory-only and never written to disk.

## FAQ

**It says permission is denied. What now?**
Open Settings → Permission → Open System Settings, enable TextSnap under Screen Recording, then come back — the app re-checks automatically.

**It captured but found no text.**
The region probably had no readable text (or too small to read). One alert explains it; press the shortcut and drag a tighter region.

**Does it upload my screen anywhere?**
No. Capture uses `/usr/sbin/screencapture`, recognition uses Apple's on-device Vision. There is no network code and no history database.

**Will it auto-update?**
No. There is no update feed; "Check for Updates" says so honestly. New versions live in the repo itself — pull and rebuild when you want one.

**My shortcut does nothing / says taken.**
Another app already owns that combo — Settings tells you loudly instead of failing silently. Pick a combo with modifiers outside the system screenshot family (`⌘⇧3/4/5/6` are reserved by macOS).

## License

[MIT](LICENSE)
