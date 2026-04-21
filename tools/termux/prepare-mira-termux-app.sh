#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_DIR="$ROOT_DIR/third_party/termux-app"
OUT_DIR="${1:-$ROOT_DIR/.mira/forks/termux-app-mira}"
MIRA_PACKAGE="${MIRA_PACKAGE:-com.vwww.mira}"
MIRA_APP_NAME="${MIRA_APP_NAME:-Mira}"
MIRA_API_APP_NAME="${MIRA_API_APP_NAME:-Mira:API}"
MIRA_BOOT_APP_NAME="${MIRA_BOOT_APP_NAME:-Mira:Boot}"
MIRA_FLOAT_APP_NAME="${MIRA_FLOAT_APP_NAME:-Mira:Float}"
MIRA_STYLING_APP_NAME="${MIRA_STYLING_APP_NAME:-Mira:Styling}"
MIRA_TASKER_APP_NAME="${MIRA_TASKER_APP_NAME:-Mira:Tasker}"
MIRA_WIDGET_APP_NAME="${MIRA_WIDGET_APP_NAME:-Mira:Widget}"

if [[ ! -d "$SRC_DIR/app" ]]; then
  echo "缺少 termux-app submodule: $SRC_DIR" >&2
  exit 1
fi

rm -rf "$OUT_DIR"
mkdir -p "$(dirname "$OUT_DIR")"
rsync -a --delete \
  --exclude '.git' \
  --exclude '.gradle' \
  --exclude 'build' \
  --exclude '*/build' \
  --exclude 'app/src/main/cpp/bootstrap-*.zip' \
  "$SRC_DIR/" "$OUT_DIR/"

python3 - "$OUT_DIR" "$MIRA_PACKAGE" "$MIRA_APP_NAME" "$MIRA_API_APP_NAME" "$MIRA_BOOT_APP_NAME" "$MIRA_FLOAT_APP_NAME" "$MIRA_STYLING_APP_NAME" "$MIRA_TASKER_APP_NAME" "$MIRA_WIDGET_APP_NAME" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
package = sys.argv[2]
app_name = sys.argv[3]
api_app_name = sys.argv[4]
boot_app_name = sys.argv[5]
float_app_name = sys.argv[6]
styling_app_name = sys.argv[7]
tasker_app_name = sys.argv[8]
widget_app_name = sys.argv[9]

