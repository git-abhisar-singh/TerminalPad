#!/usr/bin/env bash
# TerminalPad installer — builds from source and installs to /Applications.
# Usage:  ./install.sh
set -euo pipefail

cd "$(dirname "$0")"

echo "==> Building TerminalPad…"
./build.sh

DEST="/Applications/TerminalPad.app"
echo "==> Installing to $DEST"
rm -rf "$DEST"
cp -R TerminalPad.app "$DEST"

# Locally built bundle, so it's already trusted — clear any quarantine just in case.
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "==> Done. Launch with:  open \"$DEST\""
echo "    (First agent launch: macOS will ask to control Terminal — click Allow.)"
