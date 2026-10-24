# Changelog

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
