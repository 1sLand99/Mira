#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_PATH="${ROOT_DIR}/ios/Mira/Mira.xcodeproj"
SCHEME="${MIRA_IOS_SCHEME:-Mira}"
DEVICE_NAME="${MIRA_IOS_DEVICE:-iPhone 17 Pro}"
TARGET="${MIRA_IOS_TARGET:-auto}"
BUNDLE_ID="${MIRA_IOS_BUNDLE_ID:-com.vwww.mira.ios}"
SIM_DERIVED_DATA="${MIRA_IOS_SIM_DERIVED_DATA:-${ROOT_DIR}/build/ios/DerivedData}"
SIM_APP_PATH="${SIM_DERIVED_DATA}/Build/Products/Debug-iphonesimulator/Mira.app"
DEVICE_DERIVED_DATA="${MIRA_IOS_DEVICE_DERIVED_DATA:-${ROOT_DIR}/build/ios-mira-device-native-relay-derived}"
DEVICE_APP_PATH="${DEVICE_DERIVED_DATA}/Build/Products/Debug-iphoneos/Mira.app"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'MSG'
Usage: ./mira-ios [--device|--simulator]

Builds the Mira iOS app, installs it, and restarts it.

Default target is auto:
  1. use a connected physical iOS device when ios-deploy can see one
  2. otherwise fall back to the booted iOS Simulator

Environment variables:
  MIRA_IOS_TARGET       auto, device, or simulator. Default auto
  MIRA_IOS_DEVICE_ID    physical device UDID. If empty, first USB device from ios-deploy is used
  MIRA_IOS_DEPLOY       ios-deploy executable path. Default local build/ios-tools, then PATH
  MIRA_IOS_DEVICE       Simulator device name. Default iPhone 17 Pro
  MIRA_IOS_SCHEME       Xcode scheme. Default Mira
  MIRA_IOS_BUNDLE_ID    Bundle identifier. Default com.vwww.mira.ios
MSG
  exit 0
fi

case "${1:-}" in
  --device)
    TARGET="device"
    shift
    ;;
  --simulator)
    TARGET="simulator"
    shift
    ;;
esac

