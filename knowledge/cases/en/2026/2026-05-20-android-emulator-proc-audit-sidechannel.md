# Android emulator proc audit side-channel exposes qemu SELinux context

## 1. Detection object

Android emulator environment from a third-party Mira app sandbox shell, using `/proc/<pid>` access as an audit log side-channel.

## 2. Initial suspicion

A normal emulator can be detected through direct properties such as `ro.kernel.qemu=1`, but the more interesting question was whether an emulator-specific signal exists in the same style as the Magisk proc audit side-channel case.

Observation: direct properties and device nodes were visible, but those are conventional emulator checks.

Interpretation: a stronger reusable case would come from audit records produced by the app sandbox touching protected `/proc/<pid>` entries.

Still needs verification: whether emulator-specific SELinux domains are visible through logcat on more Android versions and emulator images.

## 3. Topic candidate

`android-proc-audit-sidechannel-emulator-detection`

This candidate focuses on Android third-party app sandbox `/proc` access causing audit records that expose emulator-specific SELinux `tcontext` values.

## 4. Confirmed topic

Not confirmed. This is one concrete case on an Android 9 arm64 AVD image. More emulator versions, API levels, and physical-device baselines are needed before creating a topic.

## 5. Smells

1. Conventional emulator signals were too obvious, including `ro.kernel.qemu=1`, `ro.hardware=ranchu`, and `/dev/qemu_pipe`.
2. The Magisk case showed that `/proc/<pid>` access can reveal hidden security contexts even when direct process inspection is unavailable.
3. Emulator processes had distinctive SELinux domains from adb shell process context, especially `u:r:qemu_props:s0`.
4. Wide `/proc` scans can miss or bury the useful line because audit output is rate-limited and noisy.
5. Running a script through a different shell process can change the signal shape, so invocation model matters.

Noise or misdirection:

1. `ro.kernel.qemu=1` is valid but not the side-channel finding.
2. Generic `tcontext=u:r:init:s0` and `tcontext=u:r:kernel:s0` audit lines are expected on both emulator and physical devices.
3. Physical-device logs may contain unrelated granted audit records for Mira toolbox execution.

## 6. Key clues

1. On the AVD, adb shell process listing showed `qemu-props` with SELinux context `u:r:qemu_props:s0`.
2. Touching `/proc/1394` from the Mira app sandbox produced an audit denial with `tcontext=u:r:qemu_props:s0`.
3. A small chunk scan over `1390-1399` found the same signal automatically.
4. A physical Pixel 4 baseline over a comparable window did not produce `qemu`, `ranchu`, or `goldfish` `tcontext` matches.
5. Emulator-specific HAL process names included `android.hardware.health@2.0-service.goldfish` and `android.hardware.power@1.1-service.ranchu`, suggesting additional target domains may exist on other images.

Representative AVD hit:

```text
hit_window=1390-1399
05-20 16:42:23.822 ... avc: denied { getattr } for comm="sh" path="/proc/1394" dev="proc" ... scontext=u:r:untrusted_app:s0:c88,c256,c512,c768 tcontext=u:r:qemu_props:s0 tclass=dir permissive=0
```

Physical baseline result:

```text
no_qemu_ranchu_goldfish_tcontext_in_window
```

## 7. Validation actions

1. Started AVD `9` and confirmed `adb` serial `emulator-5554`.
2. Installed and launched Mira Android with relay URL `http://10.0.2.2:8765`.
3. Used Mira MCP `mira_run_command` inside the AVD app sandbox.
4. Collected direct emulator signals, including `ro.kernel.qemu=1`, `ro.hardware=ranchu`, `ro.boot.hardware=ranchu`, `/dev/qemu_pipe`, and `/dev/goldfish_pipe`.
5. Used adb shell process context listing to identify candidate emulator-specific process contexts.
6. Targeted `/proc/1388`, `/proc/1389`, `/proc/1394`, and `/proc/1399` from the Mira sandbox and inspected fresh logcat buffers.
7. Ran an automatic chunked scan with `START=1000 END=1700 CHUNK=10 STEP=10 WAIT_SEC=1 LOG_TAIL=400`.
8. Compared with a physical Pixel 4 Mira sandbox baseline and searched for `qemu`, `ranchu`, and `goldfish` `tcontext` values.

