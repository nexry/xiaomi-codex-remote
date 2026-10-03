#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$SCRIPT_DIR/Xiaomi Codex Remote.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_SOURCE="$SCRIPT_DIR/../../assets/Xiao Codex Remote.icon"
ICON_NAME="Xiao Codex Remote"
REMOTE_IMAGE_SOURCE="$SCRIPT_DIR/Resources/XiaomiRemote.png"

echo "Building release binary..."
cd "$SCRIPT_DIR"
APP_VERSION="$(sed -n 's/.*"version": "\([^"]*\)".*/\1/p' "$SCRIPT_DIR/../../package.json" | head -n 1)"
if [ -z "$APP_VERSION" ]; then
  echo "Error: package.json does not specify an app version." >&2
  exit 1
fi
BUILD_ARGS=(-c release --disable-keychain)
if [ "${RELEASE_UNIVERSAL:-0}" = "1" ]; then
  BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi
swift build "${BUILD_ARGS[@]}"
BINARY_PATH="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)/XiaomiCodexRemote"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BINARY_PATH" "$MACOS_DIR/Xiaomi Codex Remote"
mkdir -p "$RESOURCES_DIR/shim"
cp "$SCRIPT_DIR/../../shim/preload.cjs" "$RESOURCES_DIR/shim/preload.cjs"
cp "$SCRIPT_DIR/../../shim/patch.cjs" "$RESOURCES_DIR/shim/patch.cjs"
if [ ! -f "$REMOTE_IMAGE_SOURCE" ]; then
  echo "Error: Xiaomi remote image not found: $REMOTE_IMAGE_SOURCE" >&2
  exit 1
fi
cp "$REMOTE_IMAGE_SOURCE" "$RESOURCES_DIR/XiaomiRemote.png"
# Desktop screenshots carry Finder metadata/resource-fork xattrs that make
# codesign reject the otherwise valid app bundle. Clear only the bundled copy.
xattr -c "$RESOURCES_DIR/XiaomiRemote.png"
cp "$SCRIPT_DIR/Resources/CodexMicro.png" "$RESOURCES_DIR/CodexMicro.png"
xattr -c "$RESOURCES_DIR/CodexMicro.png"

# Bundle the virtual audio driver if it has been built
DRIVER_SRC="$SCRIPT_DIR/../XiaomiCodexRemoteAudio/MiCodexRemote2ch.driver"
if [ -d "$DRIVER_SRC" ]; then
  echo "Bundling MiCodexRemote2ch.driver into Resources..."
  rm -rf "$RESOURCES_DIR/MiCodexRemote2ch.driver"
  cp -R "$DRIVER_SRC" "$RESOURCES_DIR/MiCodexRemote2ch.driver"
else
  echo "Warning: MiCodexRemote2ch.driver not found. Run 'npm run build:audio' first to bundle the driver."
fi

echo "Compiling Icon Composer app icon..."
if [ ! -d "$ICON_SOURCE" ]; then
  echo "Error: Icon Composer source not found: $ICON_SOURCE" >&2
  exit 1
fi
if ! ACTOOL_PATH="$(xcrun --find actool 2>/dev/null)"; then
  echo "Error: Xcode actool is required to compile $ICON_SOURCE." >&2
  exit 1
fi

ICON_BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/xiaomi-codex-remote-icon.XXXXXX")"
trap 'rm -rf "$ICON_BUILD_DIR"' EXIT

"$ACTOOL_PATH" "$ICON_SOURCE" \
  --compile "$ICON_BUILD_DIR" \
  --output-format human-readable-text \
  --notices \
  --warnings \
  --output-partial-info-plist "$ICON_BUILD_DIR/icon-info.plist" \
  --app-icon "$ICON_NAME" \
  --include-all-app-icons \
  --compress-pngs \
  --enable-on-demand-resources NO \
  --development-region en \
  --target-device mac \
  --minimum-deployment-target 14.0 \
  --platform macosx

if [ ! -f "$ICON_BUILD_DIR/Assets.car" ] || [ ! -f "$ICON_BUILD_DIR/$ICON_NAME.icns" ]; then
  echo "Error: actool did not produce the expected app icon resources." >&2
  exit 1
fi

rm -f "$RESOURCES_DIR/AppIcon.icns" "$RESOURCES_DIR/$ICON_NAME.icns" "$RESOURCES_DIR/Assets.car"
cp "$ICON_BUILD_DIR/Assets.car" "$RESOURCES_DIR/Assets.car"
cp "$ICON_BUILD_DIR/$ICON_NAME.icns" "$RESOURCES_DIR/$ICON_NAME.icns"

cat << 'EOF' > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>app.aircodex.remote</string>
    <key>CFBundleName</key>
    <string>Xiaomi Codex Remote</string>
    <key>CFBundleExecutable</key>
    <string>Xiaomi Codex Remote</string>
    <key>CFBundleIconFile</key>
    <string>Xiao Codex Remote</string>
    <key>CFBundleIconName</key>
    <string>Xiao Codex Remote</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Xiaomi Codex Remote 需要蓝牙连接小米语音遥控器以接收按键与语音。</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Xiaomi Codex Remote 需要访问音频系统以将遥控器音频路由到虚拟麦克风。</string>
</dict>
</plist>
EOF

/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $APP_VERSION" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $APP_VERSION" "$CONTENTS_DIR/Info.plist"

echo "Signing app bundle (ad-hoc)..."
codesign --force --sign - --timestamp=none "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

# The bundle is updated in place, so refresh its directory timestamp to make
# Finder and Launch Services invalidate any icon cached from an older build.
touch "$APP_DIR"

echo "Xiaomi Codex Remote.app successfully generated at: $APP_DIR"
