<p align="right">
  English | <a href="./THIRD-PARTY-NOTICES.zh-CN.md">简体中文</a>
</p>

# Third Party Notices

## BusyBox

- Name: BusyBox
- Version: LAMDA v9.25 busybox assets
- License: GPL-2.0
- Source: https://github.com/firerpa/lamda/releases/tag/v9.25
- Download script: `tools/toolbox/download-lamda-busybox.sh`
- Self build experiment script: `tools/toolbox/build-busybox-android.sh`
- Manifest: `android/app/src/main/assets/toolbox/manifest.json`
- Packaged assets:
  - `android/app/src/main/assets/toolbox/busybox/arm64-v8a/busybox`
  - `android/app/src/main/assets/toolbox/busybox/armeabi-v7a/busybox`
  - `android/app/src/main/assets/toolbox/busybox/x86/busybox`
  - `android/app/src/main/assets/toolbox/busybox/x86_64/busybox`

Mira packages BusyBox as APK assets and releases the matching ABI binary into a temporary per-session toolbox directory when a remote terminal session starts.

## iSH

Mira currently vendors iSH as a Git submodule for the foreground shell prototype inside the regular iOS app.

1. Upstream: https://github.com/ish-app/ish
2. Local path: `./third_party/ish`
3. Purpose: provide the foreground Linux shell backend prototype for the iOS app.
4. License: iSH uses GPLv3 together with the iOS-specific additional terms in `LICENSE.IOS`. The upstream project also notes that later contributions are compatible with GPLv2.
