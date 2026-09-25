#!/usr/bin/env bash
# Build the native virtual-HID helper. Requires the Xcode command line tools.
set -euo pipefail
cd "$(dirname "$0")"

OUT="CodexMicroVirtualHID"

echo "Compiling ${OUT}…"
swiftc -O \
  -import-objc-header IOHIDUserDeviceShim.h \
  -framework IOKit \
  -framework CoreFoundation \
  -framework Foundation \
  main.swift \
  -o "${OUT}"

echo "Built ./${OUT}"
echo
echo "Run it (root is usually required for IOHIDUserDevice):"
echo "  sudo ./${OUT} \"\${TMPDIR}codex-micro-vhid.sock\""
echo
echo "If it exits with an entitlement error, see the README section"
echo "\"macOS virtual-HID caveats\" for the code-signing walkthrough."
