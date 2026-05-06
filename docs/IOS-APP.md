<p align="right">
  English | <a href="./IOS-APP.zh-CN.md">简体中文</a>
</p>

# iOS App

This document records the current state of the Mira iOS app and the supported launch paths. The iOS side already integrates Relay, PTY, remote view upload, device metric sampling, and browser shortcuts.

## Current capabilities

Implemented:

1. `ios/Mira/Mira.xcodeproj` Xcode project.
2. SwiftUI home screen aligned with the Android control page.
3. Relay URL input plus `Connect Relay` and `Disconnect` buttons.
4. Native iOS Relay control channel that lets the browser open PTY sessions.
5. Mira app window upload to `/ws/screen/device` through H.264 plus WebSocket.
6. CPU, memory, and network metrics reported every second through `device.metrics`.
7. Browser remote view support for click, text input, paste, copy, select all, clear, Backspace, and Delete.
8. Root-level `./mira-ios` launch entry.

Current boundaries:

1. Only the Mira app key window is rendered.
2. ReplayKit is not used and system-wide full-screen capture is not enabled.
3. Remote click relies on public UIKit capabilities and does not use private touch injection.
4. The native C Relay control channel is still mainly `ws://`, while the Swift screen channel supports both `ws://` and `wss://`.

## Directory layout

```text
ios/
  Mira/
    Mira.xcodeproj/
    Mira/
      App/
        MiraApp.swift
        ContentView.swift
        MiraControlViewModel.swift
      NativeBridge/
        Mira-Bridging-Header.h
        MiraNativeStatus.swift
        MiraRemoteServices.swift
      Resources/
        README.md
```

The native bridge also references:

```text
native/bridge/ios/mira_pty_ios_shim.h
native/bridge/ios/mira_pty_ios_shim.c
native/bridge/ios/mira_ios_relay.c
```

## Open and launch paths

### Open in Xcode

```bash
open ios/Mira/Mira.xcodeproj
```

Then choose a scheme and destination in Xcode and run the app.

### Command-line launch

```bash
./mira-ios
```

The script:

1. Checks Xcode command line tools.
2. Ensures an iOS Simulator is booted when the simulator path is used.
3. Builds a Debug version with `xcodebuild`.
4. Installs through `simctl install` for simulator runs.
5. Launches through `simctl launch`.

### Real-device automation path

Validated real-device flow:

```bash
env -u LIBRARY_PATH -u SDKROOT xcodebuild   -project ios/Mira/Mira.xcodeproj   -scheme Mira   -configuration Debug   -sdk iphoneos   -destination 'id=<device-udid>'   -derivedDataPath build/ios-mira-device-native-relay-derived   -allowProvisioningUpdates   -allowProvisioningDeviceRegistration   ENABLE_DEBUG_DYLIB=NO   ENABLE_PREVIEWS=NO   build
```

Recommended install and launch order with `idb`:

```bash
idb connect <device-udid>
idb install --udid <device-udid> build/ios-mira-device-native-relay-derived/Build/Products/Debug-iphoneos/Mira.app
IDB_MIRA_RELAY_URL="http://<host-ip>:8765" IDB_MIRA_AUTO_CONNECT=1 idb launch --udid <device-udid> com.vwww.mira.ios
```

### Fresh clone recovery

After a fresh clone, re-run submodule checkout and rebuild any required native artifacts before attempting iOS deployment.

### Unsigned IPA archive

If you need an unsigned archive for local research packaging, keep the app build path and signing expectations separated from the normal real-device validation path.

## Relay integration path

The iOS app connects to Relay with the same basic workflow as Android: enter the Relay URL, establish the control channel, then let the browser attach screen and PTY workflows on demand.

## Home screen alignment with Android

The iOS control page intentionally stays close to the Android page so Relay, PTY, and screen workflows remain easy to explain and automate across both platforms.
