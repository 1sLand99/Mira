# Android 模拟器 proc audit 侧信道暴露 qemu SELinux 上下文

## 1. 检测对象

从第三方 Mira App 沙箱 shell 里检测 Android 模拟器环境, 使用 `/proc/<pid>` 访问触发 audit log(日志审计记录)作为侧信道.

## 2. 初始怀疑

普通模拟器可以通过 `ro.kernel.qemu=1` 这类直接 property(系统属性)检测, 但更有价值的问题是, 是否存在和 Magisk proc audit 侧信道同构的模拟器专属信号.

观察: 直接属性和设备节点可见, 但这些都是常规模拟器检测.

解释: 更值得沉淀的 case 应该来自 App 沙箱触碰受保护 `/proc/<pid>` 后产生的 audit 记录.

仍需验证: 更多 Android 版本和模拟器镜像中, logcat(日志缓冲)是否都能看到模拟器专属 SELinux(安全增强 Linux) domain(安全域).

## 3. 候选主题

`android-proc-audit-sidechannel-emulator-detection`

该候选主题关注 Android 第三方 App 沙箱中 `/proc` 访问触发 audit 记录, 从而暴露模拟器专属 SELinux `tcontext`.

## 4. 已确认主题

未确认. 当前只是 Android 9 arm64 AVD(Android Virtual Device, Android 虚拟设备)上的单个 case. 后续需要更多模拟器版本, API 级别和真机负样本后再创建 topic.

## 5. 异常味道

1. 常规模拟器信号太明显, 包括 `ro.kernel.qemu=1`, `ro.hardware=ranchu` 和 `/dev/qemu_pipe`.
2. Magisk case 已经证明, `/proc/<pid>` 访问可以在不能直接检查进程时泄露隐藏安全上下文.
3. 从 adb shell 进程上下文看, 模拟器进程存在很突出的 SELinux domain, 尤其是 `u:r:qemu_props:s0`.
4. 大范围 `/proc` 扫描容易因为 audit 限流和噪声漏掉或淹没有用行.
5. 通过不同 shell 进程运行脚本可能改变信号形态, 所以执行模型很重要.

噪声或误导:

1. `ro.kernel.qemu=1` 有效, 但不是本次侧信道发现.
2. `tcontext=u:r:init:s0` 和 `tcontext=u:r:kernel:s0` 这类通用 audit 行在模拟器和真机上都可能出现.
3. 真机日志可能有 Mira toolbox 执行产生的无关 granted audit 记录.

## 6. 关键线索

1. 在 AVD 上, adb shell 进程列表显示 `qemu-props` 的 SELinux 上下文是 `u:r:qemu_props:s0`.
2. 从 Mira App 沙箱触碰 `/proc/1394` 会产生 `tcontext=u:r:qemu_props:s0` 的 audit denial(拒绝记录).
3. 对 `1390-1399` 的小窗口扫描可以自动命中同一信号.
4. 物理 Pixel 4 在可比窗口里没有出现 `qemu`, `ranchu` 或 `goldfish` 的 `tcontext` 命中.
5. 模拟器专属 HAL(Hardware Abstraction Layer, 硬件抽象层)进程名包括 `android.hardware.health@2.0-service.goldfish` 和 `android.hardware.power@1.1-service.ranchu`, 说明其他镜像上可能还有更多目标 domain.

代表性 AVD 命中:

```text
hit_window=1390-1399
05-20 16:42:23.822 ... avc: denied { getattr } for comm="sh" path="/proc/1394" dev="proc" ... scontext=u:r:untrusted_app:s0:c88,c256,c512,c768 tcontext=u:r:qemu_props:s0 tclass=dir permissive=0
```

真机基线结果:

```text
no_qemu_ranchu_goldfish_tcontext_in_window
```

## 7. 验证动作

1. 启动 AVD `9`, 确认 adb(Android Debug Bridge, Android 调试桥) serial 是 `emulator-5554`.
2. 安装并启动 Mira Android, 注入 relay(中继服务)地址 `http://10.0.2.2:8765`.
3. 通过 Mira MCP(Mira Control Protocol, Mira 控制协议)的 `mira_run_command` 在 AVD App 沙箱里执行命令.
4. 采集直接模拟器信号, 包括 `ro.kernel.qemu=1`, `ro.hardware=ranchu`, `ro.boot.hardware=ranchu`, `/dev/qemu_pipe` 和 `/dev/goldfish_pipe`.
5. 用 adb shell 进程上下文列表找候选模拟器专属进程上下文.
6. 从 Mira 沙箱定点触碰 `/proc/1388`, `/proc/1389`, `/proc/1394` 和 `/proc/1399`, 并检查清空后的 logcat.
7. 使用 `START=1000 END=1700 CHUNK=10 STEP=10 WAIT_SEC=1 LOG_TAIL=400` 自动小窗口扫描.
8. 对比物理 Pixel 4 的 Mira 沙箱基线, 搜索 `qemu`, `ranchu` 和 `goldfish` 的 `tcontext`.

