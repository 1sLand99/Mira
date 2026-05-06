<p align="right">
  English | <a href="./GETTING-STARTED.zh-CN.md">简体中文</a>
</p>

# Getting Started

This guide holds the setup, build, connection, and integration steps that were moved out of the project README so the homepage can stay product-focused.

## 1. Start Relay and the browser workbench

Start the local Relay through the Python module entry point:

```bash
PYTHONPATH=. python3 -m mira.relay.server \
  --host 0.0.0.0 \
  --port 8765 \
  --advertise-url http://<your-lan-ip>:8765
```

Open the desktop browser at:

```text
http://127.0.0.1:8765
```

On Android or iOS, enter your desktop LAN address:

```text
http://<your-lan-ip>:8765
```

Do not enter `127.0.0.1` on the phone. On the phone, that address points to the phone itself, not your computer.

If you need a temporary remote debugging path, see `REMOTE-RELAY.md`. The repo also keeps developer shortcut scripts such as `./mira-local-web` and `./mira-web`, but they are not the main entry here.

## 2. Build and launch the Android app

After a fresh clone, run:

```bash
git submodule update --init --recursive
```

If the Android build reports `third_party/... does not exist`, the submodules were usually not checked out correctly. Confirm the target directories are not just placeholder `.git` entries.

```bash
./gradlew :mira-app:assembleDebug
adb install -r android/app/build/outputs/apk/debug/mira-app-debug.apk
adb shell am start -n com.vwww.mira/.MainActivity
```

For the Android automation path, you can directly run:

```bash
MIRA_ANDROID_RELAY_URL="http://<host-ip>:8765" \
./mira-android
```

The script builds, installs, launches the app, injects the Relay URL, and auto-connects.

Default Android shell binary and working directory:

```text
/data/user/0/com.vwww.mira/files/usr/bin/sh
/data/user/0/com.vwww.mira/files/home
```

The native PTY layer has already been refactored into a shared POSIX architecture for Android and iOS. See `NATIVE-ARCHITECTURE.md` for the boundaries.

## 3. Build and launch the iOS app

The validated iOS path is currently a real device running **iOS 16.7.10**. Treat real-device deployment as the default path rather than the simulator.

The iOS side already includes Relay, PTY, upload of the Mira app key window, device metric sampling, `/mira` app-view root, and `/mira/proc` simulated process view. See `IOS-APP.md` for details.

For the real-device automation path, install `idb-companion` and `fb-idb`, then inject the Relay URL through launch environment variables:

```bash
git submodule update --init --recursive
bash ./tools/ios/build-frida-musl-devkit.sh
MIRA_IOS_AUTO_LAUNCH_DEVICE=1 \
MIRA_IOS_RELAY_URL="http://<your-lan-ip>:8765" \
./mira-ios --device
```

Recommended real-device build rules:

1. Do not rely on `generic/platform=iOS` as a fallback validation path.
2. Build against an actual device destination.
3. Clear host SDK path pollution before the build.
4. Prefer `env -u LIBRARY_PATH -u SDKROOT xcodebuild ...` for real-device builds.

## 4. Connect the mobile side

After Relay is up:

1. Open the Mira app on the phone.
2. Enter the Relay URL shown above.
3. Tap `Connect Relay`.
4. Open the browser console on the desktop and attach to the connected device.

## 5. MCP integration

To let Codex or Claude operate Mira through MCP, start the MCP server after Relay:

```bash
PYTHONPATH=. python3 -m mira.mcp.server --relay http://127.0.0.1:8765
```

For full configuration examples, see `MCP.md`.

## 6. CLI

Common local CLI entry points:

```bash
./mira-cli
./mira-build
./mira-android
./mira-ios
./mira-local-web
./mira-web
```

## 7. Unified build and packaging

The repo keeps lightweight wrapper scripts at the root so Android, iOS, Relay, and web workflows can share stable entry points. Prefer these wrappers when you want a repeatable local workflow.

## 8. Usage notes

1. Mira works inside the Mira host app sandbox.
2. It is designed for runtime observation, interactive analysis, and controlled instrumentation.
3. The current baseline is a research workbench, not a production SDK.

## 9. Recovery checklist after re-cloning

1. Run `git submodule update --init --recursive`.
2. Rebuild any generated native or third-party artifacts required by your target platform.
3. Re-verify Relay, app install, and MCP connectivity before starting a new analysis session.
