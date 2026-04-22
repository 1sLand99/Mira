# iOS iSH POC(iOS iSH 原型)

本文记录普通 iOS(苹果移动操作系统) App(应用) 前台 shell(命令解释器) 方向的第一步接入结果。

## 当前目标

当前先不裁剪 iSH(用户态 Linux 模拟器项目), 目标是最快得到一个可以被 Mira relay(中继) 转发的 Linux shell(类 Linux 命令环境) backend(后端)。

阶段拆分:

1. 先把 iSH 作为 submodule(Git 子模块) 拉入 `third_party/ish`。
2. 先验证 iSH 的核心 static library(静态库) 能被本机 Xcode(苹果开发工具) 编出来。
3. 先落 Mira 自己的 C API(C 语言接口) 抽象层, 让 Android(安卓系统) 的 POSIX PTY(伪终端) 和 iOS(苹果移动操作系统) 的 iSH 后端共用同一套读写接口。
4. 再把远程输入输出接到 iSH 的 TTY(终端设备) 或 PTY(伪终端)。
5. 最后再裁剪 rootfs(根文件系统), 文件映射和命令集合。

## 已接入内容

新增 submodule:

```text
third_party/ish
```

iSH 自身还需要两个子模块:

```text
third_party/ish/deps/libarchive
third_party/ish/deps/libapps
```

它们由构建脚本自动初始化。

当前不初始化 `third_party/ish/deps/linux`。该目录是 iSH 上游 Linux kernel(内核) 子模块, 体积大, 上游默认 `update = none`, 只有后续要完整构建 `libiSHLinux` 路径时才需要单独拉取。

新增 Mira shell(命令解释器) 抽象层:

```text
/Users/vw2x/Projects/Reverses/Mira/native/include/mira/shell.h
/Users/vw2x/Projects/Reverses/Mira/native/src/shell/shell_core.c
```

当前行为:

1. macOS(苹果桌面系统) 和 iOS Simulator(iOS 模拟器) 默认走 `MIRA_SHELL_BACKEND_POSIX_PTY`。
2. 普通 iOS 真机 App 不默认走 POSIX `fork/exec`, 需要后续接 `MIRA_SHELL_BACKEND_ISH`。
3. `MIRA_SHELL_BACKEND_ISH` 已预留, 当前返回 `ENOSYS`, 表示接口已定但后端未接线。

## 构建脚本

新增脚本:

```bash
/Users/vw2x/Projects/Reverses/Mira/tools/ios/build-ish-libs.sh
```

默认构建 iPhoneSimulator(iOS 模拟器平台) 的 arm64(ARM 64 位架构) 版本:

```bash
/Users/vw2x/Projects/Reverses/Mira/tools/ios/build-ish-libs.sh
```

输出目录:

```text
/Users/vw2x/Projects/Reverses/Mira/build/ios-ish-libs/Debug-ApplePleaseFixFB19282108-iphonesimulator/meson/
```

关键产物:

```text
libish.a
libish_emu.a
libfakefs.a
```

## 本机验证结果

本机已经验证 iSH 核心静态库能构建成功。

验证命令:

```bash
MIRA_ISH_BUILD_DIR=/tmp/mira-ish-target-build \
  /Users/vw2x/Projects/Reverses/Mira/tools/ios/build-ish-libs.sh
```

成功产物:

```text
/tmp/mira-ish-target-build/Debug-ApplePleaseFixFB19282108-iphonesimulator/meson/libish.a
/tmp/mira-ish-target-build/Debug-ApplePleaseFixFB19282108-iphonesimulator/meson/libish_emu.a
/tmp/mira-ish-target-build/Debug-ApplePleaseFixFB19282108-iphonesimulator/meson/libfakefs.a
```

## 构建注意事项

1. iSH 的 Meson(构建系统) 需要 `meson` 和 `ninja`。
2. iSH 的 VDSO(虚拟动态共享对象) 构建需要 Homebrew LLVM(LLVM 编译器套件) 和 `ld.lld`。
3. 如果机器安装了 CommandLineTools(命令行工具), linker(链接器) 可能优先拿到 macOS(苹果桌面系统) 的 `libsqlite3.tbd`, 脚本会通过 `LDFLAGS=-L$SDK/usr/lib` 强制优先使用 iOS SDK(iOS 软件开发工具包) 的库路径。
4. 只构建 `libish`, `libish_emu`, `libfakefs` 三个 target(构建目标), 不构建完整 iSH App, 这样可以避开 FileProvider(文件提供器扩展) 链接问题。
5. 手动 target 构建时必须固定 `ARCHS=arm64`, 否则 Xcode 可能同时触发 x86_64(英特尔 64 位架构) 构建, 让 aarch64(ARM 64 位架构) 汇编文件被错误汇编。
6. 不要在最快 POC 路径里拉 `deps/linux`, 它下载慢且不是 `libish/libish_emu/libfakefs` 三个静态库的必要输入。
7. 如果本机 shell(命令行环境) 里有 `SDKROOT=/Library/Developer/CommandLineTools/...` 或 `LIBRARY_PATH=/Library/Developer/CommandLineTools/...`, Xcode(苹果开发工具) 可能把 macOS(苹果桌面系统) 的 `libobjc.A.tbd` 或 `libsqlite3.tbd` 链进 iOS Simulator(iOS 模拟器) 目标。脚本会清理这些环境变量, 手动构建 Mira iOS App 时也建议使用 `env -u SDKROOT -u LIBRARY_PATH xcodebuild ...`。

