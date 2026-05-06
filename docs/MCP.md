<p align="right">
  English | <a href="./MCP.zh-CN.md">简体中文</a>
</p>

# Mira MCP Server

## Goal

The MCP server lets external AI clients such as Codex connect to Mira Relay through standard JSON-RPC tool calls.

It does not replace Relay Server. It is the adapter layer between the AI client and Relay:

```text
Codex
  -> MCP stdio(JSON-RPC)
  -> mira.mcp.server
  -> Mira Relay HTTP API + WebSocket
  -> Android or iOS Mira runtime
  -> PTY and runtime actions
```

## Startup order

Start Relay Server first:

```bash
python3 -m mira.relay.server   --host 0.0.0.0   --port 8765   --advertise-url http://<your-lan-ip>:8765
```

Then let the MCP client launch the MCP server:

```bash
python3 -m mira.mcp.server   --relay http://127.0.0.1:8765
```

You can also use an environment variable:

```bash
MIRA_RELAY_URL=http://127.0.0.1:8765 python3 -m mira.mcp.server
```

## Client configuration overview

The repo mainly validates two MCP clients:

1. Claude Desktop, which uses JSON config, usually through `claude_desktop_config.json`.
2. Codex, which uses TOML config, usually through `~/.codex/config.toml`.

Use placeholders in shared examples:

1. `<path-to-mira-repo>`: your Mira repository root.
2. `<path-to-python>`: the Python interpreter used to launch Mira MCP Server.

Both clients ultimately launch the same module over stdio:

```text
python -m mira.mcp.server --relay http://127.0.0.1:8765
```

Main differences:

1. Claude uses `mcpServers` in JSON.
2. Codex uses `mcp_servers` in TOML.
3. For non-interactive Codex `exec` flows, it is safer to set each Mira tool `approval_mode` to `approve`.

## Claude Desktop config

Common config path on macOS:

```text
~/Library/Application Support/Claude/claude_desktop_config.json
```

The repo root also keeps a minimal example:

```text
./claude_desktop_config.json
```

## Codex config

Configure Mira MCP in your Codex TOML config and point it at the same Python module and Relay URL.

## Codex CLI example

Use the same Relay URL and Python entry when running from the CLI so desktop and terminal sessions stay aligned.

## Exposed tools

The MCP server exposes Mira session and runtime operations through tool calls. In practice, these cover session status, session listing, PTY lifecycle, command execution, and runtime interaction flows.

## Exposed resources

The server can surface runtime context as MCP resources when a client needs read-oriented access rather than direct tool execution.

## Exposed prompt

The repo can also provide reusable prompts that help AI clients enter a stable mobile runtime analysis workflow.

## Recommended AI analysis flow

Recommended order:

1. Start Relay.
2. Connect the mobile app.
3. Start MCP Server.
4. Let the AI client inspect device and session state first.
5. Reuse one long-lived iOS session when possible instead of reopening repeatedly.

## Magisk environment context

For Android risk review, keep environment context explicit, especially when your target case depends on root, Magisk, Zygisk, LSPosed, or related runtime traces.

## Design boundaries

1. MCP is an adapter, not a replacement for Relay.
2. Relay remains the transport and device coordination layer.
3. Runtime actions should stay grounded in the authorized Mira host app sandbox and connected session lifecycle.
