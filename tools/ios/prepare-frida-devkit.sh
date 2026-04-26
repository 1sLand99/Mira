#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="${MIRA_FRIDA_IOS_VERSION:-16.0.7}"
CACHE_DIR="${MIRA_FRIDA_IOS_DEVKIT_CACHE_DIR:-$ROOT_DIR/build/ios-frida-devkit-cache}"
OUTPUT_ROOT="${MIRA_FRIDA_IOS_DEVKIT_OUTPUT_DIR:-$ROOT_DIR/build/ios-frida-devkit}"

if [[ "${PLATFORM_NAME:-}" == "iphonesimulator" || "${SDK_NAME:-}" == iphonesimulator* ]]; then
    PLATFORM_DIR="iphonesimulator"
    ASSET_NAME="frida-core-devkit-${VERSION}-ios-arm64-simulator.tar.xz"
else
    PLATFORM_DIR="iphoneos"
    ASSET_NAME="frida-core-devkit-${VERSION}-ios-arm64.tar.xz"
fi

OUTPUT_DIR="${OUTPUT_ROOT}/${PLATFORM_DIR}"
ARCHIVE="${CACHE_DIR}/${ASSET_NAME}"
STAMP_FILE="${OUTPUT_DIR}/.mira-frida-devkit.stamp"
ASSET_URL="${MIRA_FRIDA_IOS_DEVKIT_URL:-https://github.com/frida/frida/releases/download/${VERSION}/${ASSET_NAME}}"

mkdir -p "$CACHE_DIR" "$OUTPUT_ROOT"

if [[ ! -s "$ARCHIVE" ]]; then
    echo "Downloading Frida iOS devkit: $ASSET_URL"
    curl -fL --retry 3 --connect-timeout 20 -o "${ARCHIVE}.tmp" "$ASSET_URL"
    mv "${ARCHIVE}.tmp" "$ARCHIVE"
fi

if [[ ! -f "${OUTPUT_DIR}/frida-core.h" || ! -f "${OUTPUT_DIR}/libfrida-core.a" || "$ARCHIVE" -nt "$STAMP_FILE" ]]; then
    rm -rf "$OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"
    tar -xJf "$ARCHIVE" -C "$OUTPUT_DIR"
fi

printf '%s %s\n' "$VERSION" "$ASSET_NAME" > "$STAMP_FILE"
echo "Prepared Frida devkit for ${PLATFORM_DIR} at ${OUTPUT_DIR}"
