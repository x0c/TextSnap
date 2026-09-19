<!-- managed:inherited-agents:start -->
<!-- source: /Users/geraltgraham/Codes/TextSnap/AGENTS.md -->
# TextSnap

通用工程规范：[Swift 规范](/Users/geraltgraham/Codes/_standards/swift.md)

TextSnap 是 macOS 屏幕文字识别小工具：按快捷键框选屏幕，系统直接认字，文字进入剪贴板。

## 组件一览

| 目录 | 说明 | 状态 |
|---|---|---|
| `app-macos/` | macOS 客户端（独立 git 仓库） | 已交付，用户 2026-09-19 真机验收通过 |

Remote：`app-macos` → Forgejo 私有 `Max/TextSnap`（计划中，尚未建仓推送，当前仅本地 git）。本产品文件夹不是 git 仓库。自用，不公开更新源。

## 钉死的体验

- 出厂快捷键 Command Shift 2，可改，可清除。
- 按下后走系统框选，Esc 取消。
- 认字只用本机 Vision，不联网。
- 认出文字直接进剪贴板并响一声，不弹窗打扰。
- 认不出、没开屏幕录制才弹一次说明窗。
- 左键立即框选；右键菜单；不提供隐藏菜单栏图标。
- 开机自启默认关；检查更新走「没有公开更新源」。

## 基线豁免

- **A1** 应用内自更新 / 对外 dmg：纯自用、不对外分发；仍须签名。
- **A2** 隐私清单：不收集、不上报用户数据。
- **B3** 账号登录：无账号。**B5** App Intents：没有要交给快捷指令的动作。**B7** 离线优先：无网络业务数据。

**下列不是豁免，必须过：** A3 中英、A4 无蓝框、A5 窗口记忆、A7 图标与菜单栏模板、A8 版本双轨、B1 开机自启默认关、B2 可改快捷键、B4 设置窗、B6 权限最小化与拒绝降级。

## 明确不做

- 云同步、历史记录库、翻译、截图文件管理。
- Mac App Store 版、沙盒、第三方登录。
- 隐藏菜单栏图标。

## 工作约束

- 改 TextSnap 只读本产品目录（`~/Codes/TextSnap/`）与文档导航里显式引用的标准文档；不翻阅其他产品仓源码（2026-09-19 用户否决：前面为套工程惯例翻了别的仓，用户已叫停）。

## 文档导航

- [app-macos/AGENTS.md](/Users/geraltgraham/Codes/TextSnap/app-macos/AGENTS.md)：改、评审或排查本应用工程、快捷键、框选、认字、剪贴板、菜单栏或覆盖安装前**必读**。
- [app-macos/docs/PRODUCT_CONTRACT.md](/Users/geraltgraham/Codes/TextSnap/app-macos/docs/PRODUCT_CONTRACT.md)：改、评审或排查任何用户可见行为前**必读**。
- [Swift 规范](/Users/geraltgraham/Codes/_standards/swift.md)：新建、评审或改造本 macOS 应用前**必读**。
- [macos-app-baseline](/Users/geraltgraham/Codes/_standards/workspace-docs/swift-docs/macos-app-baseline.md)：评审本应用完整度、补分发/开机自启/快捷键/设置窗前**必读**。

<!-- managed:inherited-agents:end -->

# TextSnap app-macos

Product intent: [docs/PRODUCT_CONTRACT.md](docs/PRODUCT_CONTRACT.md). This file is engineering and acceptance.

## Documentation navigation

- [docs/PRODUCT_CONTRACT.md](docs/PRODUCT_CONTRACT.md): **Must read** before changing or reviewing capture flow, hotkey, OCR, clipboard, or menu behavior.
- [../../_standards/swift.md](../../_standards/swift.md): Swift engineering baseline.
- [../../_standards/workspace-docs/swift-docs/macos-app-baseline.md](../../_standards/workspace-docs/swift-docs/macos-app-baseline.md): completion checklist.

## Remote

Forgejo private `Max/TextSnap` (PascalCase native-app name). Do not put the intranet SSH URL in files that might go public later.

## Engineering

- Generate the Xcode project with `xcodegen generate`; do not hand-edit `.xcodeproj`.
- Bundle ID: `top.caozc.TextSnap`. `LSUIElement`. No sandbox. No entitlements file (no special capabilities; screen capture is pure TCC + usage description).
- MacKit ≥0.1.4: Core, LaunchAtLogin, Lifecycle, StatusItem. No Sparkle; "Check for Updates" uses `PersonalBuildUpdateChecker` (no public channel).
- Factory hotkey is Command Shift 2 (`kVK_ANSI_2` + `cmdKey | shiftKey`). Customizable, clearable, restorable. Never hard-code anywhere except the factory default.
- Capture path is `/usr/sbin/screencapture -i -s` (system selector) + on-device Vision `VNRecognizeTextRequest` (accurate). No network. Re-entrant hotkey presses while a capture is in flight are dropped (generation guard).
- Recognized text goes straight to the general pasteboard. No result window on success; a short sound confirms. Alerts only for denied permission / empty result / failure.
- Screen capture permission: `NSScreenCaptureUsageDescription` is mandatory (process is killed without it). Denied state offers Open System Settings + explicit retry; re-check on appear and on become-active.
- Settings live in `~/.config/textsnap/settings.json` (`$XDG_CONFIG_HOME` aware). No home-directory dotfiles, no Application Support copy.
- Menu bar is the primary entry: `MenuBarReopenPolicy` with `menubarIsPrimaryEntry: true`. No hide-icon item anywhere. Left click captures immediately.
- Single settings window holds everything: shortcut, permission, launch at login, last result, capture / check updates / about / quit. Right-click menu has parity.

## Verification

```bash
xcodegen generate
xcodebuild -project TextSnap.xcodeproj -scheme TextSnap -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData build
xcodebuild -project TextSnap.xcodeproj -scheme TextSnap -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData test
```

Overlay install must delete the old bundle first, then copy whole, then launch once:

```bash
pkill -x TextSnap || true
xcodebuild -project TextSnap.xcodeproj -scheme TextSnap -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData build
rm -rf /Applications/TextSnap.app
ditto build/DerivedData/Build/Products/Release/TextSnap.app /Applications/TextSnap.app
xattr -dr com.apple.quarantine /Applications/TextSnap.app 2>/dev/null || true
open /Applications/TextSnap.app
```

First run is silent (no window). Do NOT re-open the app within 60 seconds to trigger the reopen guard, and do NOT open the settings window just for screenshots. Confirm the process is alive and the hotkey registration marker is in the log instead.
