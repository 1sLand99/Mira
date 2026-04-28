# 开源 | MIRA：内置 Frida，让 AI 实时分析 Android/iOS 运行时风险

---

## 背景

移动安全设备测风险环境识别有个老问题：工具闭源或分散 (一旦开源就迎来针对性对抗)、经验难以复用, 且不同的风险环境都有自己的针对性隐藏方案, 基本发个新版就要从头分析一遍.

更关键的是，AI 想介入分析流程，但它看不到设备运行时的真实状态——只能靠你粘贴日志、截图描述，信息损耗极大。

MIRA 想解决的就是这个：**让 AI 直接连进设备，实时看到运行时环境，然后告诉你哪里有问题**。

---

## 核心能力

**Android/iOS 双端工作台**
动态集成 busybox 命令集和 Frida gadget，提供交互式终端，可直接操作进程视角的 procfs（iOS 侧为 syscall 模拟实现）。

**内置 mira-mcp**
通过 MCP 协议将设备运行时能力暴露给 AI，Claude 等模型可以直接调用 Frida 执行脚本、读取进程信息、分析环境特征，不需要人工中转。

**经验沉淀**
每分析一个环境，沉淀三类资产：**文章**（分析过程与关键坑点）、**Case**（证据链与后续验证方向）、**Skill**（可被 AI 复用的检测流程）。

---

## 四个典型场景

### 场景一：文件系统侧信道——stat 返回值差异

这是一个很容易被忽略的信息泄露点。

```
mira $ stat com.xiwei.logistics
stat: can't stat 'com.xiwei.logistics': No such file or directory

mira $ stat com.wlqq
stat: can't stat 'com.wlqq': Permission denied
```

两条命令，两个不同的错误。`No such file or directory` 说明路径根本不存在，`Permission denied` 说明路径**存在，但当前进程没有权限访问**。

这个差异意味着：通过 stat 的返回值，即使没有 root，也能枚举出设备上安装了哪些 App 的沙盒目录——这本质上是一个未授权的信息探测面。

进一步，stat 还能看到其他真实路径的元信息（权限、属主等），可以从中推断系统的 root 状态。比如 `/data/adb` 这类路径，如果返回 `Permission denied` 而非 `No such file`，大概率说明 Magisk 或类似框架已经在那里留下了痕迹。

*[GIF：AI 自动执行 stat 枚举，识别差异并给出分析结论]*

---

### 场景二：iOS 越狱痕迹检测

iOS 侧，MIRA 在 `/mira/` 下构建了一个类 Android 的文件系统视图，可以用熟悉的命令集操作 iOS 路径。

```
mira $ stat /mira/Applications/Cydia.app
mira $ stat /mira/var/lib/cydia
mira $ stat /mira/private/var/lib/cydia
mira $ stat /mira/etc/apt
mira $ stat /mira/var/lib/dpkg/status
```

上面这几条路径是 Cydia 及其依赖的典型落点。逐一 stat，返回值不再是统一的 `No such file`——说明 Cydia 的残留还在，设备被越狱过。

即使 Cydia 本体已经卸载，dpkg 的数据库、apt 的配置目录往往还在。AI 综合多个路径的 stat 结果，可以做出置信度更高的越狱判断，而不是依赖单一指标被轻易绕过。

*[GIF：AI 批量检测路径，发现 Cydia 残留，输出越狱置信度判断]*

---

### 场景三：模拟器环境识别

*[待补充：具体命令和输出]*

*[GIF：AI 识别模拟器特征，输出检测结论]*

---

### 场景四：LSP 注入特征检测

通过 mira-mcp，AI 可以直接调度 Frida 执行任意 Java/Native 逻辑。

这里以检测 LSPosed/Xposed 框架注入特征为例。Xposed 框架会在进程中留下特定的类和方法，Frida 挂上去直接枚举即可：

*[GIF：AI 调用 Frida，枚举进程内 LSP 注入特征，输出检测结果]*

LSPosed 相比老 Xposed 做了一定的隐藏，但在运行时仍有可观测的痕迹。结合 procfs 里的 maps 信息，可以进一步确认注入深度。

---

## 经验沉淀机制

上面每个场景，分析完之后都会沉淀成三类资产：

- **文章**：这次分析的过程、踩的坑、关键结论
- **Case**：证据链截图、命令输出、后续可验证的方向
- **Skill**：把检测逻辑封装成 AI 可直接调用的流程，下次换个 App 直接复用

长期来看，每分析一个环境，工具库就厚一点。

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
