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

Mira 当前将 iSH 作为 Git submodule(Git 子模块) 接入, 用于普通 iOS(苹果移动操作系统) App(应用) 前台 shell(命令解释器) 原型。

1. 上游地址: https://github.com/ish-app/ish
2. 本地路径: `/Users/vw2x/Projects/Reverses/Mira/third_party/ish`
3. 使用目的: 提供 iOS App 前台 Linux shell backend(后端) 原型。
4. 许可证: iSH 使用 GPLv3(通用公共许可证第 3 版), 并带有 `LICENSE.IOS` 中的 iOS 附加条款。上游说明后续贡献也兼容 GPLv2(通用公共许可证第 2 版)。
