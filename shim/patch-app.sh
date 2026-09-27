#!/usr/bin/env bash
# Developer fallback for the GUI's “准备 ChatGPT 兼容副本” action.
# Uses only macOS tools plus Node.js built-ins; the product GUI uses its native
# Swift implementation and does not require Node.js.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${CHATGPT_APP:-/Applications/ChatGPT.app}"
DST="${CHATGPT_SHIM_APP:-$HOME/Applications/ChatGPT-Patched.app}"
FW_REL="Contents/Frameworks/Codex Framework.framework/Codex Framework"

if [ ! -d "$SRC" ]; then
  echo "ChatGPT app not found at $SRC (set CHATGPT_APP to override)." >&2
  exit 1
fi

mkdir -p "$(dirname "$DST")"
SRC_CANON="$(cd "$(dirname "$SRC")" && pwd -P)/$(basename "$SRC")"
DST_CANON="$(cd "$(dirname "$DST")" && pwd -P)/$(basename "$DST")"
if [ "$SRC_CANON" = "$DST_CANON" ] || [ "$DST_CANON" = "/Applications/ChatGPT.app" ]; then
  echo "Refusing to overwrite the official ChatGPT app." >&2
  exit 1
fi
case "$DST_CANON" in
  *.app) ;;
  *) echo "Compatibility target must end in .app: $DST_CANON" >&2; exit 1 ;;
esac

STAGING="$(dirname "$DST_CANON")/.ChatGPT-Patched.$$.app"
BACKUP="$(dirname "$DST_CANON")/.ChatGPT-Patched.backup.$$.app"
INSTALLED=0
cleanup() {
  rm -rf "$STAGING"
  if [ "$INSTALLED" -eq 0 ] && [ -d "$BACKUP" ] && [ ! -e "$DST_CANON" ]; then
    mv "$BACKUP" "$DST_CANON"
  fi
  rm -rf "$BACKUP"
}
trap cleanup EXIT

echo "Copying official ChatGPT to a staging bundle..."
ditto --noextattr --noqtn "$SRC_CANON" "$STAGING"

echo "Enabling Electron NodeOptions fuse..."
node - "$STAGING/$FW_REL" <<'EOF'
const fs = require("node:fs");
const target = process.argv[2];
const sentinel = Buffer.from("dL7pKGdnNz796PbbjQWNKmHXBZaB9tsX");
const data = fs.readFileSync(target);
const offsets = [];
for (let start = 0; ; start += 1) {
  const found = data.indexOf(sentinel, start);
  if (found < 0) break;
  offsets.push(found);
  start = found;
}
if (offsets.length < 1 || offsets.length > 2) throw new Error("Invalid Electron fuse marker count");
for (const offset of offsets) {
  const header = offset + sentinel.length;
  if (data[header] !== 1 || data[header + 1] <= 2) throw new Error("Unsupported Electron fuse wire");
  const state = data[header + 2 + 2];
  if (state !== 48 && state !== 49) throw new Error("NodeOptions fuse cannot be changed");
  data[header + 2 + 2] = 49;
}
fs.writeFileSync(target, data);
EOF

echo "Embedding shim and configuring Dock/Finder launches..."
SHIM_DST="$STAGING/Contents/Resources/XiaomiCodexRemoteShim"
mkdir -p "$SHIM_DST" "$HOME/Library/Logs/Xiaomi Codex Remote"
cp -X "$ROOT/shim/preload.cjs" "$ROOT/shim/patch.cjs" "$SHIM_DST/"
PLIST="$STAGING/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName ChatGPT Shim" "$PLIST" \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string ChatGPT Shim" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :LSEnvironment dict" "$PLIST" 2>/dev/null || true
for key in NODE_OPTIONS CODEX_MICRO_SOCKET CODEX_MICRO_SHIM_LOG; do
  /usr/libexec/PlistBuddy -c "Delete :LSEnvironment:$key" "$PLIST" 2>/dev/null || true
done
/usr/libexec/PlistBuddy -c "Add :LSEnvironment:NODE_OPTIONS string --require \"$DST_CANON/Contents/Resources/XiaomiCodexRemoteShim/preload.cjs\"" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :LSEnvironment:CODEX_MICRO_SOCKET string /tmp/xiaomi-codex-remote-$(id -u).sock" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :LSEnvironment:CODEX_MICRO_SHIM_LOG string $HOME/Library/Logs/Xiaomi Codex Remote/shim.log" "$PLIST"

echo "Signing and verifying compatibility copy..."
# OpenAI's application-group, push, and keychain entitlements require its team
# signature. Keeping them on an ad-hoc copy makes AMFI reject the process.
codesign --force --deep --sign - --timestamp=none "$STAGING"
codesign --verify --deep --strict "$STAGING"

if [ -e "$DST_CANON" ]; then mv "$DST_CANON" "$BACKUP"; fi
mv "$STAGING" "$DST_CANON"
INSTALLED=1
rm -rf "$BACKUP"

echo "ChatGPT Shim is ready at: $DST_CANON"
echo "Open it once, then drag ChatGPT Shim from Finder to the Dock if desired."
