#!/bin/bash
set -euo pipefail

VERSION="${1:?Usage: update-homebrew.sh <version>}"
DMG="${2:-Blink.dmg}"

if [ ! -f "$DMG" ]; then
  echo "DMG not found: $DMG"
  echo "Downloading from GitHub Releases..."
  curl -L -o "$DMG" "https://github.com/bradjenn/blink/releases/download/v${VERSION}/Blink.dmg"
fi

SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')

echo ""
echo "Update Casks/blink.rb in homebrew-tap:"
echo ""
echo "  version \"$VERSION\""
echo "  sha256 \"$SHA\""
echo ""
echo "  url \"https://github.com/bradjenn/blink/releases/download/v#{version}/Blink.dmg\""
