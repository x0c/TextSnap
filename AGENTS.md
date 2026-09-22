<!-- managed:inherited-agents:start -->
<!-- source: /Users/geraltgraham/Codes/TextSnap/AGENTS.md -->
# TextSnap

通用工程规范：[Swift 规范](/Users/geraltgraham/Codes/_standards/swift.md)

TextSnap 是 macOS 屏幕文字识别小工具：按快捷键框选屏幕，系统直接认字，文字进入剪贴板。

## 组件一览

| 目录 | 说明 | 状态 |
|---|---|---|
| `app-macos/` | macOS 客户端（独立 git 仓库） | 已交付，用户 2026-09-19 真机验收通过 |

Remote：`app-macos` → Forgejo 私有 `Max/TextSnap`（开发真源）+ GitHub 公开 `x0c/TextSnap`（门面与发行，https://github.com/x0c/TextSnap）。本产品文件夹不是 git 仓库。**发行默认走公开 GitHub**（2026-09-22 用户裁定）：正式 Release 附 Developer ID 签名并公证的 `.dmg`，应用内走 Sparkle 自更新；链路建成前按自用执行，但不得谎报最新。

## 钉死的体验

- 出厂快捷键 Command Shift 2，可改，可清除。
- 按下后走系统框选，Esc 取消。
- 认字只用本机 Vision，不联网。
- 认出文字直接进剪贴板并响一声，不弹窗打扰。
- 认不出、没开屏幕录制才弹一次说明窗。
- 左键立即框选；右键菜单；不提供隐藏菜单栏图标。
- 开机自启默认关；检查更新走公开更新源（GitHub Releases + Sparkle 应用内自更新），不得谎报已是最新。

## 基线豁免（2026-09-19 复核，c6c2341 落地后）

- **A1 已过豁免期，不再豁免**（2026-09-22 用户裁定公开为默认）：发行链路 = Developer ID 签名 + 公证 `.dmg`（Release 首装入口）+ Sparkle 应用内自更新 + 一键安装渠道；配方见签名公证分发指南。**状态已落地**（v0.2.0 首发验证通过）：签名 + 公证 dmg + Sparkle 自更新 + 发版脚本 `scripts/publish-release.py`；后续发版沿用同一条链路。
- **A2** 隐私清单：不收集、不上报用户数据。C1 不做（无日志导出；崩溃走系统报告），C3 不做（无遥测）。
- **B3** 账号登录：无账号。**B7** 离线优先：无网络业务数据。
- **A7**：`.icon` 分层与扁平 `appiconset` 已并存（`ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` + `AppIcon.icon` 资源），产物含 `AppIcon.icns` + `Assets.car`；2026-09-19 起按 P1（下次动图标时迁分层生效链路）。
- **B5 已过，不再豁免**：`CaptureTextIntent`（框选→本机识字→进剪贴板）已暴露给快捷指令 / Spotlight；`AppIntent.metadata` 随包产物。

**下列不是豁免，必须过：** A3 中英、A4 无蓝框、A5 窗口记忆与标准菜单（⌘, 走系统 Settings 场景经 `.appSettings` 转到单设置窗）、A8 版本双轨（以 xcconfig 为准，project.yml 不再双写）、A9（`~/.config/textsnap/`，目录 700 / 文件 600）、B1 开机自启默认关、B2 可改快捷键（⌘⇧3/4/5/6 截图系预留）、B4 设置窗、B6 权限最小化与拒绝降级（回前台重检；首次授权即刻用 / 开关重开需重启）。

A6 无障碍审计尚未执行：下次改设置窗时补 Accessibility Inspector 一遍。

## 明确不做

- 云同步、历史记录库、翻译、截图文件管理。
- Mac App Store 版、沙盒、第三方登录。
- 隐藏菜单栏图标。

## 工作约束

- 执行默认不确认（2026-09-22 用户裁定）：构建、发版、文档、发行链路内的常规决策按规范直接做，做完汇报；不为选型停下等。缺外部输入（密钥、账号授权、额度）时一次性列清阻塞与自助命令。
- 改完立刻发布（2026-09-22 用户裁定）：任何源码改动验证通过后，同一会话内直接走 `app-macos/scripts/publish-release.py` 发新版（版本号 +1，提交推送双远端，签名公证 dmg 上公开 GitHub Release）；不攒改动、不等下一批、不问要不要发。发版脚本要外部等待（公证排队）时放后台跑，确认启动后即汇报，完成后唤醒。
- 改 TextSnap 只读本产品目录（`~/Codes/TextSnap/`）与文档导航里显式引用的标准文档；不翻阅其他产品仓源码（2026-09-19 用户否决：前面为套工程惯例翻了别的仓，用户已叫停）。

