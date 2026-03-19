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

# Stage app + Applications symlink in a temp folder
STAGING=$(mktemp -d)
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
  -volname "Blink" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$DMG" \
  -quiet

rm -rf "$STAGING"

echo "==> Done: $DMG ($(du -h "$DMG" | cut -f1))"
