#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT/build/DerivedData-arm64"
APP="$DERIVED/Build/Products/Release/Blink.app"
DMG="$ROOT/Blink.dmg"

echo "==> Clean Release build..."
xcodebuild clean build \
  -scheme Blink \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  -arch arm64 \
  ONLY_ACTIVE_ARCH=NO \
  -quiet

echo "==> Build succeeded: $(stat -f '%Sm' "$APP/Contents/MacOS/Blink")"

echo "==> Creating DMG..."
rm -f "$DMG"
hdiutil create \
  -volname "Blink" \
  -srcfolder "$APP" \
  -ov -format UDZO \
  "$DMG" \
  -quiet

echo "==> Done: $DMG ($(du -h "$DMG" | cut -f1))"
