#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "============================================================"
echo " Building CodeFlow Companion Standalone Binary"
echo "============================================================"

cd "$ROOT_DIR/companion"

# Use python virtualenv if exists, otherwise python3
PYTHON_BIN="python3"
if [ -d "$ROOT_DIR/companion_venv" ]; then
    PYTHON_BIN="$ROOT_DIR/companion_venv/bin/python"
fi

$PYTHON_BIN build_executable.py

# Copy to root release directory
mkdir -p "$ROOT_DIR/release"
cp -r "$ROOT_DIR/companion/release/"* "$ROOT_DIR/release/" 2>/dev/null || true

echo ""
echo "[SUCCESS] Companion build artifacts copied to $ROOT_DIR/release/"
