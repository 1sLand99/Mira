# Android high-PID shell proc audit side-channel hints at scrcpy projection

## 1. Detection object

Possible Android screen projection through `scrcpy`, observed from a third-party Mira app sandbox using high-PID `/proc/<pid>` audit records that expose `u:r:shell:s0` targets.

## 2. Initial suspicion

The device was already being mirrored. From adb shell, the process table showed high-PID `shell` processes, including an `sh -> app_process -> app_process` chain consistent with a host-driven projection or automation server.

Observation: the interesting process group was not an installed app process. It ran under the Android `shell` user and `u:r:shell:s0` SELinux context.

Interpretation: an app sandbox may not directly inspect these processes, but touching `/proc/<pid>` can still trigger audit records that leak the target SELinux context.

Still needs verification: whether the same high-PID shell pattern uniquely identifies `scrcpy`, or only indicates adb-originated shell automation.

## 3. Topic candidate

`android-proc-audit-sidechannel-adb-shell-automation-detection`

This candidate covers third-party app sandbox `/proc` audit side-channels that expose high-PID adb shell automation processes. `scrcpy` is one concrete suspected source.

## 4. Confirmed topic

Not confirmed. This is a single case on a Pixel 4 during an active mirrored session. It should remain a case until there are more positive and negative baselines.

## 5. Smells

1. The suspected projection process was high-PID and `shell`-owned, not an ordinary app package.
2. The process table showed `sh` spawning `app_process`, which is a known execution style for Android host-side tools that start Java code through adb shell.
3. From the app sandbox, direct process details are restricted, but audit records still reveal `tcontext=u:r:shell:s0`.
4. High-PID `shell` contexts can also come from ordinary adb sessions, so the signal is suspicious but not conclusive.
5. Wide scans create audit noise and may hide the exact high-PID shell target.

Noise or misdirection:

1. `tcontext=u:r:shell:s0` alone is not proof of `scrcpy`.
2. Low-PID shell processes such as persistent adb helpers may be normal.
3. Kernel worker high PIDs are common and should not be treated as projection evidence.
4. Mira toolbox execution can add unrelated audit entries.

## 6. Key clues

1. adb shell process listing during active projection showed high-PID `shell` entries:

```text
u:r:shell:s0 shell 27864 1747 ... S sh
u:r:shell:s0 shell 27866 27864 ... S app_process
u:r:shell:s0 shell 27885 27866 ... S app_process
```

2. Mira app sandbox access to high PID `/proc/27864` produced a logcat audit denial with `tcontext=u:r:shell:s0`:

```text
avc: denied { getattr } for comm="sh" path="/proc/27864" ... scontext=u:r:untrusted_app_27:s0:... tcontext=u:r:shell:s0 ... app=com.vwww.mira
```

3. A separate targeted check on `/proc/11814` also produced `tcontext=u:r:shell:s0`, confirming that high-PID shell contexts are observable through the side-channel.
4. The signal was observed from the Mira app sandbox rather than from privileged adb shell inspection.

## 7. Validation actions

1. Confirmed the physical device was connected and actively mirrored.
2. Ran adb shell `ps -AZ` and searched for `shell`, `app_process`, and projection-related process shapes.
3. Identified a high-PID `sh -> app_process -> app_process` chain under `u:r:shell:s0`.
4. Opened a Mira MCP shell in the app sandbox.
5. Cleared logcat before each probe window with `/system/bin/logcat -c -b all`.
6. Touched candidate `/proc/<pid>` directories from the Mira shell using shell builtin `[ -d "/proc/$p" ]`.
7. Read the fresh logcat window and searched for high-PID `tcontext=u:r:shell:s0` records.

## 8. Script artifact and execution model

Case script artifact:

```text
knowledge/cases/artifacts/2026/2026-05-20-android-high-pid-shell-audit-sidechannel-scrcpy.sh
```

Maintained reusable copy:

```text
tools/android/mira-high-pid-shell-audit-sidechannel.sh
```

Recommended invocation:

1. Paste the script into `mira_run_command`, so the current Mira PTY shell touches `/proc/<pid>`.
2. Or source it with `. /data/data/com.vwww.mira/cache/mira-high-pid-shell-audit-sidechannel.sh`.
3. Avoid `sh file` until proven equivalent.
4. Use small windows around suspected high-PID shell ranges when adb-side process context is available.

Known-good defaults:

```sh
START=10000
END=32000
CHUNK=50
STEP=50
WAIT_SEC=1
LOG_TAIL=1200
MATCH='path="/proc/[1-9][0-9][0-9][0-9][0-9]".*tcontext=u:r:shell:s0'
```

Minimal targeted validation model:

```sh
/system/bin/logcat -c -b all >/dev/null 2>&1
[ -d /proc/<suspected-high-pid-shell> ] >/dev/null 2>&1
sleep 1
/system/bin/logcat -d -b all -t 500 | grep 'tcontext=u:r:shell:s0'
```

## 9. Result

The side-channel was confirmed as a way for the Mira app sandbox to observe high-PID `u:r:shell:s0` targets through `/proc` audit records.

Supported conclusion: during an active mirrored session, high-PID shell processes consistent with adb-driven projection were visible to the app sandbox as `tcontext=u:r:shell:s0` audit targets.

Unsupported conclusion: this case does not prove that every high-PID `shell` process is `scrcpy`, or that the app sandbox can identify the command name without external correlation.

## 10. False-positive risk

1. Any adb shell automation can create high-PID `u:r:shell:s0` processes.
2. `scrcpy`, test runners, shell scripts, installers, and manual adb sessions may look similar from this side-channel.
3. The audit line exposes SELinux context and PID path, not the process command line.
4. Old logcat entries can create stale hits if buffers are not cleared.
5. PID ranges are device-state dependent and should not be hardcoded.

## 11. Distilled judgment seeds

1. Treat high-PID `u:r:shell:s0` as an adb-automation smell, not a final verdict.
2. `sh -> app_process -> app_process` under `u:r:shell:s0` is a stronger clue than `shell` context alone.
3. The app-side side-channel can detect the presence of shell-domain targets, while adb-side correlation explains likely tool identity.
4. For projection detection, combine high-PID shell audit hits with screen-capture or display-service signals before calling it `scrcpy`.
5. Keep the detection wording as possible projection or adb automation unless command identity is independently verified.

## 12. Suggested next checks

1. Start and stop `scrcpy` while keeping Mira alive, then compare high-PID shell audit hits before and after.
2. Compare against plain `adb shell sleep`, instrumentation tests, and install sessions.
3. Look for additional audit side-channels around media projection, display, or virtual display services.
4. Test whether `/proc/<pid>/cmdline` or `/proc/<pid>/status` creates more specific audit metadata on other Android versions.
5. Build a scoring rule that separates generic adb automation from likely projection.

## 13. Linked articles

None yet. Keep this as a case until there are controlled start-stop baselines for `scrcpy` and non-scrcpy adb automation.
