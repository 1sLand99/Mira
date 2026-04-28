# Mira repo notes

## iOS true device automation baseline

1. 真机构建不要用 `generic/platform=iOS` 兜底验证, 要用真实设备 `destination`.
2. 真机构建前要清掉宿主机库路径污染, 固定使用 `env -u LIBRARY_PATH -u SDKROOT xcodebuild ...`.
3. 当前已验证可成功的真机命令如下:

```bash
env -u LIBRARY_PATH -u SDKROOT \
xcodebuild \
  -project <path-to-mira-repo>/ios/Mira/Mira.xcodeproj \
  -scheme Mira \
  -configuration Debug \
  -sdk iphoneos \
  -destination 'id=<device-udid>' \
  -derivedDataPath <path-to-mira-repo>/build/ios-mira-device-native-relay-derived \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  ENABLE_DEBUG_DYLIB=NO \
  ENABLE_PREVIEWS=NO \
  build
```

4. `libbsm` `ldl` `lresolv` 这些链接项不要为了表面报错直接删掉, 它们很可能属于 iSH / Frida 兼容链路.
5. `idb` 已验证可以连上真机并完成安装启动, 推荐顺序是 `idb connect` -> `idb install --udid` -> `idb launch --udid`.
6. `idb launch` 传启动环境变量时, 直接使用 `IDB_` 前缀, 启动到 App 内后会去掉前缀.
7. 当前已验证可工作的自动启动示例:

```bash
idb connect <device-udid>
idb install --udid <device-udid> <path-to-mira-repo>/build/ios-mira-device-native-relay-derived/Build/Products/Debug-iphoneos/Mira.app
IDB_MIRA_RELAY_URL="http://<host-ip>:8765" \
IDB_MIRA_AUTO_CONNECT=1 \
idb launch --udid <device-udid> com.vwww.mira.ios
```
