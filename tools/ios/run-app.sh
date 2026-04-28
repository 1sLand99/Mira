#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_PATH="${ROOT_DIR}/ios/Mira/Mira.xcodeproj"
SCHEME="${MIRA_IOS_SCHEME:-Mira}"
DEVICE_NAME="${MIRA_IOS_DEVICE:-iPhone 17 Pro}"
TARGET="${MIRA_IOS_TARGET:-auto}"
BUNDLE_ID="${MIRA_IOS_BUNDLE_ID:-com.vwww.mira.ios}"
AUTO_LAUNCH_DEVICE="${MIRA_IOS_AUTO_LAUNCH_DEVICE:-0}"
AUTO_CONNECT_RELAY_URL="${MIRA_IOS_RELAY_URL:-}"
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
  MIRA_IOS_AUTO_LAUNCH_DEVICE  1 to auto launch after physical-device install. Default 0
  MIRA_IOS_RELAY_URL    Relay URL to inject at launch time for automated connect
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

launch_device_app_with_devicectl() {
  local device_id="$1"
  local bundle_id="$2"
  local output
  local status

  if ! command -v xcrun >/dev/null 2>&1; then
    return 127
  fi

  set +e
  output="$(xcrun devicectl device process launch \
    --device "${device_id}" \
    --terminate-existing \
    --activate \
    "${bundle_id}" 2>&1)"
  status=$?
  set -e

  printf '%s\n' "${output}"
  return "${status}"
}

install_device_app() {
  local ios_deploy="$1"
  local device_id="$2"
  local app_path="$3"
  local bundle_id="$4"
  local output
  local status

  if has_idb; then
    install_device_app_with_idb "${device_id}" "${app_path}"
    return 0
  fi

  set +e
  output="$("${ios_deploy}" \
    --id "${device_id}" \
    --bundle "${app_path}" \
    --faster-path-search 2>&1)"
  status=$?
  set -e

  printf '%s\n' "${output}"
  if [[ ${status} -eq 0 ]]; then
    return 0
  fi

  if [[ "${output}" == *"0xe8000067"* || "${output}" == *"internal API error"* ]]; then
    echo "Install hit internal API error, retrying after uninstall ..." >&2
    "${ios_deploy}" \
      --id "${device_id}" \
      --bundle_id "${bundle_id}" \
      --uninstall_only \
      --faster-path-search >/dev/null 2>&1 || true

    "${ios_deploy}" \
      --id "${device_id}" \
      --bundle "${app_path}" \
      --uninstall \
      --faster-path-search
    return 0
  fi

  return "${status}"
}

ensure_idb() {
  local user_base
  if command -v idb >/dev/null 2>&1; then
    command -v idb
    return
  fi

  user_base="$(python3 -m site --user-base 2>/dev/null || true)"
  if [[ -n "${user_base}" && -x "${user_base}/bin/idb" ]]; then
    printf '%s\n' "${user_base}/bin/idb"
    return
  fi

  echo "idb not found. Install fb-idb client and idb-companion first." >&2
  echo "Docs: https://fbidb.io/docs/installation/" >&2
  exit 1
}

has_idb() {
  command -v idb >/dev/null 2>&1 || [[ -x "$(python3 -m site --user-base 2>/dev/null || true)/bin/idb" ]]
}

connect_idb_target() {
  local idb_bin="$1"
  local device_id="$2"
  "${idb_bin}" connect "${device_id}" >/dev/null
}

install_device_app_with_idb() {
  local device_id="$1"
  local app_path="$2"
  local idb_bin

  idb_bin="$(ensure_idb)"
  connect_idb_target "${idb_bin}" "${device_id}"
  "${idb_bin}" install --udid "${device_id}" "${app_path}"
}

launch_device_app_with_idb() {
  local device_id="$1"
  local bundle_id="$2"
  local relay_url="$3"
  local idb_bin

  idb_bin="$(ensure_idb)"
  connect_idb_target "${idb_bin}" "${device_id}"
  if [[ -n "${relay_url}" ]]; then
    IDB_MIRA_RELAY_URL="${relay_url}" IDB_MIRA_AUTO_CONNECT=1 "${idb_bin}" launch --udid "${device_id}" "${bundle_id}"
  else
    "${idb_bin}" launch --udid "${device_id}" "${bundle_id}"
  fi
}

launch_device_app() {
  local ios_deploy="$1"
  local device_id="$2"
  local app_path="$3"
  local bundle_id="$4"
  local relay_url="$5"

  if has_idb; then
    launch_device_app_with_idb "${device_id}" "${bundle_id}" "${relay_url}"
    return 0
  fi

  local output
  local status

  if output="$(launch_device_app_with_devicectl "${device_id}" "${bundle_id}")"; then
    printf '%s\n' "${output}"
    return 0
  fi
  status=$?
  printf '%s\n' "${output}"
  echo "devicectl launch failed, falling back to ios-deploy ..." >&2

  set +e
  output="$("${ios_deploy}" \
    --id "${device_id}" \
    --bundle "${app_path}" \
    --noinstall \
    --justlaunch \
    --noninteractive \
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
  install_device_app "${ios_deploy}" "${device_id}" "${DEVICE_APP_PATH}" "${BUNDLE_ID}"

  if [[ "${AUTO_LAUNCH_DEVICE}" == "1" ]]; then
    echo "Restarting Mira app ..."
    launch_device_app "${ios_deploy}" "${device_id}" "${DEVICE_APP_PATH}" "${BUNDLE_ID}" "${AUTO_CONNECT_RELAY_URL}"
    launch_note="Auto launch attempted."
  else
    launch_note="Auto launch skipped on physical device by default. Open Mira manually, or set MIRA_IOS_AUTO_LAUNCH_DEVICE=1. If idb is installed, MIRA_IOS_RELAY_URL can be injected for auto connect."
  fi

  cat <<MSG

Mira iOS app installed on device.
Project: ${PROJECT_PATH}
Device ID: ${device_id}
Bundle: ${BUNDLE_ID}
App: ${DEVICE_APP_PATH}
Note: ${launch_note}

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
