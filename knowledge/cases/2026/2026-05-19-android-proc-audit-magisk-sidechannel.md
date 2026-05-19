# Android proc audit side-channel detects Magisk SELinux context

## 1. detection object

Android app sandbox shell(应用沙箱命令环境)中的 `/proc/<pid>` 元数据访问 audit log(审计日志)侧信道, 用于观察目标进程的 SELinux(安全增强 Linux) `tcontext`.

## 2. initial suspicion

用户提出的检测思路是: 第三方 app 不直接读取 Magisk 进程信息, 而是通过触碰 `/proc/<pid>` 触发 SELinux audit, 再从 logcat(Android 日志读取工具)里搜索 `tcontext=u:r:magisk:s0`.

## 3. topic candidate

`android-proc-audit-sidechannel-root-detection`

候选主题聚焦 Android 第三方 app 环境中的 `/proc` 访问审计侧信道, 不等同于常规 root 文件路径检测或进程列表检测.

## 4. confirmed topic

未确认. 当前只作为 case(案例)记录, 后续如继续积累同类样本, 再维护 `knowledge/topics/android-proc-audit-sidechannel-root-detection/`.

## 5. smells

1. 单点 `[ -d /proc/1030 ]` 能触发 `tcontext=u:r:magisk:s0`, 但大范围线性扫描容易无命中.
2. `sh script.sh` 和当前 Mira PTY(伪终端)交互 shell 行为不完全等价.
3. 每个 PID fork(派生进程)外部 `stat` 或 `getxattr` 会制造大量无关 audit 噪声.
4. 只增加 sleep(等待时间)不能解决后半段 PID 被 audit rate limit(审计限流)吞掉的问题.

## 6. key clues

1. 单点触发命令 `[ -d /proc/1030 ]` 产生了 `{ getattr }` denied 日志, 且 `tcontext=u:r:magisk:s0`.
2. `1000-1049 wait=5` 只吐出前几个 `kernel` 目标, 没有吐出后面的 `1030`, 说明不是日志延迟问题.
3. `1030-1079 wait=5` 稳定吐出 `/proc/1030`, `/proc/1031`, `/proc/1032`, `/proc/1051` 的 Magisk 上下文.
4. `CHUNK=50` 在 `1000-1100` 范围内可命中 `1050-1099` 窗口里的 `/proc/1051`.

## 7. validation actions

1. 使用 Mira MCP(模型上下文协议)打开 Android PTY.
2. 在当前 shell 中执行 `[ -d /proc/1030 ]`, 然后用 `/system/bin/logcat -d -b all` 搜索 `tcontext=u:r:magisk:s0`.
3. 对比 `sh script.sh`, `source script`, inline loop(内联循环), 外部 `/system/bin/stat`, shell builtin(内建命令)等触发方式.
4. 对比 `CHUNK=10`, `CHUNK=50`, `CHUNK=500` 和不同等待时间的命中稳定性.
5. 将可复用脚本落到 `tools/android/mira-proc-audit-sidechannel.sh`.

## 8. result

确认该侧信道在目标设备上成立. 可靠命中示例:

```text
avc: denied { getattr } for comm="sh" path="/proc/1030" dev="proc" ... tcontext=u:r:magisk:s0 ... app=com.vwww.mira
```

实测推荐参数是 `CHUNK=50`, `WAIT_SEC=1-3`, `COOLDOWN_SEC=2-3`, `LOG_TAIL=1000-2000`. 如果全量扫描未命中, 优先缩小 chunk 或使用重叠 step, 不要只拉长等待时间.

## 9. false-positive risk

1. 旧 logcat 缓冲区可能残留历史命中, 所以每个判断窗口前应清空 logcat.
2. `tcontext=u:r:magisk:s0` 是强信号, 但最终结论应描述为检测到 Magisk 相关 SELinux 上下文暴露, 不应直接推导所有 root 能力状态.
3. 不同 ROM(安卓系统发行版), SELinux policy(策略), Magisk 配置和 logcat 权限会影响可见性.
4. 大窗口无命中不能作为无 Magisk 结论, 它可能只是 audit 限流或窗口噪声导致.

## 10. distilled judgment seeds

1. 对 audit 侧信道, 单点能命中而批量不命中时, 优先怀疑限流和窗口噪声.
2. 对 Mira PTY 脚本, 当前交互 shell 和 `sh file` 不是天然等价, 关键 syscall(系统调用)触发点要实测.
3. 对 `/proc` 扫描, 触发窗口应小于日志限流阈值, 并让目标 PID 尽量不要落在窗口太后面.
4. 对检测脚本, `logcat -c` 是隔离当前窗口证据的关键步骤, 但不能替代 chunk 控制.

## 11. suggested next checks

1. 在更多 Android 版本和 ROM 上验证 `CHUNK=50` 与 `CHUNK=10` 的命中率差异.
2. 验证重叠窗口策略, 例如 `CHUNK=50 STEP=25`, 是否能降低目标落在窗口后半段时的漏检.
3. 验证非 Magisk root 方案是否暴露不同 `tcontext`, 例如 `u:r:su:s0` 或厂商自定义域.
4. 记录 enforcing(强制模式)和 permissive(宽容模式)下 audit 可见性的差异.
5. 评估是否需要形成 topic(主题)资产和 article(文章)草稿.

## 12. linked articles

暂无. 当前只沉淀为 case. 如果后续形成主题文章, 应从本 case 和更多设备样本中提炼边界, 误判风险和稳定参数.