## 文档导航

- [app-macos/AGENTS.md](/Users/geraltgraham/Codes/TextSnap/app-macos/AGENTS.md)：改、评审或排查本应用工程、快捷键、框选、认字、剪贴板、菜单栏或覆盖安装前**必读**。
- [app-macos/docs/PRODUCT_CONTRACT.md](/Users/geraltgraham/Codes/TextSnap/app-macos/docs/PRODUCT_CONTRACT.md)：改、评审或排查任何用户可见行为前**必读**。
- [app-macos/README.md](/Users/geraltgraham/Codes/TextSnap/app-macos/README.md)（中文镜像 `README.zh-CN.md`）：改对外安装门面、发版说明前**必读**；两版结构对齐、同一提交内同步，应用图标展示须为圆角矩形。
- [GitHub 开源发布指南](~/.config/agentsync/docs/OPEN_SOURCE_GITHUB_GUIDE.md)：动公开门面（README/截图/图标/安装说明）、建公开仓、发公开 Release 前**必读**；先过脱敏审查，零命中才能推。
- [Swift 规范](/Users/geraltgraham/Codes/_standards/swift.md)：新建、评审或改造本 macOS 应用前**必读**。
- [macos-app-baseline](/Users/geraltgraham/Codes/_standards/workspace-docs/swift-docs/macos-app-baseline.md)：评审本应用完整度、补分发/开机自启/快捷键/设置窗前**必读**。
- [macOS 应用开发：菜单栏、生命周期与后台服务](~/.config/agentsync/docs/MACOS_APP_DEVELOPMENT_GUIDE.md)：改、评审或排查菜单栏、登录静默、二次启动防呆、右键与设置对等前**必读**。
- [桌面应用配置落点](~/.config/agentsync/docs/DESKTOP_APP_CONFIG_LOCATION_GUIDE.md)：改、评审或排查配置 / 日志 / 缓存落盘前**必读**。
- [macOS 系统授权](/Users/geraltgraham/Codes/_standards/workspace-docs/swift-docs/macos-system-permissions.md)：改、评审或排查屏幕录制授权与拒绝降级前**必读**。

<!-- managed:inherited-agents:end -->

# TextSnap app-macos

Product intent: [docs/PRODUCT_CONTRACT.md](docs/PRODUCT_CONTRACT.md). This file is engineering and acceptance.

## Documentation navigation

- [docs/PRODUCT_CONTRACT.md](docs/PRODUCT_CONTRACT.md): **Must read** before changing or reviewing capture flow, hotkey, OCR, clipboard, or menu behavior.
- [../../_standards/swift.md](../../_standards/swift.md): Swift engineering baseline.
- [../../_standards/workspace-docs/swift-docs/macos-app-baseline.md](../../_standards/workspace-docs/swift-docs/macos-app-baseline.md): completion checklist.

## Remote

Forgejo private `Max/TextSnap` (PascalCase native-app name). Do not put the intranet SSH URL in files that might go public later.

## App icon

- The editable masters are `design/app-icon/TextSnap-gradient.svg` and `TextSnap-gradient-foreground.svg`; the 1024px PNG master and all macOS asset-catalog sizes are generated from them.
- Keep the centered `T` and four selection corners as one visual identity. The background and corners may retain their blue-cyan-violet gradients, but the finished icon must remain fully opaque and pass the 24px and 48px contrast checks.
- Update both `TextSnap/Assets.xcassets/AppIcon.appiconset/` and `TextSnap/AppIcon.icon/` together; the former produces the bundled `AppIcon.icns`, while the latter preserves the new icon-source workflow.

## Engineering

- Generate the Xcode project with `xcodegen generate`; do not hand-edit `.xcodeproj`.
- Bundle ID: `top.caozc.TextSnap`. `LSUIElement`. No sandbox. No entitlements file (no special capabilities; screen capture is pure TCC + usage description).
- MacKit ≥0.1.4: Core, LaunchAtLogin, Lifecycle, StatusItem. Public distribution is the default (landed v0.2.0): Sparkle + notarized `.dmg` via `scripts/publish-release.py`; must never claim up to date.
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