## Mira iOS App 构建验证

项目最低系统版本已调整为 iOS 16.0, 以支持当前连接的 iOS 16.7.10 真机。

本机 iOS Simulator(iOS 模拟器) 已打开:

```text
iPhone 17 Pro, UDID 2260242F-07BC-4946-95FB-1204D87F29BA
```

验证命令:

```bash
env -u LIBRARY_PATH -u SDKROOT xcodebuild \
  -project /Users/vw2x/Projects/Reverses/Mira/ios/Mira/Mira.xcodeproj \
  -scheme Mira \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'id=2260242F-07BC-4946-95FB-1204D87F29BA' \
  -derivedDataPath /Users/vw2x/Projects/Reverses/Mira/build/ios-mira-derived-cleanenv \
  build
```

验证结果:

```text
** BUILD SUCCEEDED **
```

并已安装启动:

```bash
xcrun simctl install 2260242F-07BC-4946-95FB-1204D87F29BA /Users/vw2x/Projects/Reverses/Mira/build/ios-mira-derived-cleanenv/Build/Products/Debug-iphonesimulator/Mira.app
xcrun simctl launch 2260242F-07BC-4946-95FB-1204D87F29BA com.vwww.mira.ios
```

## Mira iOS 真机构建验证

当前连接真机:

```text
iPhone, iOS 16.7.10, UDID b8b0fe95e9624225302276f374cb734e3dfeedaf
```

本机目前没有可用的 Apple Development(苹果开发签名证书) 身份:

```text
0 valid identities found
```

该状态后来已修复。当前可用签名身份:

```text
Apple Development: s1lver12138@outlook.com (6ART85UVA4)
TeamIdentifier: RCK3A5ACX3
```

unsigned build(不签名构建) 验证命令:

```bash
env -u LIBRARY_PATH -u SDKROOT xcodebuild \
  -project /Users/vw2x/Projects/Reverses/Mira/ios/Mira/Mira.xcodeproj \
  -scheme Mira \
  -configuration Debug \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /Users/vw2x/Projects/Reverses/Mira/build/ios-mira-device-unsigned-derived \
  CODE_SIGNING_ALLOWED=NO \
  build
```

验证结果:

```text
** BUILD SUCCEEDED **
```

签名构建当前阻塞在:

```text
Signing for "Mira" requires a development team.
```

该阻塞后来已修复。signed build(签名构建) 验证命令:

```bash
env -u LIBRARY_PATH -u SDKROOT xcodebuild \
  -project /Users/vw2x/Projects/Reverses/Mira/ios/Mira/Mira.xcodeproj \
  -scheme Mira \
  -configuration Debug \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /Users/vw2x/Projects/Reverses/Mira/build/ios-mira-device-signed-derived \
  build
```

验证结果:

```text
** BUILD SUCCEEDED **
```

签名产物:

```text
/Users/vw2x/Projects/Reverses/Mira/build/ios-mira-device-signed-derived/Build/Products/Debug-iphoneos/Mira.app
```

当前真机 install(安装) 阻塞在 Developer Mode(开发者模式) 未启用。`xcdevice` 显示:

```text
To use iPhone for development, enable Developer Mode in Settings -> Privacy & Security.
```

因此需要在真机上打开:

```text
Settings -> Privacy & Security -> Developer Mode
```

打开后重启并确认, 再重新连接 Mac(苹果电脑)。

iSH 真机静态库已验证:

```bash
MIRA_ISH_SDK=iphoneos \
MIRA_ISH_ARCHS=arm64 \
MIRA_ISH_BUILD_DIR=/Users/vw2x/Projects/Reverses/Mira/build/ios-ish-device-libs \
  /Users/vw2x/Projects/Reverses/Mira/tools/ios/build-ish-libs.sh
```

成功产物:

```text
/Users/vw2x/Projects/Reverses/Mira/build/ios-ish-device-libs/Debug-ApplePleaseFixFB19282108-iphoneos/meson/libish.a
/Users/vw2x/Projects/Reverses/Mira/build/ios-ish-device-libs/Debug-ApplePleaseFixFB19282108-iphoneos/meson/libish_emu.a
/Users/vw2x/Projects/Reverses/Mira/build/ios-ish-device-libs/Debug-ApplePleaseFixFB19282108-iphoneos/meson/libfakefs.a
```

## 下一步

下一步要做的是 Mira 自己的 iSH session(会话) 包装层:

```text
/Users/vw2x/Projects/Reverses/Mira/native/src/ios/ish_backend/
```

已落地的 C API:

```c
mira_shell_session_t *mira_shell_open(const mira_shell_options_t *options);
ssize_t mira_shell_read(mira_shell_session_t *session, void *buffer, size_t length);
ssize_t mira_shell_write(mira_shell_session_t *session, const void *buffer, size_t length);
int mira_shell_resize(mira_shell_session_t *session, int columns, int rows, int cell_width, int cell_height);
int mira_shell_wait_for(mira_shell_session_t *session);
int mira_shell_close(mira_shell_session_t *session);
```

远程协议继续复用 Android(安卓系统) 当前消息:

```text
terminal.input
terminal.output
terminal.resize
session.close
```
