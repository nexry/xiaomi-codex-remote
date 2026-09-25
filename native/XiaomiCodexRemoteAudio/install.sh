#!/usr/bin/env bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root (e.g. using sudo)"
  exit 1
fi

ROOT="$(cd "$(dirname "$0")" && pwd)"
DRIVER_DIR="$ROOT/MiCodexRemote2ch.driver"
DEST_DIR="/Library/Audio/Plug-Ins/HAL/MiCodexRemote2ch.driver"

if [ ! -d "$DRIVER_DIR" ]; then
  echo "Driver not found. Please run build.sh first."
  exit 1
fi

echo "Copying driver to $DEST_DIR..."
rm -rf "$DEST_DIR"
cp -R "$DRIVER_DIR" "$DEST_DIR"

echo "Setting permissions..."
chown -R root:wheel "$DEST_DIR"
find "$DEST_DIR" -type d -exec chmod 755 {} \;
find "$DEST_DIR" -type f -exec chmod 644 {} \;
chmod 755 "$DEST_DIR/Contents/MacOS/MiCodexRemote2ch"

echo "Verifying signature..."
codesign --verify --deep --strict "$DEST_DIR"

echo "Restarting CoreAudio (coreaudiod) to load the new driver..."
if pgrep -qx coreaudiod; then
  killall coreaudiod
  echo "CoreAudio restarted."
else
  echo "CoreAudio was not running."
fi

echo "Installation complete! The virtual sound card should now be available."
