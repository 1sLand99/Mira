<p align="center">
  <a href="./README.md">English</a> · 简体中文
</p>

<h1 align="center">Mira</h1>

<p align="center">
  面向 Android 与 iOS 的 AI 原生移动运行时风险发现工作台.
</p>

![claude 分析算法助手的 hook 痕迹](./docs/Area.gif)

## 为什么安全团队会用 Mira

- **更快的防护反馈闭环**: 从怀疑到真实运行时证据, 不必为每一轮验证都重搭割裂的实验链路.
- **AI 驱动的加固提效**: 通过 `mira-mcp` 接入 Codex 或 Claude, 把原始运行时观察更快转成检查步骤, Case 和防护改进方向.
- **覆盖双端移动栈的统一工作台**: 用同一套 Relay 工作流承接 Android 与 iOS 的发现, 验证和后续跟进.

## 核心能力

### 实时运行时风险发现

展示运行时真实沙盒环境, 内置 Frida 实时执行 Java / Native 逻辑, 直接暴露移动防护真正关心的信号, 比如 hook 痕迹, 环境指纹, 进程状态和运行时验证证据.

同时提供 mira-mcp, 让 Codex 或 Claude 可以进入同一个实时会话协助分析环境风险.

Claude Desktop 和 Codex 的接入方式见 [`docs/MCP.md`](./docs/MCP.md).

### 覆盖 Android 与 iOS 的统一防守工作台

动态集成 busybox 命令集和 Frida gadget, 交互式分析进程视角 procfs, iOS 为 syscall 模拟实现, 让同一套验证流程覆盖双端移动栈, 不必拆成两套割裂的工具模型.

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

> 当前内置删减版 Frida gadget, 存在注入特征和偶发崩溃, 下个迭代会逐步去特征并优化稳定性.

### Relay 驱动的专家协作链路

配合 Relay, 可通过[脚本](./mira-web)将临时授权会话扩展到公网, 适用于云手机等不便 adb 的场景, 也适合专家协作, 远程复核, 以及多人围绕同一份实时运行时证据快速协同.

![使用 cpolar 方案公网访问](./docs/public-deploy.png)

## 防守工作流

1. 用 `./mira-local-web` 启动局域网 Relay, 或用 `./mira-web` 暂时开放公网访问.
2. 在 Android 或 iOS 端启动 Mira App 并连接到 Relay.
3. 在浏览器工作台和远程 PTY 中检查 App 的真实运行时状态.
4. 通过 MCP 把 Codex 或 Claude 接入同一个实时会话, 加速假设生成, 验证和证据采集.
5. 把结果转成可复用的防护检查流程, Case 和后续加固动作.

## 快速开始

### 启动 Relay 和浏览器工作台

```bash
./mira-local-web
```

如果需要临时公网共享:

```bash
./mira-web
```

### Android 自动化链路

```bash
MIRA_ANDROID_RELAY_URL="http://<host-ip>:8765" \
./mira-android
```

### iOS 模拟器链路

```bash
./mira-ios
```

### MCP 服务

```bash
python3 -m mira.mcp.server \
  --relay http://127.0.0.1:8765
```

更完整的安装, 启动和排障说明见 [`docs/GETTING-STARTED.md`](./docs/GETTING-STARTED.md).

## 仓库结构

- `android/`: Android App 与平台接入层.
- `ios/`: iOS App, 基于 iSH 的运行时桥接和设备工作流.
- `apps/console/`: Web 控制台 UI.
- `mira/`: Relay, MCP 服务端和 Python CLI 实现.
- `native/`: 双端共享的原生运行时组件.
- `docs/`: 安装说明, 架构文档和平台说明.
- `tools/`: 构建, 打包和辅助脚本.

## 授权研究边界

Mira 只面向授权研究和自有 App 分析:

1. 只观察和交互 Mira 宿主 App 自身沙盒.
2. 不控制其他第三方 App.
3. 不提供系统级远控能力.
4. 不提供 root / jailbreak 绕过或系统沙盒绕过能力.
5. 不提供生产 SDK 或静默后台控制能力.

## 致谢

- [lamda](https://github.com/firerpa/lamda): Web 控制台 UI 完全仿照 lamda 工作台.
- [Termux](https://github.com/termux/termux-app): Android 侧终端体验与可扩展终端生态.
- [iSH](https://github.com/ish-app/ish): iOS 侧 Linux shell 与 syscall 转换路径.

## 开源许可证

`GPL-3.0-only`.

第三方组件按各自上游许可证分发, 详见 [`docs/THIRD-PARTY-NOTICES.md`](./docs/THIRD-PARTY-NOTICES.md).
