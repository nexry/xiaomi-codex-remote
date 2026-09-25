#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Building Xiaomi Codex Remote GUI in release mode..."
swift build -c release

BIN_PATH="$SCRIPT_DIR/.build/release/XiaomiCodexRemote"
echo "Build succeeded: $BIN_PATH"
