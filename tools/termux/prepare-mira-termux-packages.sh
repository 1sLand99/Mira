#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_DIR="$ROOT_DIR/third_party/termux-packages"
OUT_DIR="${1:-$ROOT_DIR/.mira/forks/termux-packages-mira}"
MIRA_PACKAGE="${MIRA_PACKAGE:-com.vwww.mira}"

if [[ ! -d "$SRC_DIR/scripts" ]]; then
  echo "缺少 termux-packages submodule: $SRC_DIR" >&2
  exit 1
fi

rm -rf "$OUT_DIR"
mkdir -p "$(dirname "$OUT_DIR")"
rsync -a --delete \
  --exclude '.git' \
  --exclude 'output' \
  --exclude 'debs' \
  --exclude 'bootstrap-*.zip' \
  "$SRC_DIR/" "$OUT_DIR/"

python3 - "$OUT_DIR/scripts/properties.sh" "$MIRA_PACKAGE" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
package = sys.argv[2]
text = path.read_text()
text = text.replace('TERMUX_APP__PACKAGE_NAME="com.termux"', f'TERMUX_APP__PACKAGE_NAME="{package}"')
path.write_text(text)
PY

cat > "$OUT_DIR/MIRA-BUILD.md" <<EOF
# Mira termux-packages fork workspace

Package name: $MIRA_PACKAGE
Prefix: /data/data/$MIRA_PACKAGE/files/usr

Build all bootstrap architectures with Docker:

\`\`\`bash
cd "$OUT_DIR"
./scripts/run-docker.sh ./scripts/build-bootstraps.sh -f &> build-mira-bootstrap.log
\`\`\`

Expected outputs:

\`\`\`text
$OUT_DIR/bootstrap-aarch64.zip
$OUT_DIR/bootstrap-arm.zip
$OUT_DIR/bootstrap-i686.zip
$OUT_DIR/bootstrap-x86_64.zip
\`\`\`

For a one-device aarch64 smoke build:

\`\`\`bash
./scripts/run-docker.sh ./scripts/build-bootstraps.sh --architectures aarch64 -f &> build-mira-bootstrap-aarch64.log
\`\`\`

Do not use official com.termux bootstrap zip for Mira.
EOF

echo "已准备 Mira termux-packages fork 工作区: $OUT_DIR"
echo "包名: $MIRA_PACKAGE"
echo "下一步: cd '$OUT_DIR' && ./scripts/run-docker.sh ./scripts/build-bootstraps.sh -f"
