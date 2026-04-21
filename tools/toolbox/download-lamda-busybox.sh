#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LAMDA_RELEASE_TAG="${LAMDA_RELEASE_TAG:-v9.25}"
LAMDA_RELEASE_URL="https://github.com/firerpa/lamda/releases/tag/${LAMDA_RELEASE_TAG}"
ASSET_DIR="$ROOT_DIR/android/app/src/main/assets/toolbox/busybox"
MANIFEST_PATH="$ROOT_DIR/android/app/src/main/assets/toolbox/manifest.json"
TMP_DIR="${TMP_DIR:-$ROOT_DIR/.mira/tmp/lamda-busybox-${LAMDA_RELEASE_TAG}}"
ABI_ORDER="arm64-v8a armeabi-v7a x86 x86_64"

cleanup() {
  if [[ "${KEEP_TOOLBOX_DOWNLOADS:-0}" != "1" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

ROOT_DIR="$ROOT_DIR" \
LAMDA_RELEASE_TAG="$LAMDA_RELEASE_TAG" \
LAMDA_RELEASE_URL="$LAMDA_RELEASE_URL" \
ASSET_DIR="$ASSET_DIR" \
MANIFEST_PATH="$MANIFEST_PATH" \
TMP_DIR="$TMP_DIR" \
ABI_ORDER="$ABI_ORDER" \
python3 - <<'PY'
from pathlib import Path
import hashlib
import json
import os
import shutil
import sys
import urllib.request

root_dir = Path(os.environ['ROOT_DIR'])
tag = os.environ['LAMDA_RELEASE_TAG']
release_url = os.environ['LAMDA_RELEASE_URL']
asset_dir = Path(os.environ['ASSET_DIR'])
manifest_path = Path(os.environ['MANIFEST_PATH'])
tmp_dir = Path(os.environ['TMP_DIR'])
abi_order = os.environ['ABI_ORDER'].split()
base_url = f'https://github.com/firerpa/lamda/releases/download/{tag}'
asset_names = {
    'arm64-v8a': 'busybox-arm64-v8a',
    'armeabi-v7a': 'busybox-armeabi-v7a',
    'x86': 'busybox-x86',
    'x86_64': 'busybox-x86_64',
}


def download(url: str, path: Path) -> None:
    print(f'download {url}')
    req = urllib.request.Request(url, headers={'User-Agent': 'Mira toolbox fetcher'})
    with urllib.request.urlopen(req) as resp, path.open('wb') as out:
        shutil.copyfileobj(resp, out)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


tmp_dir.mkdir(parents=True, exist_ok=True)
asset_dir.mkdir(parents=True, exist_ok=True)
abis = []

for abi in abi_order:
    name = asset_names[abi]
    bin_url = f'{base_url}/{name}'
    sum_url = f'{bin_url}.sha256sum'
    tmp_bin = tmp_dir / name
    tmp_sum = tmp_dir / f'{name}.sha256sum'
    download(sum_url, tmp_sum)
    expected = tmp_sum.read_text(encoding='utf-8').strip().split()[0]
    download(bin_url, tmp_bin)
    actual = sha256(tmp_bin)
    if actual.lower() != expected.lower():
        print(f'sha256 mismatch for {abi}: expected {expected}, got {actual}', file=sys.stderr)
        sys.exit(1)

    out_dir = asset_dir / abi
    out_dir.mkdir(parents=True, exist_ok=True)
    out_bin = out_dir / 'busybox'
    shutil.copy2(tmp_bin, out_bin)
    out_bin.chmod(0o644)

    asset_rel = f'toolbox/busybox/{abi}/busybox'
    source_txt = out_dir / 'SOURCE.txt'
    source_txt.write_text(
        f'LAMDA BusyBox {tag}\n'
        f'ABI: {abi}\n'
        'License: GPL-2.0\n'
        f'Release: {release_url}\n'
        f'Upstream asset: {bin_url}\n'
        'Download script: tools/toolbox/download-lamda-busybox.sh\n'
        f'Asset: {asset_rel}\n'
        f'SHA256: {actual}\n',
        encoding='utf-8',
    )

    size = out_bin.stat().st_size
    abis.append({
        'abi': abi,
        'asset': asset_rel,
        'upstreamAsset': bin_url,
        'sha256': actual,
        'sizeBytes': size,
    })
    print(f'verified {abi}: {actual} {size} bytes')

manifest = {
    'schemaVersion': 1,
    'name': 'mira-toolbox',
    'packaging': 'apk-assets',
    'releaseMode': 'per-session-cache',
    'busybox': {
        'version': f'lamda-{tag}',
        'license': 'GPL-2.0',
        'source': release_url,
        'downloadScript': 'tools/toolbox/download-lamda-busybox.sh',
        'runtimeInstallMode': 'all applets from busybox --list',
        'installedAppletsSource': 'runtime busybox --list',
        'abis': abis,
    },
}
manifest_path.parent.mkdir(parents=True, exist_ok=True)
manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
PY
