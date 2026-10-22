#!/bin/bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
COMMAND="$1"
shift
case "$COMMAND" in
  build|test) ;;
  *) printf 'Expected build or test\n' >&2; exit 2 ;;
esac
# Keep signed test bundles outside Documents/iCloud, which adds Finder metadata.
KEY="$(printf %s "$ROOT" | shasum -a 256 | cut -c 1-12)"
CACHE="$HOME/Library/Caches/Ribbon/swift-$KEY"
mkdir -p "$CACHE"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
# Swift Build in Xcode 27 stamps the deployment target as the linked SDK.
# The native SwiftPM backend correctly links the current SDK (verified at packaging).
exec swift "$COMMAND" --sdk "$SDK" --build-system native --package-path "$ROOT/native" --scratch-path "$CACHE" "$@"
