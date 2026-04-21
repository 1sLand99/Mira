# Mira MCP Server

## 目标

MCP(Model Context Protocol, 模型上下文协议) server(服务端) 让外部 AI client(智能客户端), 例如 Codex, 通过标准 JSON-RPC(JSON 远程过程调用) 工具接口操作 Mira Relay(中继服务端)。

它不替代 Relay Server。它是 AI 到 Relay 的适配层:

```text
Codex
  -> MCP stdio(JSON-RPC)
  -> mira.mcp.server
  -> Mira Relay HTTP API + WebSocket
  -> Android Mira Discovery Service
  -> Android PTY
```

## 启动顺序

先启动 Relay Server:

```bash
python3 -m mira.relay.server \
  --host 0.0.0.0 \
  --port 8765 \
  --discovery-port 8766 \
  --advertise-url http://<电脑局域网IP>:8765
```

再让 MCP client 启动 MCP Server:

```bash
python3 -m mira.mcp.server \
  --relay http://127.0.0.1:8765 \
  --broadcast-target 255.255.255.255
```

也可以用环境变量:

```bash
MIRA_RELAY_URL=http://127.0.0.1:8765 \
MIRA_BROADCAST_TARGET=255.255.255.255 \
python3 -m mira.mcp.server
```

## Codex 配置示例

如果 Codex 使用 TOML(配置文件格式) 声明 MCP server, 可以按下面思路配置:

```toml
[mcp_servers.mira]
command = "python3"
args = ["-m", "mira.mcp.server", "--relay", "http://127.0.0.1:8765"]
cwd = "/Users/vw2x/Projects/Reverses/Mira"
```

实际字段名以当前 Codex 客户端支持为准。核心是让客户端以 stdio(标准输入输出) 方式启动 `python3 -m mira.mcp.server`。

MCP stdio 消息使用单行 JSON-RPC(JSON 远程过程调用) 消息, stdout(标准输出) 只写协议响应, 日志应写 stderr(标准错误输出)。

## 暴露的 tools

| Tool | 用途 |
| --- | --- |
| `mira_discover_devices` | 通过 Relay 扫描局域网设备 |
| `mira_list_devices` | 读取 Relay 已知设备列表 |
| `mira_open_terminal` | 打开 Android PTY 会话并 attach(附着) |
| `mira_run_command` | 在持久 PTY 中执行命令并等待结束标记 |
| `mira_collect_snapshot` | 执行第一轮 Android 分析命令集 |
| `mira_send_input` | 向交互式 PTY 发送原始输入 |
| `mira_read_output` | 读取 MCP 侧缓存的终端输出 |
| `mira_close_terminal` | 关闭 PTY 会话并触发设备侧清理 |

## 暴露的 resources

| Resource | 用途 |
| --- | --- |
| `mira://analysis-guide` | Android 终端分析指南 |
| `mira://sessions` | 当前 MCP 进程内活跃 session(会话) |
| `mira://relay` | 当前 Relay URL(统一资源定位符) 和 broadcast target(广播目标) |

## 暴露的 prompt

| Prompt | 用途 |
| --- | --- |
| `mira_android_triage` | 指导 AI 采集设备身份, shell 环境, toolbox, mount, process 和 memory 证据 |

## 推荐 AI 分析流

```text
mira_discover_devices
  -> mira_collect_snapshot
  -> 按输出补充 mira_run_command
  -> 汇总设备身份, shell 环境, mount, toolbox 和风险点
  -> mira_close_terminal
```

## 设计边界

1. MCP Server 只连接已有 Relay Server, 不负责启动 Relay Server。
2. MCP Server 使用 stdio transport(标准输入输出传输), 不直接暴露公网 HTTP 服务。
3. 每个 MCP 进程在内存里维护自己的 browser attach 和输出缓存。
4. `mira_run_command` 面向短命令和诊断命令, 长时间交互用 `mira_send_input` 和 `mira_read_output`。
5. `mira_collect_snapshot` 优先使用 `/system/bin/...` 采集 Android 系统信息, 避免临时 toolbox applet(工具别名) 遮蔽系统命令。
6. 本阶段不做账号体系, TLS(传输层安全协议), 多租户隔离或 AI 自动决策策略。
