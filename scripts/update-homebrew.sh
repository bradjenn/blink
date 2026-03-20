#!/bin/bash
set -euo pipefail

APPLY=false
POSITIONAL=()

for arg in "$@"; do
  case $arg in
    --apply) APPLY=true ;;
    *) POSITIONAL+=("$arg") ;;
  esac
done

VERSION="${POSITIONAL[0]:?Usage: update-homebrew.sh [--apply] <version> [dmg-path]}"
DMG="${POSITIONAL[1]:-Blink.dmg}"

if [ ! -f "$DMG" ]; then
  echo "DMG not found: $DMG"
  echo "Downloading from GitHub Releases..."
  curl -L -o "$DMG" "https://github.com/bradjenn/blink/releases/download/v${VERSION}/Blink.dmg"
fi

SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')

CASK_FILE="homebrew-tap/Casks/blink.rb"

if [ "$APPLY" = true ]; then
  if [ ! -f "$CASK_FILE" ]; then
    echo "Error: $CASK_FILE not found. Run from the blink repo root."
    exit 1
  fi
  sed -i '' "s/version \".*\"/version \"$VERSION\"/" "$CASK_FILE"
  sed -i '' "s/sha256 \".*\"/sha256 \"$SHA\"/" "$CASK_FILE"
  echo "Updated $CASK_FILE to v$VERSION (sha256: $SHA)"
else
  echo ""
  echo "Update Casks/blink.rb in homebrew-tap:"
  echo ""
  echo "  version \"$VERSION\""
  echo "  sha256 \"$SHA\""
  echo ""
  echo "Or run with --apply to update automatically:"
  echo "  ./scripts/update-homebrew.sh --apply $VERSION"
fi
