<p align="center">
  <img src="./apps/console/app/icon.svg" alt="Mira icon" width="88" />
</p>

<h1 align="center">Mira</h1>

<p align="center">
  <a href="./README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Android-iOS-2f855a?style=flat-square" alt="Android and iOS" />
  <img src="https://img.shields.io/badge/Built--in-MCP-0f172a?style=flat-square" alt="Built-in MCP" />
  <img src="https://img.shields.io/badge/Built--in-Frida-dc2626?style=flat-square" alt="Built-in Frida" />
  <img src="https://img.shields.io/badge/Relay-Ready-2563eb?style=flat-square" alt="Relay Ready" />
</p>

<p align="center">
  AI-native mobile runtime analysis workspace for authorized Android and iOS research.
</p>

<p align="center">
  <a href="./docs/GETTING-STARTED.md">Getting Started</a> ·
  <a href="./docs/MCP.md">Claude / Codex MCP Setup</a> ·
  <a href="./docs/">Documentation</a> ·
  <a href="./docs/THIRD-PARTY-NOTICES.md">Third-Party Notices</a>
</p>

## What Mira is

Mira is a mobile research workspace for teams that need to inspect the real runtime state of their own app under authorization. It combines a browser console, built-in Relay, remote PTY, and Frida-powered inspection so AI agents and human researchers can work against the same live session.

![Claude analyzing runtime hook traces](./docs/Area.gif)

## Key capabilities

### AI-ready runtime inspection

Mira exposes the actual app sandbox, ships with built-in Frida execution for Java and Native analysis, and provides `mira-mcp` so Codex or Claude can inspect a live device session through standard MCP tooling.

See [`docs/MCP.md`](./docs/MCP.md) for the MCP integration flow.

### Android and iOS workbench

Mira integrates a BusyBox-style toolbox, Frida gadget support, and an interactive process-oriented shell view across both platforms. On iOS, the PTY and process view are adapted to the iSH compatibility layer.

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

### Optional public access through Relay

With Relay, you can temporarily expose an authorized session beyond the local network. This is useful for cloud devices, remote collaboration, or fast handoff during a live analysis session.

![Relay exposed through cpolar](./docs/public-deploy.png)

### Knowledge capture for repeatable reviews

Each investigation can be turned into reusable assets: articles for process notes, cases for evidence chains, and skills for AI-assisted review flows.

## Supported workflows

1. Start a local or public Relay.
2. Connect an Android or iOS Mira app instance.
3. Open the browser console and remote PTY.
4. Attach MCP clients such as Codex or Claude.
5. Run Frida, shell, and runtime inspection tasks against the same authorized session.

## Quick start

### Launch Relay and the web console

```bash
./mira-local-web
```

For temporary public sharing:

```bash
./mira-web
```

### Android automation path

```bash
MIRA_ANDROID_RELAY_URL="http://<host-ip>:8765" \
./mira-android
```

### iOS simulator path

```bash
./mira-ios
```

### MCP server

```bash
python3 -m mira.mcp.server \
  --relay http://127.0.0.1:8765
```

For detailed setup, device launch, and troubleshooting, see [`docs/GETTING-STARTED.md`](./docs/GETTING-STARTED.md).

## Repository structure

- `android/`: Android app and platform integration.
- `ios/`: iOS app, iSH-based runtime bridge, and device workflows.
- `apps/console/`: Web console UI.
- `mira/`: Relay, MCP server, and Python CLI implementation.
- `native/`: Shared native runtime components.
- `docs/`: Setup notes, architecture, and platform-specific documentation.
- `tools/`: Build, packaging, and helper scripts.

## Research boundaries

Mira is designed for authorized research on apps and environments you own or are explicitly permitted to inspect.

1. It observes and interacts with the Mira host app sandbox.
2. It does not control unrelated third-party apps.
3. It does not provide system-wide remote control.
4. It does not provide root or jailbreak bypass capabilities.
5. It is not a production SDK or a silent background control channel.

## Acknowledgements

- [lamda](https://github.com/firerpa/lamda): inspiration for the web workbench interaction model.
- [Termux](https://github.com/termux/termux-app): Android terminal UX and extensible shell ecosystem.
- [iSH](https://github.com/ish-app/ish): iOS-side Linux shell compatibility and syscall translation path.

## License

`GPL-3.0-only`.

Third-party components are distributed under their respective upstream licenses. See [`docs/THIRD-PARTY-NOTICES.md`](./docs/THIRD-PARTY-NOTICES.md) for details.
