# Contributing to Mira

Thanks for your interest in Mira. This project is built in the open and welcomes practical contributions from mobile security researchers, reverse engineers, Frida users, MCP users, and device testers.

## Good First Contributions

Useful contributions include:

1. Security hardening for native C, Objective-C, Swift, Kotlin, Python, and build scripts.
2. Android or iOS device compatibility reports with concrete logs.
3. New detection cases under `knowledge/cases/` with reproducible evidence.
4. Improvements to Relay, MCP, shell, PTY, or Frida workflows.
5. Documentation fixes that make setup, risk boundaries, or troubleshooting clearer.
6. Small tests or scripts that make runtime behavior easier to verify.

## Before Opening an Issue

Please check existing issues and documentation first.

When opening an issue, include:

1. What you expected to happen.
2. What actually happened.
3. The platform, device, OS version, and Mira version or commit.
4. Logs, screenshots, or command output when possible.
5. Whether the issue affects Android, iOS, Relay, MCP, docs, or native code.

## Before Opening a Pull Request

Please keep pull requests focused and reviewable.

A good pull request should include:

1. A clear title using a conventional commit style when possible.
2. A short explanation of the problem and the fix.
3. The exact files or flows changed.
4. Manual verification steps or test output.
5. Notes about behavior changes, compatibility risks, or follow-up work.

Avoid bundling unrelated refactors, formatting changes, and feature work in one pull request.

## Security and Hardening Pull Requests

Security and hardening pull requests are welcome.

For scanner-generated findings, please include repository-specific reasoning, not only generic CWE text. Explain why the code path is reachable in Mira and how the patch avoids regressions.

For memory safety fixes, please check related patterns in nearby Android, iOS, and shared native code. A narrow one-line fix may be correct, but related growth, bounds, and lifetime logic should be reviewed together when practical.

## Development Notes

Common local entry points:

```bash
PYTHONPATH=. python3 -m mira.relay.server --host 0.0.0.0 --port 8765 --advertise-url http://<your-lan-ip>:8765
PYTHONPATH=. python3 -m mira.mcp.server --relay http://127.0.0.1:8765
```

Android automation normally starts from:

```bash
MIRA_ANDROID_RELAY_URL="http://<host-ip>:8765" ./mira-android
```

For iOS device builds, prefer a real device destination rather than `generic/platform=iOS`.

## Documentation Language

The main README is English. When changing user-facing documentation, update the matching Simplified Chinese file when one exists.

## Maintainer Review

Maintainers may ask for a smaller patch, clearer reproduction steps, or a different implementation. This is normal. The goal is to keep Mira useful as a research workbench while preserving clear trust boundaries.
