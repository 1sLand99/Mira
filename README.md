<p align="center">
  <img src="./apps/console/app/icon.svg" alt="MIRA icon" width="88" />
</p>

<h1 align="center">MIRA | AI-Powered Runtime Risk Analysis</h1>

<p align="center">
  <img src="https://img.shields.io/badge/Android-iOS-2f855a?style=flat-square" alt="Android and iOS" />
  <img src="https://img.shields.io/badge/Built--in-MCP-0f172a?style=flat-square" alt="Built-in MCP" />
  <img src="https://img.shields.io/badge/Built--in-Frida-dc2626?style=flat-square" alt="Built-in Frida" />
  <img src="https://img.shields.io/badge/Relay-Ready-2563eb?style=flat-square" alt="Relay Ready" />
</p>

<p align="center">
  面向 Android 与 iOS App 沙盒环境运行时风险分析工作台
</p>

<p align="center">
  <a href="./docs/GETTING-STARTED.md">Getting Started</a> ·
  <a href="./docs/">Documentation</a> ·
  <a href="./docs/THIRD-PARTY-NOTICES.md">Third-Party Notices</a>
</p>


## 核心能力

### AI 运行时风险发现

Mira 提供运行时真实沙盒视图, 且内置 frida 可实时执行任何 Java/Native 逻辑, 比动态 dex 更快

![claude 分析算法助手的 hook 痕迹](./docs/Area.gif)

### Android / iOS 双端工作台

实时画面, 沙盒 shell, 内置 Frida.

Android 暴露当前进程可见的 procfs 视角; iOS 则是模拟贴近 procfs 的进程视图, 但因为多了一层 syscall 翻译, 所以执行仍会有些卡顿.

<table>
  <tr>
    <th align="center">Android</th>
    <th align="center">iOS</th>
  </tr>
  <tr>
    <td><img src="./docs/android-remote-frida.png" alt="Android Remote Frida" /></td>
    <td><img src="./docs/ios-remote-frida.png" alt="iOS Remote Frida" /></td>
  </tr>
</table>

Mira 选择使用 Frida 作为动态分析切点, 而非自定义 AOP, linker, xdl 库等生产方案. 原因不是后者不够动态, 恰恰相反, 后者会更强, 但这类实现一旦被完整开源, 很容易被针对性研究, 复现和对抗, 反而会把项目本身变成攻击者的训练样本.

这也带来两个暂时的问题:
1. Frida 自身有进程注入特征. 预期在下个迭代周期中, 去掉更多的内置 frida 特征, 同时继续识别, 隔离和评估 Frida 痕迹.
2. frida 本身属性容易导致卡死. 短期只能杀进程重启, 长期我会排查并逐步优化体验(欢迎大家多多提 issue 和 pr).

为让文件系统做到和 Frida 体验的内置, Mira 做了以下动作:
1. Gadget 与 client 同时内置, 并删减 frida-cli 中无用的部分;
2. iOS 端 syscall 转换和交叉编译: 进一步完成了 iSH 适配, 将 Frida client runtime 预制进 rootfs, 通过端口直连进程内 Gadget, 再结合 hostfs, 轻量 procfs 和 `vm_region_recurse_64`, 并将真实进程视图映射到 `/mira/proc`, 让进程模拟终端中的分析体验尽量接近电脑中分析 android 的体验.

### 可选公网访问

配合 Relay, Mira 允许把一次临时授权会话快速扩展到公网, 好处就是可让大佬快速协助分析 🤝

### 持续沉淀 Skill 与 Case

后续每分析一个环境或框架, 都会沉淀三类资产:

1. 文章: 记录分析过程, 判断路径和关键坑点.
2. Case: 保留具体环境里的证据链, 不确定性和后续验证方向.
3. Skill: 把可复用的方法整理成 AI 可调用的检查流程.

希望可以沉淀一套可复查, 可迁移, 可被 AI 反复调用的移动安全分析方法. 如果你也关注 AI 如何提升移动安全开发效率, 可以 star 或 watch 这个项目.

### 兼容性提升中

当前公开验证主要覆盖 Android 13 与 iPhone X, 也会隔几次就遇到卡死的问题, 如果项目大家反馈比较有用的花, 更多设备和 Frida 版本组合会在后续持续补齐适配.

后续也会逐步引入 built-in agent 模式, 支持按服务端策略触发一轮本地自动分析与结构化上报. 更贴近真实对抗场景

## 授权研究边界

Mira 只面向授权研究和自有 App 分析

1. 只观察和交互 Mira 宿主 App 自身沙盒
2. 不控制其他 App
3. 不提供系统级远控能力
4. 不提供 root, jailbreak 绕过或系统沙盒绕过能力
5. 不提供生产 SDK 或静默后台控制能力 (所有会话都必须从 Mira App 内主动连接 Relay 后才存在)

## 致谢

Mira 的实现受到了不少优秀开源项目的启发, 在这里特别致谢:

1. [lamda](https://github.com/firerpa/lamda): Web 控制台的 UI 完全仿照 lamda 的工作台 UI.
2. [Termux](https://github.com/termux/termux-app): Android 侧终端体验与可扩展终端生态给了 Mira 很多基础思路, 但注入的思路不同;
3. [iSH](https://github.com/ish-app/ish): iOS 侧 Linux shell 体验, 用户态仿真与 syscall 转换路径为 Mira 的 iOS 运行时工作台提供了重要参考.

感谢这些开源项目和维护者持续推动移动端终端, 自动化与研究基础设施的演进.

## 开源许可证

Mira 使用 `GPL-3.0-only`, 第三方组件按各自上游许可证分发, 详见 `docs/THIRD-PARTY-NOTICES.md`.

## 文档

详细文档见 `docs/`, 安装与使用入口见 `docs/GETTING-STARTED.md`.
