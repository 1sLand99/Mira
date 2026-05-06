<p align="right">
  English | <a href="./REPO-ARCHITECTURE.zh-CN.md">简体中文</a>
</p>

# Repository Architecture

Mira is currently split across platform app shells, a shared native layer, Relay and MCP services, a browser console, third-party components, and project documentation.

## Top-level directories

```text
android/      Android app shell and packaging config
apps/console/ Browser console source
docs/         Current documentation entry, plus notes and archive
ios/          iOS app shell and Xcode project
mira/         Python Relay, MCP, and CLI code
native/       Shared PTY and bridge native layer
third_party/  Vendored or pinned third-party components
tools/        Build, packaging, and helper scripts
web/          Web-facing assets and related support code
```

## Layering rules

1. Platform-specific app logic stays under `android/` and `ios/`.
2. Reusable PTY and bridge logic stays under `native/`.
3. Relay, MCP, and CLI stay under `mira/`.
4. Documentation entry points stay under `docs/`, while research notes and archived phase material stay in their dedicated subdirectories.

## Current entry points

The repo root keeps stable wrappers such as `mira-android`, `mira-ios`, `mira-build`, `mira-cli`, `mira-local-web`, and `mira-web` so common workflows do not depend on remembering long commands.

## Documentation layering

1. `docs/README.md` is the English documentation hub.
2. `docs/README.zh-CN.md` is the Simplified Chinese documentation hub.
3. `docs/notes/` stores ongoing notes and research material.
4. `docs/archive/` stores historical phase records.
