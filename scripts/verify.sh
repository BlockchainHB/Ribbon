#!/bin/bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cargo +1.95.0 fmt --manifest-path "$ROOT/vendor/paneru/Cargo.toml" --check
cargo +1.95.0 clippy --manifest-path "$ROOT/vendor/paneru/Cargo.toml" --all-targets -- -D warnings
cargo +1.95.0 test --manifest-path "$ROOT/vendor/paneru/Cargo.toml" --locked --all-targets
cargo +1.95.0 test --manifest-path "$ROOT/vendor/paneru/Cargo.toml" --locked --no-default-features --all-targets
swift format lint --strict --recursive "$ROOT/native/Sources" "$ROOT/native/Tests" "$ROOT/native/Package.swift" "$ROOT/scripts/make-icon.swift"
"$ROOT/scripts/swift.sh" test
git -C "$ROOT" diff --check
KEY="$(printf %s "$ROOT" | shasum -a 256 | cut -c 1-12)"
APP="$HOME/Library/Caches/Ribbon/package-$KEY/Ribbon.app"
if [ -x "$APP/Contents/MacOS/Ribbon" ]; then
  "$APP/Contents/MacOS/Ribbon" --print-config > "$ROOT/build/generated-engine.toml"
  "$APP/Contents/MacOS/ribbon-engine" check-config "$ROOT/build/generated-engine.toml"
  codesign --verify --deep --strict "$APP"
fi
