---
created: 2026-04-21T03:36:43.519Z
title: Expand Android device workbench
area: general
files:
  - README.md
---

## Problem

本轮讨论确认 Mira 不应只停留在 Android 环境风险检测脚本集合, 而可以演进成一个 Android Device Workbench(安卓设备工作台). 关键洞察是 Android 设备可以自己成为一个可观测, 可交互, 可编排的运行节点. 第一阶段仍然必须收敛到 Web Terminal(网页终端) MVP(最小可行产品), 但后续想法需要先沉淀下来, 避免新开对话后遗忘。

已经确认的第一步是用 PTY(伪终端) + WebSocket(网页长连接协议) + xterm.js(浏览器终端组件) 替代 Termux 的 Android TerminalView(安卓终端视图) 展示层. 也就是服务端持有 PTY master(主端), shell(命令解释器) 连接 PTY slave(从端), 浏览器只负责展示和输入。

## Solution

后续能力按优先级沉淀为以下 TODO, 不要在 Web Terminal MVP 里一次性实现:

1. Web Terminal MVP: 在 Termux 或 Android 设备侧启动 mira-server, 后端创建持久 PTY session(会话), 浏览器通过 WebSocket 实时输入输出, 支持 resize(窗口尺寸同步), 能运行 `pwd`, `ls`, `echo hello` 等交互命令。
2. Live UI(实时界面): 把自己 App 的 UI(用户界面) 截成 Bitmap(位图), 编码为 JPEG/WebP(图片压缩格式), 通过 WebSocket 推到浏览器右侧面板. 第一版低帧率即可, 例如 1-10 fps(每秒帧数)。
3. Device Metrics(设备指标): 上传 CPU(处理器) 占用, memory(内存) 占用, thread(线程) 数量, fd(file descriptor, 文件描述符) 数量, network(网络) 流量, battery(电池) 状态和 temperature(温度)。
4. App Runtime(应用运行态): 展示 package(包名), pid(进程 ID), 当前 Activity(页面), View Tree(视图树), logcat(日志系统) 摘要, crash(崩溃) 堆栈和 ANR(Application Not Responding, 应用无响应) 线索。
5. Probe Report(探针报告): 把 Root(提权环境), emulator(模拟器), hook(运行时劫持), injection(注入), suspicious process(可疑进程) 和 system property(系统属性) 检测结果统一输出 JSON(结构化数据), 再由浏览器展示 findings(风险发现)。
6. Automation Tasks(自动化任务): 增加 scheduler(调度器), 支持定时采集设备状态, App 启动后自动抓 logcat, crash 后自动保存堆栈和设备状态, 风险信号变化后自动二次验证。
7. Agent Analysis(智能体分析): 把 Probe 输出, 指标和日志交给 Agent 解释, 输出风险等级, 证据链, 误报说明和下一步验证建议。
8. Multi Device(多设备): 后续支持多个 Android 设备注册到同一个 Web Console(网页控制台), 形成设备列表, 会话切换和批量巡检。

第一版产品布局可以暂存为:

```text
Browser Console
├─ Left: Web Terminal
├─ Right Top: Live UI
├─ Right Middle: Metrics
└─ Right Bottom: Findings
```

实现顺序必须保持克制:

1. 先完成 Web Terminal MVP.
2. 再补 TODO 里的数据总线和事件协议.
3. 再逐步接 UI, metrics, logcat, probe 和 automation.
