<p align="right">
  <a href="./THIRD-PARTY-NOTICES.md">English</a> | 简体中文
</p>

# 第三方说明

## BusyBox

- 名称: BusyBox
- 版本: LAMDA v9.25 busybox assets
- 许可证: GPL-2.0
- 来源: https://github.com/firerpa/lamda/releases/tag/v9.25
- 下载脚本: `tools/toolbox/download-lamda-busybox.sh`
- 自构建实验脚本: `tools/toolbox/build-busybox-android.sh`
- 清单: `android/app/src/main/assets/toolbox/manifest.json`
- 打包资产:
  - `android/app/src/main/assets/toolbox/busybox/arm64-v8a/busybox`
  - `android/app/src/main/assets/toolbox/busybox/armeabi-v7a/busybox`
  - `android/app/src/main/assets/toolbox/busybox/x86/busybox`
  - `android/app/src/main/assets/toolbox/busybox/x86_64/busybox`

Mira 会把 BusyBox 作为 APK 资产打包, 并在远程终端会话启动时, 将匹配 ABI 的二进制释放到临时的会话工具目录。

## iSH

Mira 当前将 iSH 作为 Git 子模块接入, 用于普通 iOS App 前台 shell 原型。

1. 上游地址: https://github.com/ish-app/ish
2. 本地路径: `./third_party/ish`
3. 使用目的: 提供 iOS App 前台 Linux shell backend 原型。
4. 许可证: iSH 使用 GPLv3, 并带有 `LICENSE.IOS` 中的 iOS 附加条款。上游说明后续贡献也兼容 GPLv2。
