# 开源 | MIRA：内置 Frida，让 AI 实时分析 Android/iOS 运行时风险

---

## 背景

移动安全设备测风险环境识别有个老问题：工具闭源或分散 (一旦开源就迎来针对性对抗)、经验难以复用, 且不同的风险环境都有自己的针对性隐藏方案, 基本发个新版就要从头分析一遍.

更关键的是，AI 想介入分析流程，但它看不到设备运行时的真实状态——只能靠你粘贴日志、截图描述，信息损耗极大。

MIRA 想解决的就是这个：**让 AI 直接连进设备, 实时看到运行时环境, 执行任意逻辑, 然后告诉你哪里有问题**。

---

## 核心能力

**Android/iOS 双端工作台**
动态集成 busybox 命令集和 Frida gadget，提供交互式终端，可直接操作进程视角的 procfs（iOS 侧为 syscall 模拟实现）。

| Android | iOS |
| --- | --- |
| ![](./android-remote-frida.png) | ![](./ios-remote-frida.png) |

**内置 mira-mcp**
通过 MCP 协议将设备运行时能力暴露给 AI，Claude 等模型可以直接调用 Frida 执行脚本、读取进程信息、分析环境特征，不需要人工中转。

![](./mira-mcp-claude.png)

---

## 场景演示

### 场景一: 利用 Unix shell 能力快速分析隐藏痕迹

该部分展现 AI 利用 Mira Unix shell 的方便之处

熟悉 linux 的同学知道, 在同一个没有读权限的目录下, stat 命令存在有两种截然不同的报错: `No such file or directory` 指路径根本不存在. 而 `Permission denied` 是指路径**存在，但当前进程没有权限访问**。

这是一个很大的发现, 因为这意味着：通过 stat 的返回状态, 即使只有第三方 App 的权限, 也能枚举设备上安装的风险 App! 如下图演示, 检测出了 android 设备上狐狸面具的安装

![](./stat-magisk.gif)

iOS 侧也来下, 笔者在 iPhone X 环境安装了 Cydia, 因为没研究过 Cydia 实现, 不知道可能的痕迹, 但这个 AI 最清楚了, 于是让 AI 自己来对接操作

因为 iOS 的安全限制, Mira 暂时只能通过 syscall 翻译的方式模拟 shell (MIRA 在 `/mira/` 下 mount 了类 Android 的文件系统视图和进程视图, 可以用熟悉的命令集操作 iOS 路径)

![](./cydia-ios.gif)

不止是很轻松的发现了 Cydia, 还发现了近 10 种相关风险工具留下的具体痕迹, 输出了详尽的报告

对 AI 来说, Mira 提供了近似 CLI 的体验, 这是 AI 最擅长的场景, 且 Mira 已内置 busybox 的所有命令, 后续还会继续适配和增加

---

### 场景二：LSP 注入特征检测

Mira 内置 Frida Gadget 与适配好的 frida-cli, 换句话说, 通过使用 mira-mcp, AI 可动态调用 Frida 执行任意 Java/Native 逻辑

以检测 LSPosed 框架为例, 试想你分析源码, 看到 LSPosed 会通过自己的 ClassLoader 加载类, 那 AI 一下就会反应过来 classloader 会不会有特征? 换做之前, 写代码验证的路径很长, 甚至中间可能还对 Java 层做了对抗, native 层你又不怎么会写的时候, 现在有了 frida 内置能力, 直接一句话就找到了 3 种奇怪的 ClassLoader 注入特征!

![](./Area.gif)

未来 Mira 会提供通用能力, 允许提取内存上传, 你甚至可以看看这个 `InMemoryDexClassLoader` dex 具体注入的什么逻辑! (即将实现)

---

### 场景三：摇人分析

Mira 基于 cpolar 提供了临时公网服务, 对于海外环境, 后续还会提供 Cloudflare 临时公网服务

换句话说, 你可以更方便的请教他人, 直接打开公网 url 使用命令行和 Frida 即可请他分析环境特征

![](./public-deploy.png)

---

## 经验沉淀机制

上面每个场景，分析完之后都会沉淀成三类资产：

- **文章**：这次分析的过程、踩的坑、关键结论
- **Case**：证据链截图、命令输出、后续可验证的方向
- **Skill**：把检测逻辑封装成 AI 可直接调用的流程，下次换个 App 直接复用

长期来看，每分析一个环境，工具库就厚一点 (仍在沉淀中, 包括这篇文章也会加入 commit)

---

## 部署

两种接入方式：

- **本地模式**：adb 直连，适合日常分析
- **Relay 公网模式**：通过脚本将会话扩展到公网，适合云手机或者邀请别人一起分析

详见 [Getting Started](./GETTING-STARTED.md)。

---

## 边界说明

MIRA 只面向授权研究和自有 App 分析。工具本身只观察和交互 Mira 宿主 App 自身沙盒，不控制其他 App，不提供 root/jailbreak 绕过能力，不提供生产 SDK 或静默后台控制能力。

---

开源地址：[GitHub - MIRA](https://github.com/)（换成实际地址）

欢迎 star / watch，有问题或者新的检测场景欢迎提 issue 或 PR，一起把经验库做厚。
