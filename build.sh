#!/bin/bash
# Build TerminalPad.app from Swift sources without Xcode (CommandLineTools only).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/TerminalPad.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"

echo "==> Cleaning previous build"
rm -rf "$APP"
mkdir -p "$MACOS" "$RES"

# Minimum macOS: 14.0 (Sonoma) — covers every shipping Apple Silicon Mac, and Intel too.
# macOS-26-only APIs (Liquid Glass) are runtime-gated with `if #available(macOS 26, *)`,
# so the app falls back to a clean dark panel on older systems.
DEPLOY_TARGET="14.0"

compile_slice() {
    local arch="$1" out="$2"
    swiftc \
        -O \
        -parse-as-library \
        -target "${arch}-apple-macos${DEPLOY_TARGET}" \
        -framework SwiftUI \
        -framework AppKit \
        -framework Carbon \
        -o "$out" \
        "$ROOT"/Sources/*.swift
}

echo "==> Compiling Swift sources (universal: arm64 + x86_64, min macOS ${DEPLOY_TARGET})"
TMP="$(mktemp -d)"
compile_slice arm64 "$TMP/TerminalPad-arm64"
if compile_slice x86_64 "$TMP/TerminalPad-x86_64" 2>/dev/null; then
    lipo -create "$TMP/TerminalPad-arm64" "$TMP/TerminalPad-x86_64" -output "$MACOS/TerminalPad"
    echo "    universal binary: $(lipo -archs "$MACOS/TerminalPad")"
else
    # x86_64 SDK slice unavailable — ship Apple Silicon only.
    cp "$TMP/TerminalPad-arm64" "$MACOS/TerminalPad"
    echo "    arm64-only (x86_64 slice unavailable)"
fi
rm -rf "$TMP"

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