## 8. 脚本产物与执行模型

Case script artifact(案例脚本快照):

```text
knowledge/cases/artifacts/2026/2026-05-20-android-emulator-proc-audit-sidechannel.sh
```

Maintained reusable copy(维护版可复用脚本):

```text
tools/android/mira-emulator-audit-sidechannel.sh
```

推荐执行方式:

1. 将脚本内容粘贴进 `mira_run_command`, 让它在当前 Mira PTY(Pseudo Terminal, 伪终端) shell 中执行.
2. 或写入设备 cache path 后, 用 `. /data/data/com.vwww.mira/cache/mira-emulator-audit-sidechannel.sh` source(在当前 shell 加载)执行.
3. 在证明等价前避免 `sh file`, 因为信号依赖当前 shell 进程触碰 `/proc/<pid>`.

本 case 的已验证默认参数:

```sh
START=1000
END=2500
CHUNK=10
STEP=10
WAIT_SEC=1
LOG_TAIL=400
MATCH='tcontext=u:r:qemu_props:s0|tcontext=u:r:[^ ]*(goldfish|ranchu|qemu)[^ ]*:s0'
```

最小验证命令:

```sh
START=1350 END=1420 CHUNK=10 STEP=10 . /data/data/com.vwww.mira/cache/mira-emulator-audit-sidechannel.sh
```

预期 AVD 风格结果:

```text
[probe] hit pid=1390-1399
tcontext=u:r:qemu_props:s0
```

## 9. 结果

该侧信道在本次测试 AVD 上确认成立. 第三方 App 沙箱触碰 `/proc/<pid>` 可以触发 audit 记录, 并暴露模拟器专属 SELinux `tcontext`, 最关键的是 `u:r:qemu_props:s0`.

支持的结论: 该 AVD 会通过 Mira App 上下文可见的 `/proc` audit 记录泄露模拟器专属 SELinux domain.

不支持的结论: 不能仅凭这一次实验断言所有 Android 模拟器镜像, ROM, API 级别或加固 logcat 策略都可检测.

## 10. 误判风险

1. `qemu_props`, `goldfish` 和 `ranchu` domain 在正常 Android 设备上高度偏模拟器, 但特殊 vendor test build 理论上可能复用相似名称.
2. 如果每个 decision window(判断窗口)前不清空 logcat, 旧日志可能造成 stale hit(陈旧命中).
3. audit 限流可能让过大的扫描窗口漏掉真实命中.
4. Android 版本, SELinux policy(策略), logcat 可见性和 App target SDK(目标 SDK)都可能影响可观测性.
5. 真机可能有无关字符串如 kernel thread(内核线程)里的 `virt`, 所以匹配必须限制在 SELinux `tcontext` 上.

## 11. 判断种子

1. 如果直接模拟器 property 可见, 不要停在这里. 继续寻找能暴露背后模拟器服务 domain 的侧信道.
2. 对 `/proc` audit probe(探针), 先用 adb shell `ps -AZ` 找可能的目标 domain, 再围绕目标 PID 调整 App 沙箱扫描窗口.
3. 强模拟器侧信道信号应匹配 SELinux `tcontext`, 而不是任意进程名或 property 字符串.
4. 扫描 chunk(分块)要足够小, 避免 audit 噪声和目标落在窗口后段造成漏检.
5. 每个窗口前清空 logcat 可以隔离证据, 但不能替代 chunk 控制.

## 12. 后续检查

1. 测试 Android 10 到 Android 16 AVD 镜像, 对比 `qemu_props` 是否稳定可见.
2. 测试 Play Store 和非 Play Store 镜像, 因为服务组成可能不同.
3. 在每个镜像上扫描 `hal_*goldfish*`, `hal_*ranchu*` 和 `qemu_props` domain.
4. 在受限 logcat 条件下对比直接 property 检测和 audit 侧信道检测.
5. 验证是否仍必须使用 `CHUNK=10`, 或 `CHUNK=50 STEP=25` 是否已足够稳定.
6. 在更多物理设备和 vendor ROM 上采集负样本基线.

## 13. 相关文章

暂无. 先作为 case 保存, 等多个模拟器镜像确认稳定边界和失败模式后再提炼 topic 或 article.
