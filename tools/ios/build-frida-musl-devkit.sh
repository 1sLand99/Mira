#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FRIDA_VERSION="${FRIDA_VERSION:-16.0.7}"
BUILD_ROOT="${MIRA_IOS_FRIDA_BUILD_ROOT:-$ROOT_DIR/build/ios-frida-musl}"
SOURCE_DIR="${MIRA_IOS_FRIDA_SOURCE_DIR:-$BUILD_ROOT/frida-$FRIDA_VERSION}"
OUTPUT_DIR="${MIRA_IOS_FRIDA_OUTPUT_DIR:-$ROOT_DIR/build/frida/devkit/$FRIDA_VERSION/linux-x86-musl}"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "This builder must run inside a native Linux x86 musl environment." >&2
  echo "Expected target: Alpine x86 or equivalent musl builder." >&2
  exit 1
fi

if [[ "$(uname -m)" != "i386" && "$(uname -m)" != "i486" && "$(uname -m)" != "i586" && "$(uname -m)" != "i686" ]]; then
  echo "This builder expects an x86 Linux userland." >&2
  echo "Current architecture: $(uname -m)" >&2
  exit 1
fi

for tool in git make python3 meson ninja gcc g++; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required tool: $tool" >&2
    exit 1
  fi
done

mkdir -p "$BUILD_ROOT" "$(dirname "$OUTPUT_DIR")"

if [[ ! -d "$SOURCE_DIR/.git" ]]; then
  git clone --branch "$FRIDA_VERSION" --recurse-submodules https://github.com/frida/frida.git "$SOURCE_DIR"
else
  git -C "$SOURCE_DIR" fetch --tags origin
  git -C "$SOURCE_DIR" checkout "$FRIDA_VERSION"
  git -C "$SOURCE_DIR" submodule update --init --recursive
fi

export FRIDA_LIBC=musl

cd "$SOURCE_DIR"
make core-linux-x86
python3 releng/devkit.py frida-core linux-x86 "$OUTPUT_DIR"

echo "Generated musl-native Frida devkit at: $OUTPUT_DIR"