replacements = {
    'manifestPlaceholders.TERMUX_PACKAGE_NAME = "com.termux"': f'manifestPlaceholders.TERMUX_PACKAGE_NAME = "{package}"',
    'manifestPlaceholders.TERMUX_APP_NAME = "Termux"': f'manifestPlaceholders.TERMUX_APP_NAME = "{app_name}"',
    'manifestPlaceholders.TERMUX_API_APP_NAME = "Termux:API"': f'manifestPlaceholders.TERMUX_API_APP_NAME = "{api_app_name}"',
    'manifestPlaceholders.TERMUX_BOOT_APP_NAME = "Termux:Boot"': f'manifestPlaceholders.TERMUX_BOOT_APP_NAME = "{boot_app_name}"',
    'manifestPlaceholders.TERMUX_FLOAT_APP_NAME = "Termux:Float"': f'manifestPlaceholders.TERMUX_FLOAT_APP_NAME = "{float_app_name}"',
    'manifestPlaceholders.TERMUX_STYLING_APP_NAME = "Termux:Styling"': f'manifestPlaceholders.TERMUX_STYLING_APP_NAME = "{styling_app_name}"',
    'manifestPlaceholders.TERMUX_TASKER_APP_NAME = "Termux:Tasker"': f'manifestPlaceholders.TERMUX_TASKER_APP_NAME = "{tasker_app_name}"',
    'manifestPlaceholders.TERMUX_WIDGET_APP_NAME = "Termux:Widget"': f'manifestPlaceholders.TERMUX_WIDGET_APP_NAME = "{widget_app_name}"',
    'public static final String TERMUX_PACKAGE_NAME = "com.termux";': f'public static final String TERMUX_PACKAGE_NAME = "{package}";',
    'public static final String TERMUX_APP_NAME = "Termux";': f'public static final String TERMUX_APP_NAME = "{app_name}";',
    'public static final String TERMUX_API_APP_NAME = "Termux:API";': f'public static final String TERMUX_API_APP_NAME = "{api_app_name}";',
    'public static final String TERMUX_BOOT_APP_NAME = "Termux:Boot";': f'public static final String TERMUX_BOOT_APP_NAME = "{boot_app_name}";',
    'public static final String TERMUX_FLOAT_APP_NAME = "Termux:Float";': f'public static final String TERMUX_FLOAT_APP_NAME = "{float_app_name}";',
    'public static final String TERMUX_STYLING_APP_NAME = "Termux:Styling";': f'public static final String TERMUX_STYLING_APP_NAME = "{styling_app_name}";',
    'public static final String TERMUX_TASKER_APP_NAME = "Termux:Tasker";': f'public static final String TERMUX_TASKER_APP_NAME = "{tasker_app_name}";',
    'public static final String TERMUX_WIDGET_APP_NAME = "Termux:Widget";': f'public static final String TERMUX_WIDGET_APP_NAME = "{widget_app_name}";',
    'public static final String BUILD_CONFIG_CLASS_NAME = TERMUX_PACKAGE_NAME + ".BuildConfig";': 'public static final String BUILD_CONFIG_CLASS_NAME = "com.termux.BuildConfig";',
    'public static final String FILE_SHARE_RECEIVER_ACTIVITY_CLASS_NAME = TERMUX_PACKAGE_NAME + ".app.api.file.FileShareReceiverActivity";': 'public static final String FILE_SHARE_RECEIVER_ACTIVITY_CLASS_NAME = "com.termux.app.api.file.FileShareReceiverActivity";',
    'public static final String FILE_VIEW_RECEIVER_ACTIVITY_CLASS_NAME = TERMUX_PACKAGE_NAME + ".app.api.file.FileViewReceiverActivity";': 'public static final String FILE_VIEW_RECEIVER_ACTIVITY_CLASS_NAME = "com.termux.app.api.file.FileViewReceiverActivity";',
    'public static final String TERMUX_ACTIVITY_NAME = TERMUX_PACKAGE_NAME + ".app.TermuxActivity";': 'public static final String TERMUX_ACTIVITY_NAME = "com.termux.app.TermuxActivity";',
    'public static final String TERMUX_SETTINGS_ACTIVITY_NAME = TERMUX_PACKAGE_NAME + ".app.activities.SettingsActivity";': 'public static final String TERMUX_SETTINGS_ACTIVITY_NAME = "com.termux.app.activities.SettingsActivity";',
    'public static final String TERMUX_SERVICE_NAME = TERMUX_PACKAGE_NAME + ".app.TermuxService";': 'public static final String TERMUX_SERVICE_NAME = "com.termux.app.TermuxService";',
    'public static final String RUN_COMMAND_SERVICE_NAME = TERMUX_PACKAGE_NAME + ".app.RunCommandService";': 'public static final String RUN_COMMAND_SERVICE_NAME = "com.termux.app.RunCommandService";',
    '<!ENTITY TERMUX_PACKAGE_NAME "com.termux">': f'<!ENTITY TERMUX_PACKAGE_NAME "{package}">',
    '<!ENTITY TERMUX_APP_NAME "Termux">': f'<!ENTITY TERMUX_APP_NAME "{app_name}">',
    '<!ENTITY TERMUX_API_APP_NAME "Termux:API">': f'<!ENTITY TERMUX_API_APP_NAME "{api_app_name}">',
    '<!ENTITY TERMUX_BOOT_APP_NAME "Termux:Boot">': f'<!ENTITY TERMUX_BOOT_APP_NAME "{boot_app_name}">',
    '<!ENTITY TERMUX_FLOAT_APP_NAME "Termux:Float">': f'<!ENTITY TERMUX_FLOAT_APP_NAME "{float_app_name}">',
    '<!ENTITY TERMUX_STYLING_APP_NAME "Termux:Styling">': f'<!ENTITY TERMUX_STYLING_APP_NAME "{styling_app_name}">',
    '<!ENTITY TERMUX_TASKER_APP_NAME "Termux:Tasker">': f'<!ENTITY TERMUX_TASKER_APP_NAME "{tasker_app_name}">',
    '<!ENTITY TERMUX_WIDGET_APP_NAME "Termux:Widget">': f'<!ENTITY TERMUX_WIDGET_APP_NAME "{widget_app_name}">',
    '<!ENTITY TERMUX_PREFIX_DIR_PATH "/data/data/com.termux/files/usr">': f'<!ENTITY TERMUX_PREFIX_DIR_PATH "/data/data/{package}/files/usr">',
    'android:targetPackage="com.termux"': f'android:targetPackage="{package}"',
    'android:name="com.termux.app.failsafe_session"': f'android:name="{package}.app.failsafe_session"',
}

