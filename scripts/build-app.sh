#!/bin/bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
export CARGO_TARGET_DIR="$ROOT/build/cargo"
PROFILE=release
ENGINE_DIRECTORY=release
SUFFIX=
if [ "$#" -gt 0 ]; then
  if [ "$#" != 1 ] || [ "$1" != --debug-engine ]; then
    printf 'Usage: build-app.sh [--debug-engine]\n' >&2
    exit 2
  fi
  PROFILE=dev
  ENGINE_DIRECTORY=debug
  SUFFIX=-debug
  export CARGO_TARGET_DIR="$ROOT/vendor/paneru/target"
fi
cargo +1.95.0 build --manifest-path "$ROOT/vendor/paneru/Cargo.toml" --locked --no-default-features --profile "$PROFILE"
"$ROOT/scripts/swift.sh" build -c release
SWIFT_BIN="$("$ROOT/scripts/swift.sh" build -c release --show-bin-path)"
KEY="$(printf %s "$ROOT" | shasum -a 256 | cut -c 1-12)"
STAGING="$HOME/Library/Caches/Ribbon/package-$KEY$SUFFIX"
mkdir -p "$STAGING"
python3 "$ROOT/scripts/collect-notices.py"
python3 "$ROOT/scripts/package-app.py" "$ROOT" "$SWIFT_BIN" "$STAGING" "$CARGO_TARGET_DIR/$ENGINE_DIRECTORY/paneru"
swift "$ROOT/scripts/make-icon.swift" "$STAGING/AppIcon.iconset"
APP="$STAGING/Ribbon.app"
iconutil -c icns "$STAGING/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier dev.ribbon.fixture "$APP/Contents/Resources/Ribbon Demo.app"
codesign --force --sign - --identifier dev.ribbon.sentinel "$APP/Contents/Resources/Ribbon Sentinel.app"
codesign --force --sign - --identifier dev.ribbon.app "$APP/Contents/MacOS/ribbon-engine"
codesign --force --sign - --identifier dev.ribbon.app "$APP"
codesign --verify --deep --strict "$APP"
ARCHIVE="$ROOT/build/Ribbon-beta$SUFFIX.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
# Documents/iCloud rewrites bundle metadata after signing. Keep the physical
# signed app in Caches, and deliver an immutable ZIP in the workspace.
python3 -c 'import json,sys; from pathlib import Path; Path(sys.argv[2]).write_text(json.dumps({"app":sys.argv[1],"archive":sys.argv[3]},indent=2))' "$APP" "$ROOT/build/artifacts$SUFFIX.json" "$ARCHIVE"
printf 'Built and verified: %s\nArchive: %s\n' "$APP" "$ARCHIVE"
