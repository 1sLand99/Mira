# 安装与使用

这份文档承接 README 中移出的安装, 构建, 连接和接入步骤, 方便把项目主页保持为产品化介绍页面.

## 1. 启动 Relay 和浏览器工作台

局域网演示优先使用:

```bash
./mira-local-web
```

电脑浏览器打开:

```text
http://localhost:8765
```

Android 或 iOS 端填写:

```text
http://<电脑局域网 IP>:8765
```

如果需要远程临时调试链路, 可以使用:

```bash
./mira-web
```

`./mira-web` 会启动 Mira Relay, 构建 `apps/console`, 并通过 cpolar 输出可访问的 Browser URL(浏览器地址) 和移动端 Relay URL(中继地址). 详细说明见 `REMOTE-RELAY.md`.

## 2. 构建并启动 Android App

```bash
./gradlew :mira-app:assembleDebug
adb install -r android/app/build/outputs/apk/debug/mira-app-debug.apk
adb shell am start -n com.vwww.mira/.MainActivity
```

Android shell 的默认路径和工作目录是:

```text
/data/user/0/com.vwww.mira/files/usr/bin/sh
/data/user/0/com.vwww.mira/files/home
```

原生 PTY 层已经整理为 Android 和 iOS 可共享的 POSIX(可移植操作系统接口) 架构, 详细边界见 `NATIVE-ARCHITECTURE.md`.

## 3. 构建并启动 iOS App

命令行构建并启动 iOS Simulator(模拟器):

```bash
./mira-ios
```

也可以直接用 Xcode 打开:

```bash
open ios/Mira/Mira.xcodeproj
```

iOS 侧已经接入 Relay, PTY, Mira App 自身 key window 画面上传, 设备指标采样, `/mira` app-view root 和 `/mira/proc` simulated process view(模拟进程视图). 详细说明见 `IOS-APP.md`.

## 4. 连接移动端

1. 打开 Android 或 iOS 端 Mira App 首页.
2. 填写 Relay URL.
3. 点击 `Connect Relay`.
4. 回到浏览器等待设备列表出现.
5. 点击 `Open Terminal` 打开 App 沙盒会话.

服务端通过 control WebSocket(控制通道) 向设备发送 `session.open` 请求, 设备收到后才创建 PTY 并主动连接服务端.

## 5. MCP 接入

启动 Relay Server 后, MCP client 以 stdio(标准输入输出) 方式启动:

```bash
python3 -m mira.mcp.server \
  --relay http://127.0.0.1:8765
```

核心工具包括:

1. `mira_list_devices`: 读取已连接 Relay 的设备.
2. `mira_open_terminal`: 打开远程 PTY session(会话).
3. `mira_run_command`: 在同一个 PTY 中执行命令并读取输出.
4. `mira_collect_snapshot`: 采集第一轮 Android 分析快照.
5. `mira_close_terminal`: 关闭会话并清理设备侧临时状态.

如果要让 Codex 做移动风险分析, 可以让它读取 `skills/mira-mobile-risk-review`, 再针对当前授权会话生成观察步骤和 Case. 完整配置见 `MCP.md`.

## 6. CLI

```bash
./mira-cli devices
./mira-cli run 'pwd'
./mira-cli shell
```

`mira-cli` 直接使用 Relay HTTP 和 WebSocket, 不经过 MCP. 默认连接 `http://127.0.0.1:8765`, 也可以指定 Relay:

```bash
./mira-cli --relay https://example.invalid devices
./mira-cli run 'echo hello' --relay https://example.invalid
```

`shell` 会进入交互式远程 PTY, 按 `Ctrl-]` 退出本地 CLI 会话并关闭远程 session.

## 7. 使用须知

使用 Mira 即表示你确认:

1. 只在自己拥有或已获得明确授权的 App, 设备和运行环境中使用 Mira.
2. 不使用 Mira 控制其他 App, 绕过平台保护, 访问未授权数据, 或执行系统级远程控制.
3. Mira 不提供生产 SDK, 静默后台控制, root, jailbreak 绕过, 或跨 App 自动化能力.
4. 所有会话都必须从 Mira App 内主动发起, 且仅限 Mira 自身 App 沙盒和普通第三方 App 权限范围.
5. 使用者需自行遵守适用法律, 平台规则和内部安全规范.
