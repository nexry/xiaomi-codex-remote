#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="$ROOT/.build"
SOURCE_ROOT="$WORK_DIR/BlackHole"

OUTPUT="$ROOT/MiCodexRemote2ch.driver"

PRODUCT_NAME="MiCodexRemote2ch"
BUNDLE_ID="com.micodexremote.audio2ch"
DEFINITIONS='$GCC_PREPROCESSOR_DEFINITIONS kDriver_Name=\"MiCodexRemote\" kDevice_Name=\"MiCodexRemote\" kPlugIn_BundleID=\"com.micodexremote.audio2ch\" kNumber_Of_Channels=2'

echo "Cleaning up..."
rm -rf "$WORK_DIR" "$OUTPUT"
mkdir -p "$WORK_DIR"

echo "Cloning BlackHole v0.7.1..."
git clone --depth 1 --branch v0.7.1 https://github.com/ExistentialAudio/BlackHole.git "$SOURCE_ROOT"

echo "Updating COM Plugin UUID to avoid conflicts..."
sed -i '' 's/e395c745-4eea-4d94-bb92-46224221047c/11994d37-7b40-4221-a654-ca2651b400d8/g' "$SOURCE_ROOT/BlackHole/BlackHole.plist"

echo "Building driver using xcodebuild..."
xcodebuild \
  -project "$SOURCE_ROOT/BlackHole.xcodeproj" \
  -target BlackHole \
  -configuration Release \
  -sdk macosx \
  ONLY_ACTIVE_ARCH=NO \
  MACOSX_DEPLOYMENT_TARGET=12.0 \
  CODE_SIGNING_ALLOWED=NO \
  PRODUCT_NAME="$PRODUCT_NAME" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  GCC_PREPROCESSOR_DEFINITIONS="$DEFINITIONS" \
  build

echo "Copying built driver to $OUTPUT..."
cp -R "$SOURCE_ROOT/build/Release/$PRODUCT_NAME.driver" "$OUTPUT"
strip -S "$OUTPUT/Contents/MacOS/$PRODUCT_NAME"

echo "Signing driver (ad-hoc)..."
codesign --force --deep --sign - --timestamp=none "$OUTPUT"

echo "Successfully built $OUTPUT."
echo ""
echo "To install the driver, you can run:"
echo "  sudo bash \"$ROOT/install.sh\""
