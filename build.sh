#!/bin/bash
# Build AgentPad.app from Swift sources without Xcode (CommandLineTools only).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/AgentPad.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"

echo "==> Cleaning previous build"
rm -rf "$APP"
mkdir -p "$MACOS" "$RES"

echo "==> Compiling Swift sources"
swiftc \
    -O \
    -parse-as-library \
    -framework SwiftUI \
    -framework AppKit \
    -o "$MACOS/AgentPad" \
    "$ROOT"/Sources/*.swift

echo "==> Installing Info.plist"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

echo "==> Bundling resources"
if [ -d "$ROOT/Resources/logos" ]; then
    mkdir -p "$RES/logos"
    cp "$ROOT/Resources/logos/"*.png "$RES/logos/" 2>/dev/null || true
    echo "    $(ls "$RES/logos" | wc -l | tr -d ' ') logos"
fi
cp "$ROOT/Resources/"*.png "$RES/" 2>/dev/null || true

# Optional custom icon: if AppIcon.icns exists, bundle it.
if [ -f "$ROOT/AppIcon.icns" ]; then
    cp "$ROOT/AppIcon.icns" "$RES/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || true
fi

echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "    (codesign skipped)"

echo "==> Done: $APP"
