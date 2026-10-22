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
# Certificate-backed requirements survive rebuilds; ad-hoc requirements pin a
# code hash, so a checked privacy entry can stop matching after every update.
SIGNING_IDENTITY="${RIBBON_SIGNING_IDENTITY:-}"
if [ -z "$SIGNING_IDENTITY" ] && [ -z "$SUFFIX" ]; then
  IDENTITIES="$(security find-identity -v -p codesigning | awk '/"Developer ID Application:/ {print $2}')"
  IDENTITY_COUNT="$(printf '%s\n' "$IDENTITIES" | awk 'NF {n++} END {print n+0}')"
  if [ "$IDENTITY_COUNT" -gt 1 ]; then
    printf 'Set RIBBON_SIGNING_IDENTITY to choose a Developer ID identity.\n' >&2
    exit 1
  fi
  SIGNING_IDENTITY="$IDENTITIES"
fi
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
SIGNING_OPTIONS=(--timestamp=none)
if [ "$SIGNING_IDENTITY" = - ]; then
  printf 'Ad-hoc build: Accessibility approval may need renewal after updates.\n' >&2
  SIGNING_KIND=ad-hoc
else
  SIGNING_OPTIONS=(--options runtime --timestamp)
  SIGNING_KIND=certificate
fi
cargo +1.95.0 build --manifest-path "$ROOT/vendor/paneru/Cargo.toml" --locked --no-default-features --profile "$PROFILE"
"$ROOT/scripts/swift.sh" build -c release
SWIFT_BIN="$("$ROOT/scripts/swift.sh" build -c release --show-bin-path)"
# An old linked-SDK stamp keeps AppKit/SwiftUI in compatibility appearance.
python3 - "$SWIFT_BIN/Ribbon" <<'SDKCHECK'
import re, subprocess, sys
output = subprocess.check_output(["xcrun", "vtool", "-show-build", sys.argv[1]], text=True)
match = re.search(r"^\s+sdk (\d+)", output, re.M)
if not match or int(match.group(1)) < 26:
    raise SystemExit("Ribbon must link SDK 26 or newer for native Liquid Glass controls")
SDKCHECK
KEY="$(printf %s "$ROOT" | shasum -a 256 | cut -c 1-12)"
STAGING="$HOME/Library/Caches/Ribbon/package-$KEY$SUFFIX"
mkdir -p "$STAGING"
python3 "$ROOT/scripts/collect-notices.py"
python3 "$ROOT/scripts/package-app.py" "$ROOT" "$SWIFT_BIN" "$STAGING" "$CARGO_TARGET_DIR/$ENGINE_DIRECTORY/paneru" "$SIGNING_KIND"
APP="$STAGING/Ribbon.app"
python3 "$ROOT/scripts/compile-icons.py" "$ROOT" "$APP" "$STAGING"
swift "$ROOT/scripts/make-icon.swift" "$ROOT/branding/explorations/fold/mark.png" "$APP/Contents/Resources/RibbonMenuTemplate.pdf"
codesign --force --sign "$SIGNING_IDENTITY" "${SIGNING_OPTIONS[@]}" --identifier dev.ribbon.fixture "$APP/Contents/Resources/Ribbon Demo.app"
codesign --force --sign "$SIGNING_IDENTITY" "${SIGNING_OPTIONS[@]}" --identifier dev.ribbon.sentinel "$APP/Contents/Resources/Ribbon Sentinel.app"
codesign --force --sign "$SIGNING_IDENTITY" "${SIGNING_OPTIONS[@]}" --identifier dev.ribbon.app "$APP/Contents/MacOS/ribbon-engine"
codesign --force --sign "$SIGNING_IDENTITY" "${SIGNING_OPTIONS[@]}" --identifier dev.ribbon.app "$APP"
codesign --verify --deep --strict "$APP"
ARCHIVE="$ROOT/build/Ribbon-beta$SUFFIX.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
# Documents/iCloud rewrites bundle metadata after signing. Keep the physical
# signed app in Caches, and deliver an immutable ZIP in the workspace.
python3 -c 'import json,sys; from pathlib import Path; Path(sys.argv[2]).write_text(json.dumps({"app":sys.argv[1],"archive":sys.argv[3]},indent=2))' "$APP" "$ROOT/build/artifacts$SUFFIX.json" "$ARCHIVE"
printf 'Built and verified: %s\nArchive: %s\n' "$APP" "$ARCHIVE"
