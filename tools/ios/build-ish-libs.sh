#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ISH_DIR="$ROOT_DIR/third_party/ish"

CONFIGURATION="${MIRA_ISH_CONFIGURATION:-Debug-ApplePleaseFixFB19282108}"
SDK_NAME="${MIRA_ISH_SDK:-iphonesimulator}"
ARCHS_VALUE="${MIRA_ISH_ARCHS:-arm64}"
BUILD_DIR="${MIRA_ISH_BUILD_DIR:-$ROOT_DIR/build/ios-ish-libs}"
LOG_FILE="$BUILD_DIR/build.log"

if [[ ! -d "$ISH_DIR/.git" && ! -f "$ISH_DIR/.git" ]]; then
    echo "iSH submodule is missing: $ISH_DIR" >&2
    echo "Run: git submodule update --init --depth 1 third_party/ish" >&2
    exit 1
fi

if ! command -v meson >/dev/null 2>&1; then
    echo "meson is required for iSH static library build." >&2
    echo "Install with: python3 -m pip install --user meson" >&2
    exit 1
fi

if ! command -v ninja >/dev/null 2>&1; then
    echo "ninja is required for iSH static library build." >&2
    echo "Install with Homebrew or pip before running this script." >&2
    exit 1
fi

if [[ ! -x /opt/homebrew/opt/llvm/bin/clang || -z "$(command -v ld.lld || true)" ]]; then
    echo "Homebrew LLVM with ld.lld is required by iSH VDSO build." >&2
    echo "Install with: brew install llvm lld" >&2
    exit 1
fi

git -C "$ISH_DIR" submodule update --init --depth 1 deps/libarchive deps/libapps

mkdir -p "$BUILD_DIR"

# Avoid host CommandLineTools SDK paths leaking into iOS Simulator/iPhoneOS
# builds through the parent shell environment.
unset SDKROOT
unset LIBRARY_PATH
unset CPATH
unset C_INCLUDE_PATH
unset CPLUS_INCLUDE_PATH
unset OBJC_INCLUDE_PATH

SDK_PATH="$(xcrun --sdk "$SDK_NAME" --show-sdk-path)"

# Meson in iSH discovers sqlite3 through the host linker. On machines with
# CommandLineTools installed, ld may pick the macOS libsqlite3.tbd first.
# Keep the iOS SDK library path first so the generated static libraries target
# iPhoneSimulator/iPhoneOS consistently.
export LDFLAGS="-L$SDK_PATH/usr/lib ${LDFLAGS:-}"

xcodebuild \
    -project "$ISH_DIR/iSH.xcodeproj" \
    -target libish \
    -target libish_emu \
    -target libfakefs \
    -configuration "$CONFIGURATION" \
    -sdk "$SDK_NAME" \
    SYMROOT="$BUILD_DIR" \
    OBJROOT="$BUILD_DIR" \
    ARCHS="$ARCHS_VALUE" \
    ONLY_ACTIVE_ARCH=YES \
    build 2>&1 | tee "$LOG_FILE"

PRODUCT_DIR="$BUILD_DIR/$CONFIGURATION-$SDK_NAME/meson"
required=(
    "$PRODUCT_DIR/libish.a"
    "$PRODUCT_DIR/libish_emu.a"
    "$PRODUCT_DIR/libfakefs.a"
)

for archive in "${required[@]}"; do
    if [[ ! -f "$archive" ]]; then
        echo "Missing expected iSH archive: $archive" >&2
        echo "Build log: $LOG_FILE" >&2
        exit 1
    fi
done

echo "iSH static libraries are ready:"
for archive in "${required[@]}"; do
    ls -lh "$archive"
done
echo "Build log: $LOG_FILE"