for rel in [
    'app/build.gradle',
    'termux-shared/src/main/java/com/termux/shared/termux/TermuxConstants.java',
    'app/src/main/res/values/strings.xml',
    'termux-shared/src/main/res/values/strings.xml',
    'app/src/main/res/xml/shortcuts.xml',
]:
    path = root / rel
    text = path.read_text()
    for old, new in replacements.items():
        text = text.replace(old, new)
    if rel == 'app/build.gradle' and 'applicationId "' not in text:
        text = text.replace('versionName "0.118.0"', f'versionName "0.118.0"\n        applicationId "{package}"')
    if rel == 'app/build.gradle':
        old = '    def file = new File(projectDir, localUrl)\n    if (file.exists()) {'
        new = (
            '    def file = new File(projectDir, localUrl)\n'
            '    def miraUseLocalBootstraps = System.getenv("MIRA_USE_LOCAL_BOOTSTRAPS") == "1"\n'
            '    if (miraUseLocalBootstraps && !file.exists()) {\n'
            '        throw new GradleException("Missing local Mira bootstrap: " + localUrl)\n'
            '    }\n'
            '    if (file.exists()) {'
        )
        text = text.replace(old, new)
        old = '    if (file.exists()) {\n        def buffer = new byte[8192]'
        new = (
            '    if (file.exists()) {\n'
            '        if (miraUseLocalBootstraps) {\n'
            '            logger.quiet("Using local Mira bootstrap: " + localUrl)\n'
            '            return\n'
            '        }\n'
            '        def buffer = new byte[8192]'
        )
        text = text.replace(old, new)
    path.write_text(text)

checks = {
    'app/build.gradle': [
        f'applicationId "{package}"',
        f'manifestPlaceholders.TERMUX_PACKAGE_NAME = "{package}"',
        'Missing local Mira bootstrap',
        'miraUseLocalBootstraps',
    ],
    'termux-shared/src/main/java/com/termux/shared/termux/TermuxConstants.java': [
        f'public static final String TERMUX_PACKAGE_NAME = "{package}";',
        f'public static final String TERMUX_APP_NAME = "{app_name}";',
        'public static final String TERMUX_ACTIVITY_NAME = "com.termux.app.TermuxActivity";',
        'public static final String TERMUX_SERVICE_NAME = "com.termux.app.TermuxService";',
    ],
    'termux-shared/src/main/res/values/strings.xml': [
        f'<!ENTITY TERMUX_PACKAGE_NAME "{package}">',
        f'<!ENTITY TERMUX_PREFIX_DIR_PATH "/data/data/{package}/files/usr">',
    ],
    'app/src/main/res/xml/shortcuts.xml': [
        f'android:targetPackage="{package}"',
        f'android:name="{package}.app.failsafe_session"',
        'android:targetClass="com.termux.app.TermuxActivity"',
    ],
}
missing = []
for rel, needles in checks.items():
    text = (root / rel).read_text()
    for needle in needles:
        if needle not in text:
            missing.append(f'{rel}: {needle}')
if missing:
    raise SystemExit('Mira fork patch validation failed:\\n' + '\\n'.join(missing))
PY

cat > "$OUT_DIR/MIRA-FORK.md" <<EOF
# Mira termux-app fork workspace

Package name: $MIRA_PACKAGE
App name: $MIRA_APP_NAME
Java source package: com.termux

Before building the APK, copy matching Mira bootstrap zips into:

\`\`\`text
app/src/main/cpp/bootstrap-aarch64.zip
app/src/main/cpp/bootstrap-arm.zip
app/src/main/cpp/bootstrap-i686.zip
app/src/main/cpp/bootstrap-x86_64.zip
\`\`\`

Then build:

\`\`\`bash
cd "$OUT_DIR"
MIRA_USE_LOCAL_BOOTSTRAPS=1 ./gradlew :app:assembleDebug
\`\`\`

This generated fork keeps the original Java source package \`com.termux\` and changes the Android
\`applicationId\` to \`$MIRA_PACKAGE\`. Do not rename Java packages for the first fork pass.

This workspace is generated. Do not edit it as source of truth.
EOF

echo "已准备 Mira termux-app fork 工作区: $OUT_DIR"
echo "包名: $MIRA_PACKAGE"
echo "注意: 必须配套使用按 $MIRA_PACKAGE 重编的 bootstrap zip"
