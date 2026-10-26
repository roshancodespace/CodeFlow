#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Starting full build for CodeFlow Companion and Mobile..."
"$SCRIPT_DIR/build_companion.sh"
"$SCRIPT_DIR/build_android.sh"

echo ""
echo "============================================================"
echo " All builds completed! Check the 'release/' folder."
echo "============================================================"
