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
exec swift "$COMMAND" --package-path "$ROOT/native" --scratch-path "$CACHE" "$@"
