#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_ID="${MIRA_ANDROID_APP_ID:-com.vwww.mira}"
ACTIVITY="${MIRA_ANDROID_ACTIVITY:-com.vwww.mira/.MainActivity}"
APK_PATH="${MIRA_ANDROID_APK_PATH:-${ROOT_DIR}/android/app/build/outputs/apk/debug/mira-app-debug.apk}"
AUTO_LAUNCH="${MIRA_ANDROID_AUTO_LAUNCH:-1}"
RELAY_URL="${MIRA_ANDROID_RELAY_URL:-}"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'MSG'
Usage: ./mira-android

Builds the Mira Android app, installs it with adb, and optionally launches it.

Environment variables:
  MIRA_ANDROID_APP_ID       Android applicationId. Default com.vwww.mira
  MIRA_ANDROID_ACTIVITY     Launch activity. Default com.vwww.mira/.MainActivity
  MIRA_ANDROID_APK_PATH     Built APK path
  MIRA_ANDROID_AUTO_LAUNCH  1 to launch after install. Default 1
  MIRA_ANDROID_RELAY_URL    Relay URL to inject into Activity extras for auto connect
  MIRA_ANDROID_ADB_SERIAL   adb serial to target. If empty, use default adb device
MSG
  exit 0
fi

adb_cmd() {
  if [[ -n "${MIRA_ANDROID_ADB_SERIAL:-}" ]]; then
    adb -s "${MIRA_ANDROID_ADB_SERIAL}" "$@"
  else
    adb "$@"
  fi
}

if ! command -v adb >/dev/null 2>&1; then
  echo "adb not found. Install Android platform-tools first." >&2
  exit 1
fi

if [[ ! -x "${ROOT_DIR}/gradlew" ]]; then
  echo "Missing gradlew at ${ROOT_DIR}/gradlew" >&2
  exit 1
fi

echo "Building Mira Android debug APK ..."
(cd "${ROOT_DIR}" && ./gradlew :mira-app:assembleDebug)

if [[ ! -f "${APK_PATH}" ]]; then
  echo "Built APK not found: ${APK_PATH}" >&2
  exit 1
fi

echo "Installing Mira Android APK ..."
adb_cmd install -r "${APK_PATH}"

if [[ "${AUTO_LAUNCH}" != "1" ]]; then
  cat <<MSG

Mira Android app installed.
APK: ${APK_PATH}
Package: ${APP_ID}
Note: Auto launch skipped. Set MIRA_ANDROID_AUTO_LAUNCH=1 to launch automatically.

MSG
  exit 0
fi

echo "Launching Mira Android app ..."
adb_cmd shell am force-stop "${APP_ID}" >/dev/null 2>&1 || true
if [[ -n "${RELAY_URL}" ]]; then
  adb_cmd shell am start \
    -n "${ACTIVITY}" \
    -a android.intent.action.MAIN \
    -c android.intent.category.LAUNCHER \
    --es mira_relay_url "${RELAY_URL}" \
    --ez mira_auto_connect true
else
  adb_cmd shell am start \
    -n "${ACTIVITY}" \
    -a android.intent.action.MAIN \
    -c android.intent.category.LAUNCHER
fi

cat <<MSG

Mira Android app installed and launched.
APK: ${APK_PATH}
Package: ${APP_ID}
Relay: ${RELAY_URL:-<not-set>}

MSG
