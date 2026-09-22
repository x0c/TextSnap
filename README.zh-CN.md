**语言：** [English](README.md) | 简体中文

# TextSnap

<img src="docs/images/app-icon.png" width="96" height="96" alt="TextSnap 应用图标">

按一下快捷键，在屏幕上框选一块区域，里面的文字就进入剪贴板。macOS 菜单栏识字工具，全程调用本机 Apple Vision —— 不留截图文件，不联网，不用账号。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Latest release](https://img.shields.io/github/v/release/x0c/TextSnap)](https://github.com/x0c/TextSnap/releases/latest)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-black)

![TextSnap 设置窗口](docs/images/settings.png)

## 功能

- **快捷键框选** —— 出厂 `⌘⇧2`，可重录、可清除、可恢复出厂；和系统冲突的组合会明确拒绝并说明原因。
- **系统框选器** —— 你早就熟悉的十字准星；`Esc` 静默取消。
- **本机识别** —— Apple Vision，精确模式，带语言纠错。没有任何数据离开你的 Mac。
- **成功零打扰** —— 认出的文字直接进剪贴板并响一声，不弹结果窗。
- **失败说人话** —— 认不出或没给权限时弹一次说明窗，告诉你怎么办，从不静默失败，也从不反复重试。
- **菜单栏原生** —— 左键直接框选，右键出菜单；无程序坞图标，首次启动保持静默。
- **可自动化** —— `Capture Screen Text` 意图把核心动作暴露给快捷指令和 Spotlight。

## 支持的平台

仅 macOS 26（Tahoe）及更高，Apple 芯片与 Intel 均可。TextSnap 依赖 macOS 专有能力（Vision、本机框选授权、菜单栏），没有 Windows / Linux 版。

## 安装

从 [最新版本](https://github.com/x0c/TextSnap/releases/latest)下载已签名的 `.dmg`，打开后把 TextSnap 拖进 Applications，启动一次。首次启动是静默的 —— 去菜单栏找取景框图标，然后按 `⌘⇧2`。

第一次按快捷键会申请屏幕录制权限；没有它，TextSnap 看不见你框选的区域。如果之前拒绝过，去设置里一键跳回系统设置打开即可。

### 从源码构建

需要 Xcode 26 与 [xcodegen](https://github.com/yonaskolb/XcodeGen)：

```bash
xcodegen generate
xcodebuild -project TextSnap.xcodeproj -scheme TextSnap -configuration Release \
  -destination 'platform=macOS' build
```

## 用法

1. 按 `⌘⇧2`（或左键点菜单栏图标，或从菜单里选框选）。
2. 拖出区域。松手即识别，`Esc` 取消。
3. 直接粘贴 —— 文字已经在剪贴板里了。

右键点菜单栏图标进设置：改快捷键、看授权状态、开关机自启、复制上一次的结果。设置存在 `~/.config/textsnap/settings.json`；识别出的文字只放内存，从不写盘。

## 常见问题

**提示没有权限，怎么办？**
设置 → 权限 → 打开系统设置，在屏幕录制里勾上 TextSnap，回来后应用会自动重检。

**框选了但说没认出文字？**
那块区域大概没有可读文字（或太小看不清）。一次说明窗讲清楚，重按快捷键框得更贴一点就行。

**会把我的屏幕上传到哪吗？**
不会。框调用的是 `/usr/sbin/screencapture`，识别用的是本机 Apple Vision。没有网络代码，也没有历史库。

**会自动更新吗？**
不会。没有更新源，「检查更新」会如实告诉你。新版本在 GitHub releases 发布，想升就去下新的 `.dmg`。

**快捷键按了没反应 / 说被占用？**
说明那个组合已经被别的 App 占了 —— 设置里会明确告诉你，而不是静默失败。换一个带修饰键的组合；`⌘⇧3/4/5/6` 是系统截图家族，动不了。

## 许可证

[MIT](LICENSE)
