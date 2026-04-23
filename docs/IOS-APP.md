# iOS App(苹果移动应用)

本文记录 Mira iOS App 的当前状态和启动方式。当前 iOS 侧已经接入 Relay(中继服务), PTY(伪终端), 远程 View(界面视图) 上传, 设备指标采样和浏览器快捷输入。

## 当前能力

已完成:

1. `ios/Mira/Mira.xcodeproj` Xcode project(Xcode 项目)。
2. SwiftUI(Swift 声明式界面框架) 首页, 对齐 Android(安卓系统) 控制页。
3. Relay URL(中继地址) 输入框, `Connect Relay` 和 `Disconnect` 按钮。
4. iOS 原生 relay 控制通道, 支持浏览器打开 PTY(伪终端) 会话。
5. App 自身窗口 View(界面视图) 通过 H.264(视频编码标准) + WebSocket(网页套接字) 上传到 `/ws/screen/device`。
6. CPU(中央处理器), 内存和网络速率指标每 1 秒通过 `device.metrics` 上报。
7. 浏览器远程画面支持点击, 文本输入, 粘贴, 复制, 全选, 清空, Backspace(退格) 和 Delete(删除)。
8. 根目录 `./mira-ios` 启动入口。

当前边界:

1. 只渲染 Mira App 自己的 key window(主窗口), 不使用 ReplayKit(苹果屏幕录制框架), 不采集系统全屏。
2. 远程点击使用公开 UIKit(苹果界面框架) 能力尽量激活命中的控件, 不做私有系统触摸注入。
3. 原生 C relay 的控制通道仍以 `ws://` 为主, Swift 层远程画面 WebSocket 支持 `ws://` 和 `wss://` URL(统一资源定位符)。

## 目录

```text
ios/
  Mira/
    Mira.xcodeproj/
    Mira/
      App/
        MiraApp.swift
        ContentView.swift
        MiraControlViewModel.swift
      NativeBridge/
        Mira-Bridging-Header.h
        MiraNativeStatus.swift
        MiraRemoteServices.swift
      Resources/
        README.md
```

Native bridge(原生桥接层) 还会引用:

```text
native/bridge/ios/mira_pty_ios_shim.h
native/bridge/ios/mira_pty_ios_shim.c
native/bridge/ios/mira_ios_relay.c
```

## 打开方式

### Xcode 打开

```bash
open ios/Mira/Mira.xcodeproj
```

在 Xcode 中选择:

```text
Mira -> iPhone 17 Pro -> Run
```

### 命令行启动

```bash
./mira-ios
```

脚本会执行:

1. 检查 Xcode 命令行工具。
2. 确保 iOS Simulator(iOS 模拟器) 已启动。
3. 使用 `xcodebuild` 构建 Debug(调试) 版本。
4. 使用 `simctl install` 安装到 booted simulator(已启动模拟器)。
5. 使用 `simctl launch` 打开 App。

可选环境变量:

```bash
MIRA_IOS_DEVICE="iPhone 17 Pro" ./mira-ios
MIRA_IOS_SCHEME="Mira" ./mira-ios
MIRA_IOS_BUNDLE_ID="com.vwww.mira.ios" ./mira-ios
```

## Relay 联调路径

1. 启动 Mira relay 服务端。
2. 在 iOS App 输入 Relay URL(中继地址) 并点击 `Connect Relay`。
3. 浏览器打开 relay console(控制台), 设备列表应出现 iOS 设备。
4. 选择设备后, 左侧显示 iOS App 自身画面, 右侧 Web Terminal(网页终端) 可打开 PTY 会话。
5. 底部 INFO(信息) 面板展示 CPU, MEM(内存), NET(网络) 动态曲线。
6. 在远程画面中点击输入框后, 可通过浏览器键盘输入文字, 粘贴, 复制, 全选和删除。

## 首页 UI 对齐 Android

Android 和 iOS 首页保持相同信息架构:

1. 左侧大标题 `Mira`。
2. 右侧小字 `by vw2x`。
3. 中间 Relay URL 输入框。
4. `Connect Relay` 按钮。
5. `Disconnect` 按钮。
6. monospaced(等宽字体) 状态文本。