if [[ $# -gt 0 ]]; then
  echo "Unknown argument: $1" >&2
  echo "Run ./mira-ios --help for usage." >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild not found. Install Xcode and run xcode-select first." >&2
  exit 1
fi
if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun not found. Install Xcode and run xcode-select first." >&2
  exit 1
fi
if [[ ! -d "${PROJECT_PATH}" ]]; then
  echo "Missing iOS project: ${PROJECT_PATH}" >&2
  exit 1
fi

ensure_ios_deploy() {
  if [[ -n "${MIRA_IOS_DEPLOY:-}" ]]; then
    if [[ -x "${MIRA_IOS_DEPLOY}" ]]; then
      printf '%s\n' "${MIRA_IOS_DEPLOY}"
      return
    fi
    echo "MIRA_IOS_DEPLOY is not executable: ${MIRA_IOS_DEPLOY}" >&2
    exit 1
  fi

  local local_ios_deploy="${ROOT_DIR}/build/ios-tools/node_modules/.bin/ios-deploy"
  if [[ -x "${local_ios_deploy}" ]]; then
    printf '%s\n' "${local_ios_deploy}"
    return
  fi

  if command -v ios-deploy >/dev/null 2>&1; then
    command -v ios-deploy
    return
  fi

  if ! command -v npm >/dev/null 2>&1; then
    echo "ios-deploy not found. Install it or set MIRA_IOS_DEPLOY=/path/to/ios-deploy." >&2
    exit 1
  fi

  echo "Installing local ios-deploy ..." >&2
  mkdir -p "${ROOT_DIR}/build/ios-tools"
  if [[ ! -f "${ROOT_DIR}/build/ios-tools/package.json" ]]; then
    cat >"${ROOT_DIR}/build/ios-tools/package.json" <<'JSON'
{
  "dependencies": {
    "ios-deploy": "^1.12.2"
  }
}
JSON
  fi
  npm --prefix "${ROOT_DIR}/build/ios-tools" install >&2

  if [[ ! -x "${local_ios_deploy}" ]]; then
    echo "ios-deploy install did not produce ${local_ios_deploy}" >&2
    exit 1
  fi
  printf '%s\n' "${local_ios_deploy}"
}

detect_ios_device_id() {
  local ios_deploy="$1"
  if [[ -n "${MIRA_IOS_DEVICE_ID:-}" ]]; then
    printf '%s\n' "${MIRA_IOS_DEVICE_ID}"
    return
  fi

  "${ios_deploy}" --detect --faster-path-search 2>/dev/null | awk '
    /through USB/ && !usb { usb=$3 }
    /Found/ && !any { any=$3 }
    END {
      if (usb) print usb
      else if (any) print any
    }
  '
}

launch_device_app() {
  local ios_deploy="$1"
  local device_id="$2"
  local app_path="$3"
  local output
  local status

  set +e
  output="$("${ios_deploy}" \
    --id "${device_id}" \
    --bundle "${app_path}" \
    --noinstall \
    --debug \
    --justlaunch \
    --faster-path-search 2>&1)"
  status=$?
  set -e

  printf '%s\n' "${output}"
  if [[ "${output}" == *"error: Cannot launch"* || "${output}" == *"invalid code signature"* ]]; then
    return 1
  fi
  if [[ ${status} -ne 0 && "${output}" != *"success"* ]]; then
    return "${status}"
  fi
}

run_device() {
  local ios_deploy="$1"
  local device_id="$2"

  if [[ -z "${device_id}" ]]; then
    echo "No physical iOS device found. Connect a device or run ./mira-ios --simulator." >&2
    exit 1
  fi

  echo "Building Mira for physical iOS device: ${device_id}"
  env -u SDKROOT -u LIBRARY_PATH xcodebuild \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -configuration Debug \
    -sdk iphoneos \
    -destination "id=${device_id}" \
    -derivedDataPath "${DEVICE_DERIVED_DATA}" \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    ENABLE_DEBUG_DYLIB=NO \
    ENABLE_PREVIEWS=NO \
    build

  if [[ ! -d "${DEVICE_APP_PATH}" ]]; then
    echo "Built app not found: ${DEVICE_APP_PATH}" >&2
    exit 1
  fi

  echo "Stopping existing Mira app if it is running ..."
  "${ios_deploy}" \
    --id "${device_id}" \
    --bundle_id "${BUNDLE_ID}" \
    --kill \
    --faster-path-search >/dev/null 2>&1 || true

  echo "Installing Mira app with ios-deploy ..."
  "${ios_deploy}" \
    --id "${device_id}" \
    --bundle "${DEVICE_APP_PATH}" \
    --faster-path-search

  echo "Restarting Mira app ..."
  launch_device_app "${ios_deploy}" "${device_id}" "${DEVICE_APP_PATH}"

  cat <<MSG

Mira iOS app installed and restarted on device.
Project: ${PROJECT_PATH}
Device ID: ${device_id}
Bundle: ${BUNDLE_ID}
App: ${DEVICE_APP_PATH}

MSG
}

run_simulator() {
  local booted_device
  booted_device="$(xcrun simctl list devices booted | awk -F '[()]' '/Booted/ {print $2; exit}')"
  if [[ -z "${booted_device}" ]]; then
    echo "Booting simulator: ${DEVICE_NAME}"
    xcrun simctl boot "${DEVICE_NAME}"
  fi
  open -a Simulator

  env -u SDKROOT -u LIBRARY_PATH xcodebuild \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -configuration Debug \
    -destination "platform=iOS Simulator,name=${DEVICE_NAME}" \
    -derivedDataPath "${SIM_DERIVED_DATA}" \
    CODE_SIGNING_ALLOWED=NO \
    build

  if [[ ! -d "${SIM_APP_PATH}" ]]; then
    echo "Built app not found: ${SIM_APP_PATH}" >&2
    exit 1
  fi

  xcrun simctl terminate booted "${BUNDLE_ID}" >/dev/null 2>&1 || true
  xcrun simctl install booted "${SIM_APP_PATH}"
  xcrun simctl launch booted "${BUNDLE_ID}"

  cat <<MSG

Mira iOS app installed and restarted on simulator.
Project: ${PROJECT_PATH}
Device: ${DEVICE_NAME}
Bundle: ${BUNDLE_ID}
App: ${SIM_APP_PATH}

MSG
}

case "${TARGET}" in
  auto)
    IOS_DEPLOY="$(ensure_ios_deploy)"
    DEVICE_ID="$(detect_ios_device_id "${IOS_DEPLOY}")"
    if [[ -n "${DEVICE_ID}" ]]; then
      run_device "${IOS_DEPLOY}" "${DEVICE_ID}"
    else
      run_simulator
    fi
    ;;
  device)
    IOS_DEPLOY="$(ensure_ios_deploy)"
    DEVICE_ID="$(detect_ios_device_id "${IOS_DEPLOY}")"
    run_device "${IOS_DEPLOY}" "${DEVICE_ID}"
    ;;
  simulator|sim)
    run_simulator
    ;;
  *)
    echo "Invalid MIRA_IOS_TARGET: ${TARGET}. Use auto, device, or simulator." >&2
    exit 1
    ;;
esac
