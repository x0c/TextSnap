# Changelog

## 0.2.9

- Fix the macOS 27 Vision E5RT recognition failure (`CRImageReaderError.e5rtError(..., 13)`) and startup freeze by switching to a `512×256` bilingual warm-up image, padding small crops (`< 256×160`), selecting explicit `.gpu` → `.cpu` compute devices with sRGB fallback, and automatically recovering via a headless `--ocr-once` worker process if E5RT is ever poisoned.
- Keep global shortcuts responsive across captures and errors: release the in-flight lock before modal alerts (and dismiss stale alerts on a new press), run `/usr/sbin/screencapture` asynchronously with `stderr` error classification and sleep/session-resign cancellation, suspend active hotkeys while recording, add coalesced post-wake/unlock re-assertion, route `⌘Q` through the termination guard, and avoid stale results in Shortcuts (`CaptureTextIntent`).
- Add dual-sink, privacy-safe observability logs (`~/.config/textsnap/logs/textsnap.log`, mode `700`/`600`, 2 MB × 3 rotation, plus Unified Logging `top.caozc.TextSnap`) recording startup state, capture correlation IDs, trigger source, blocked-phase diagnostics, selector dimensions/stderr, and OCR compute device/timing without logging recognized text or clipboard contents.

### 简体中文

- 修复 macOS 27 下 Vision 持续报错（`CRImageReaderError.e5rtError(..., 13)`）与启动卡死问题：启动预热图改为 `512×256` 中英双语图像，为小尺寸框选（`< 256×160`）自动补白画布，显式优先 `.gpu` → `.cpu` 计算设备并支持 sRGB 归一化回退；若进程内仍发生 E5RT 异常，自动切到无界面 `--ocr-once` 子进程恢复识别。
- 解决全局快捷键唤不出来的问题：弹出失败/空结果提示窗前释放采集锁（新触发自动关闭旧弹窗），改用异步 `screencapture` 监听 `stderr` 区分真实报错与 Esc 取消并在休眠/锁屏时自动取消卡住的框选，录制快捷键时暂停当前热键，唤醒/解锁后防抖重注册，修复设置窗打开时 `⌘Q` 无法退出的问题，并确保快捷指令不会返回旧结果。
- 新增隐私安全的双通道可观测性日志（`~/.config/textsnap/logs/textsnap.log`，目录 700 / 文件 600，单文件 2 MB 保留 3 份，并同步输出到系统统一日志 `top.caozc.TextSnap`），记录启动状态、请求编号、触发来源、丢弃原因与阶段耗时、截图尺寸/错误输出及 OCR 设备与耗时，绝不记录识别文字或剪贴板内容。

## 0.2.8

- Stop the Settings recovery window from opening at login. TextSnap now classifies the launch after macOS has delivered its launch event, so a login-item start stays silent even while the menu-bar icon is hidden; reopening the app yourself still presents Settings.
- Keep the hidden menu-bar icon recoverable: a user launch from Finder, Dock or Spotlight presents Settings, and the capture shortcut keeps working.

### 简体中文

- 修复开机登录时自行弹出设置窗的问题。改为在系统送达启动事件后判定启动来源，登录项启动保持静默，即使菜单栏图标已隐藏；你主动再次打开应用时仍会显示设置窗。
- 菜单栏图标隐藏后仍可恢复：从 Finder、Dock 或 Spotlight 打开应用会显示设置窗，识别快捷键照常可用。

## 0.2.7

- Replace the menu-bar capture symbol with a silhouette of the App Icon's paired opening quotation marks. The system tints the transparent template for light and dark menu bars.
- Keep left-click capture, the right-click menu and icon visibility behavior unchanged.

### 简体中文

- 菜单栏图标换为应用图标中成对开引号的剪影；透明模板由系统着色，适配浅色和深色菜单栏。
- 左键框选、右键菜单和图标显隐行为保持不变。

## 0.2.6

- Add Hide Menu Bar Icon to the status menu and a matching Show Menu Bar Icon switch in Settings. The preference survives restart without changing your capture shortcut.
- Keep capture available through the shortcut while hidden. Reopening TextSnap from Applications or Spotlight brings back the same Settings window so you can restore the icon; login launches remain silent.

### 简体中文

- 右键菜单新增“隐藏菜单栏图标”，设置中新增对应的“显示菜单栏图标”开关。重启后保留显隐选择，不改变原有识别快捷键。
- 图标隐藏后仍可用快捷键识别；从“应用程序”或 Spotlight 再次打开 TextSnap，会显示同一设置窗以恢复图标。开机自启动仍保持静默。

## 0.2.5

- Register the global shortcut before any other launch work, retry failed registrations with backoff, and re-assert it after wake, unlock, session activation and during the first 90 seconds of a login session. The shortcut no longer stays dead while the system settles.
- Move text recognition off the main thread, resolve Vision's language support once per process, and pre-warm the recognition model at launch. The first recognition after launch no longer freezes the whole app for one to two minutes.
- Start Sparkle and read launch-at-login state off the launch path; status menus now use a cached, asynchronously refreshed value.
- Add privacy-safe diagnostics for launch, shortcut and capture timing. Recognized text and clipboard contents are never logged.

### 简体中文

- 全局快捷键改为启动时的第一件事；注册失败会按退避重试，并在唤醒、解锁、会话激活以及登录后前 90 秒内重新注册。系统还在收尾时，快捷键不会再一直失灵。
- 文字识别移出主线程，Vision 语言能力每进程只查询一次，并在启动后预热识别模型。启动后的首次识别不会再让整个应用卡住一两分钟。
- Sparkle 与开机自启状态查询移出启动关键路径；状态菜单改用缓存值并异步刷新。
- 增加不涉及隐私的启动、快捷键和识图耗时诊断日志；绝不上报识别文字或剪贴板内容。

## 0.2.4

- Replace the application icon with refined blue glass quotation marks on a pale silver background.
- Preserve the glass highlights and cast shadows across all application-icon sizes; retain the existing menu-bar capture symbol.

### 简体中文

- 应用图标换为浅银色背景上的蓝色玻璃双引号，精修轮廓、高光与小尺寸辨识度。
- 各尺寸应用图标保留玻璃高光与投影；菜单栏框选符号保持现有设计。

## 0.2.3

- Reorganize Settings into a compact native grouped form with aligned controls and an integrated app/version/update row.
- Preserve shortcut recording, screen-recording status, login behavior and last-result actions; use the native Settings scene and size it to its content.
- Remove factory-shortcut instructions from the empty result state so custom shortcuts stay accurate.

### 简体中文

- 设置改为紧凑的原生分组表单，控件对齐，应用、版本和更新操作集中在底部。
- 保留快捷键录制、屏幕录制权限、开机自启和上次结果操作；使用系统设置场景并按内容确定窗口高度。
- 空状态去掉写死的默认快捷键，避免自定义快捷键后出现错误说明。
