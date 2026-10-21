#!/bin/bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
KEY="$(printf %s "$ROOT" | shasum -a 256 | cut -c 1-12)"
SOURCE="$HOME/Library/Caches/Ribbon/package-$KEY/Ribbon.app"
DESTINATION="$HOME/Applications/Ribbon.app"
codesign --verify --deep --strict "$SOURCE"
if [ -e "$DESTINATION" ]; then
  IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$DESTINATION/Contents/Info.plist")"
  if [ "$IDENTIFIER" != "dev.ribbon.app" ]; then
    printf 'A different app already exists at %s; refusing to replace it.\n' "$DESTINATION" >&2
    exit 1
  fi
  if pgrep -f "$DESTINATION/Contents/MacOS/Ribbon" > /dev/null; then
    printf 'Quit the existing Ribbon build before replacing it.\n' >&2
    exit 1
  fi
fi
mkdir -p "$HOME/Applications"
ditto "$SOURCE" "$DESTINATION"
codesign --verify --deep --strict "$DESTINATION"
printf 'Installed: %s\n' "$DESTINATION"
