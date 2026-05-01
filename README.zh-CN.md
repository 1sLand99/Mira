#### [English](./README.md) | 简体中文

<div align="center">
  <img src="./apps/console/app/icon-round.png" alt="Mira icon" width="160" />
</div>

# Mira

面向 Android 与 iOS 的 AI 原生移动运行时风险发现工作台.

<p align="center">
  <img src="https://img.shields.io/badge/analysis-AI--native-0f172a?style=flat-square" alt="AI-native analysis" />
  <img src="https://img.shields.io/badge/platform-Android%20%2B%20iOS-2f855a?style=flat-square" alt="Android and iOS" />
  <img src="https://img.shields.io/badge/execution-live%20logic-2563eb?style=flat-square" alt="Live logic execution" />
</p>

## Features

- **AI 辅助分析**: 通过 `mira-mcp` 接入 Codex 或 Claude, 让 AI 和研究者同时检查同一个实时会话.
- **双端运行时覆盖**: 用同一套工作流覆盖 Android 与 iOS, 不必拆成两套割裂的分析工具链.
- **任意逻辑动态执行**: 通过内置 Frida 链路执行 Java 与 Native 逻辑, 直接在运行中的 App 内验证假设.
- **面向防护的证据采集**: 暴露 hook 痕迹, 环境指纹, 进程状态和运行时验证信号, 服务于移动加固与风险复核.

## Getting Started

- **本地 Relay**: 用 `./mira-local-web` 启动本地浏览器工作台.
- **Android 工作流**: 使用 `MIRA_ANDROID_RELAY_URL="http://<host-ip>:8765" ./mira-android` 完成构建, 安装和自动连接.
- **iOS 工作流**: 模拟器场景使用 `./mira-ios`, 真机链路见 [`docs/GETTING-STARTED.md`](./docs/GETTING-STARTED.md).
- **AI 接入**: 启动 `python3 -m mira.mcp.server --relay http://127.0.0.1:8765`, 再从 Codex 或 Claude 连接.

## Workflow

1. 启动 Relay 并打开浏览器工作台.
2. 在 Android 或 iOS 上连接 Mira App.
3. 打开远程 PTY, 检查真实运行时状态.
4. 动态执行逻辑, 采集证据, 验证风险假设.
5. 将结果沉淀为可复用检查步骤和加固后续动作.

## Runtime Views

<table>
  <tr>
    <th align="center">Android</th>
    <th align="center">iOS</th>
  </tr>
  <tr>
    <td>
      <img src="./docs/android-remote-frida.png" alt="Android Remote Frida" />
      <div align="center"><sub>Android 侧远程 shell 与运行时分析视图.</sub></div>
    </td>
    <td>
      <img src="./docs/ios-remote-frida.png" alt="iOS Remote Frida" />
      <div align="center"><sub>iOS 侧对应的 PTY 与 Frida 分析链路.</sub></div>
    </td>
  </tr>
</table>

## Public Relay Access

![使用 cpolar 方案公网访问](./docs/public-deploy.png)

配合 Relay, 可将临时授权会话扩展到公网, 适用于云手机, 专家协作和实时证据交接.

## Research Boundaries

1. Mira 只观察和交互 Mira 宿主 App 自身沙盒.
2. Mira 不控制其他第三方 App.
3. Mira 不提供系统级远控能力.
4. Mira 不提供 root / jailbreak 绕过或系统沙盒绕过能力.
5. Mira 不提供生产 SDK 或静默后台控制能力.

## Documentation

- [`docs/GETTING-STARTED.md`](./docs/GETTING-STARTED.md)
- [`docs/MCP.md`](./docs/MCP.md)
- [`docs/IOS-APP.md`](./docs/IOS-APP.md)
- [`docs/NATIVE-ARCHITECTURE.md`](./docs/NATIVE-ARCHITECTURE.md)
- [`docs/THIRD-PARTY-NOTICES.md`](./docs/THIRD-PARTY-NOTICES.md)

## Acknowledgements

- [lamda](https://github.com/firerpa/lamda): Web 控制台 UI 设计参考 lamda 工作台.
- [Termux](https://github.com/termux/termux-app): Android 侧终端体验与可扩展终端生态.
- [iSH](https://github.com/ish-app/ish): iOS 侧 Linux shell 与 syscall 转换路径.

## License

`GPL-3.0-only`.