## 8. Script artifact and execution model

Case script artifact:

```text
knowledge/cases/artifacts/2026/2026-05-20-android-emulator-proc-audit-sidechannel.sh
```

Maintained reusable copy:

```text
tools/android/mira-emulator-audit-sidechannel.sh
```

Recommended invocation:

1. Paste the script content into `mira_run_command`, so it runs in the current Mira PTY shell.
2. Or write it to the device cache path and source it with `. /data/data/com.vwww.mira/cache/mira-emulator-audit-sidechannel.sh`.
3. Avoid `sh file` until proven equivalent, because the signal depends on the current shell process touching `/proc/<pid>`.

Known-good defaults from this case:

```sh
START=1000
END=2500
CHUNK=10
STEP=10
WAIT_SEC=1
LOG_TAIL=400
MATCH='tcontext=u:r:qemu_props:s0|tcontext=u:r:[^ ]*(goldfish|ranchu|qemu)[^ ]*:s0'
```

Minimal validation command:

```sh
START=1350 END=1420 CHUNK=10 STEP=10 . /data/data/com.vwww.mira/cache/mira-emulator-audit-sidechannel.sh
```

Expected AVD-style result:

```text
[probe] hit pid=1390-1399
tcontext=u:r:qemu_props:s0
```

## 9. Result

The side-channel was confirmed on the tested AVD. A third-party app sandbox touching `/proc/<pid>` can trigger audit records that expose emulator-specific SELinux `tcontext` values, most importantly `u:r:qemu_props:s0`.

Supported conclusion: the tested AVD leaked an emulator-specific SELinux domain through `/proc` audit records visible to the Mira app context.

Unsupported conclusion: this alone does not prove universal emulator detection across all Android emulator images, ROMs, API levels, or hardened logcat policies.

## 10. False-positive risk

1. `qemu_props`, `goldfish`, and `ranchu` domains are highly emulator-specific on normal Android devices, but unusual vendor test builds could theoretically reuse similar names.
2. Old logcat entries can create stale hits if buffers are not cleared before each decision window.
3. Audit rate limiting can hide a real hit when the scan window is too wide.
4. Android version, SELinux policy, logcat visibility, and app target SDK may affect observability.
5. Physical devices may contain unrelated strings such as `virt` in kernel thread names, so matching must be restricted to SELinux `tcontext` values.

## 11. Distilled judgment seeds

1. If a direct emulator property is visible, do not stop there. Look for a side-channel that exposes the backing emulator service domain.
2. For `/proc` audit probes, first identify likely target domains from adb shell `ps -AZ`, then tune the app-sandbox scan window around those PIDs.
3. Strong emulator side-channel signals should match SELinux `tcontext`, not arbitrary process names or property strings.
4. Keep scan chunks small enough to avoid audit noise and late-window misses.
5. Always clear logcat before each window, but treat `logcat -c` as isolation only, not as a substitute for chunk control.

## 12. Suggested next checks

1. Test Android 10 through Android 16 AVD images and compare whether `qemu_props` remains visible.
2. Test Play Store and non-Play Store images, because service composition may differ.
3. Scan for `hal_*goldfish*`, `hal_*ranchu*`, and `qemu_props` domains on each image.
4. Compare direct property detection against audit side-channel detection under restricted logcat conditions.
5. Verify whether `CHUNK=10` is still necessary or whether `CHUNK=50 STEP=25` is reliable enough.
6. Capture a negative baseline on more physical devices and vendor ROMs.

## 13. Linked articles

None yet. Keep this as a case until multiple emulator images confirm stable boundaries and failure modes.
