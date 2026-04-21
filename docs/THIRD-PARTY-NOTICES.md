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
