<p align="right">
  <a href="./README.zh-CN.md">简体中文</a>
</p>

# Mira

<p align="center">
  A modern mobile defense workspace for live risk discovery, runtime verification, and AI-accelerated hardening.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Android-iOS-2f855a?style=flat-square" alt="Android and iOS" />
  <img src="https://img.shields.io/badge/MCP-AI%20Ready-0f172a?style=flat-square" alt="MCP AI Ready" />
  <img src="https://img.shields.io/badge/Relay-Frida-2563eb?style=flat-square" alt="Relay and Frida" />
</p>

![Claude analyzing runtime hook traces](./docs/Area.gif)

<p align="center">
  Built for security teams that need faster evidence collection, sharper runtime verification, and more repeatable hardening workflows.
</p>

## Why security teams use Mira

- **Faster defensive feedback loops**: move from suspicion to live runtime evidence without rebuilding a separate lab flow for every verification pass.
- **AI-accelerated hardening**: connect Codex or Claude through `mira-mcp` so researchers can turn raw observations into review steps, cases, and mitigation ideas faster.
- **One workbench across mobile stacks**: keep Android and iOS discovery, verification, and follow-up inside the same Relay-based workflow.

## Core capabilities

### Live runtime risk discovery

Mira exposes the actual app sandbox, ships with built-in Frida execution for Java and Native analysis, and surfaces the signals that matter for mobile defense: runtime hooks, environment fingerprints, process state, and verification evidence inside the running app.

It also provides `mira-mcp`, so Codex or Claude can inspect the same live device session through standard MCP tooling.

See [`docs/MCP.md`](./docs/MCP.md) for the MCP integration flow.

### One defensive workbench across Android and iOS

Mira integrates a BusyBox-style toolbox, Frida gadget support, and an interactive process-oriented shell view across both platforms. On iOS, the PTY and process view are adapted to the iSH compatibility layer, so the same review workflow can span both mobile stacks without splitting the tooling model.

<table>
  <tr>
    <th align="center">Android</th>
    <th align="center">iOS</th>
  </tr>
  <tr>
    <td>
      <img src="./docs/android-remote-frida.png" alt="Android Remote Frida" />
      <div align="center"><sub>Remote shell and runtime inspection on Android.</sub></div>
    </td>
    <td>
      <img src="./docs/ios-remote-frida.png" alt="iOS Remote Frida" />
      <div align="center"><sub>Equivalent PTY and Frida workflow on iOS.</sub></div>
    </td>
  </tr>
</table>

> Mira currently embeds a trimmed Frida gadget build. Injection fingerprints and occasional instability are known limitations and are being improved in future iterations.

### Relay-powered expert collaboration

With Relay, you can temporarily expose an authorized session beyond the local network. This makes Mira practical for cloud devices, remote collaboration, expert review handoff, and fast evidence sharing when multiple people need to reason about the same live runtime state.

![Relay exposed through cpolar](./docs/public-deploy.png)

## Defense workflow

1. Start a local Relay with `./mira-local-web`, or expose a temporary public session with `./mira-web`.
2. Launch the Mira app on Android or iOS and connect it to the Relay.
3. Open the browser console and remote PTY to inspect the app's real runtime state.
4. Attach Codex or Claude through MCP to accelerate hypothesis generation, validation, and evidence collection.
5. Convert findings into reusable defensive review workflows, cases, and hardening follow-ups.

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
