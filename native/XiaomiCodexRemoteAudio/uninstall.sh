#!/usr/bin/env bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root (e.g. using sudo)"
  exit 1
fi

DEST_DIR="/Library/Audio/Plug-Ins/HAL/MiCodexRemote2ch.driver"

if [ ! -d "$DEST_DIR" ]; then
  echo "Driver not found at $DEST_DIR. It may have already been uninstalled."
  exit 0
fi

echo "Removing driver from $DEST_DIR..."
rm -rf "$DEST_DIR"

echo "Restarting CoreAudio (coreaudiod) to unload the driver..."
if pgrep -qx coreaudiod; then
  killall coreaudiod
  echo "CoreAudio restarted."
else
  echo "CoreAudio was not running."
fi

echo "Uninstallation complete!"
