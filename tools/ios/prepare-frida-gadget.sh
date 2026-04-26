#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CACHE_DIR="${MIRA_FRIDA_IOS_CACHE_DIR:-$ROOT_DIR/build/ios-frida-gadget}"
DEVICE_ARCHIVE="${MIRA_FRIDA_IOS_DEVICE_ARCHIVE:-$HOME/Downloads/frida-gadget-16.0.7-ios-universal.dylib.gz}"
SIM_ARCHIVE="${MIRA_FRIDA_IOS_SIM_ARCHIVE:-$HOME/Downloads/frida-gadget-16.0.7-ios-simulator-universal.dylib.xz}"

if [[ -z "${TARGET_BUILD_DIR:-}" || -z "${WRAPPER_NAME:-}" ]]; then
    OUTPUT_DIR="${MIRA_FRIDA_IOS_OUTPUT_DIR:-$ROOT_DIR/ios/Mira/Mira/Resources}"
else
    OUTPUT_DIR="$TARGET_BUILD_DIR/$WRAPPER_NAME"
fi

FRAMEWORKS_DIR="${OUTPUT_DIR}/Frameworks"
STAMP_FILE="${OUTPUT_DIR}/.mira-frida-gadget.stamp"
TARGET_DYLIB="${FRAMEWORKS_DIR}/libdynamic.dylib"
TARGET_CONFIG="${OUTPUT_DIR}/libdynamic.config"

mkdir -p "$CACHE_DIR" "$FRAMEWORKS_DIR"

if [[ "${PLATFORM_NAME:-}" == "iphonesimulator" || "${SDK_NAME:-}" == iphonesimulator* ]]; then
    SOURCE_ARCHIVE="$SIM_ARCHIVE"
    CACHE_DYLIB="${CACHE_DIR}/libdynamic-simulator.dylib"
    EXTRACT_CMD=(xz -dc)
    PLATFORM_LABEL="iphonesimulator"
else
    SOURCE_ARCHIVE="$DEVICE_ARCHIVE"
    CACHE_DYLIB="${CACHE_DIR}/libdynamic-device.dylib"
    EXTRACT_CMD=(gzip -dc)
    PLATFORM_LABEL="iphoneos"
fi

if [[ ! -f "$SOURCE_ARCHIVE" ]]; then
    echo "Missing Frida Gadget archive: $SOURCE_ARCHIVE" >&2
    exit 1
fi

if [[ ! -s "$CACHE_DYLIB" || "$SOURCE_ARCHIVE" -nt "$CACHE_DYLIB" ]]; then
    "${EXTRACT_CMD[@]}" "$SOURCE_ARCHIVE" > "${CACHE_DYLIB}.tmp"
    chmod 0755 "${CACHE_DYLIB}.tmp"
    mv "${CACHE_DYLIB}.tmp" "$CACHE_DYLIB"
fi

cp "$CACHE_DYLIB" "$TARGET_DYLIB"
chmod 0755 "$TARGET_DYLIB"

cat > "$TARGET_CONFIG" <<'EOF'
{
  "interaction": {
    "type": "listen",
    "address": "127.0.0.1",
    "port": 27042,
    "on_load": "resume"
  },
  "teardown": "minimal",
  "runtime": "default",
  "code_signing": "optional"
}
EOF

if [[ "${CODE_SIGNING_ALLOWED:-NO}" != "NO" && -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]]; then
    /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --timestamp=none "$TARGET_DYLIB"
fi

printf '%s %s\n' "$PLATFORM_LABEL" "$SOURCE_ARCHIVE" > "$STAMP_FILE"
echo "Prepared Frida Gadget for $PLATFORM_LABEL at $TARGET_DYLIB"
