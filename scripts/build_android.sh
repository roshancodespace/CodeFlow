#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

VERSION=$(cat "$ROOT_DIR/VERSION" 2>/dev/null || echo "1.0.0")

echo "============================================================"
echo " Building CodeFlow Android Release APK (v$VERSION)"
echo "============================================================"

cd "$ROOT_DIR/codeflow_app"

# Check flutter binary
FLUTTER_BIN="flutter"
if ! command -v flutter &> /dev/null; then
    if [ -x "/home/roshan/fvm/versions/3.41.9/bin/flutter" ]; then
        FLUTTER_BIN="/home/roshan/fvm/versions/3.41.9/bin/flutter"
    fi
fi

echo "Using Flutter: $($FLUTTER_BIN --version | head -n 1)"

$FLUTTER_BIN pub get
$FLUTTER_BIN build apk --release

RELEASE_DIR="$ROOT_DIR/release"
mkdir -p "$RELEASE_DIR"

OUTPUT_APK="$ROOT_DIR/codeflow_app/build/app/outputs/flutter-apk/app-release.apk"
TARGET_APK="$RELEASE_DIR/CodeFlow-Android-v$VERSION.apk"

if [ -f "$OUTPUT_APK" ]; then
    cp "$OUTPUT_APK" "$TARGET_APK"
    echo ""
    echo "[SUCCESS] Release APK built and copied to: $TARGET_APK"
else
    echo "[WARNING] Expected output APK not found at $OUTPUT_APK"
fi
