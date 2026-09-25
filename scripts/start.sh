#!/usr/bin/env bash
# Convenience launcher: build the native helper if needed, start it (as root,
# since IOHIDUserDevice usually requires it), then run the Node bridge.
#
#   ./scripts/start.sh [--input keyboard]
#
# Ctrl-C stops both.
set -euo pipefail
cd "$(dirname "$0")/.."

SOCK="${TMPDIR:-/tmp/}codex-micro-vhid.sock"
HELPER="native/CodexMicroVirtualHID/CodexMicroVirtualHID"

if [ ! -x "$HELPER" ]; then
  echo "Building native helper…"
  bash native/CodexMicroVirtualHID/build.sh
fi

echo "Starting virtual-HID helper (sudo)…"
sudo "$HELPER" "$SOCK" &
HELPER_PID=$!
trap 'sudo kill $HELPER_PID 2>/dev/null || true' EXIT

# Give the helper a moment to create the device and bind the socket.
sleep 1

echo "Starting bridge…"
node bin/codex-micro-emulator.js --mode helper --socket "$SOCK" "$@"
