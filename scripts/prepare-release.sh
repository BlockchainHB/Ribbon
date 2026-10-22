#!/bin/bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
PROFILE="${1:-Ribbon}"
if [ "$#" -gt 1 ]; then
  printf 'Usage: prepare-release.sh [notary-keychain-profile]\n' >&2
  exit 2
fi
if ! git -C "$ROOT" diff --quiet || ! git -C "$ROOT" diff --cached --quiet; then
  printf 'Commit tracked source changes before preparing a public release.\n' >&2
  exit 1
fi
TAG="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["tag"])' "$ROOT/release.json")"
ASSET="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["asset"])' "$ROOT/release.json")"
OUTPUT="$ROOT/build/releases/$TAG"
mkdir -p "$OUTPUT"
"$ROOT/scripts/build-app.sh"
APP="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["app"])' "$ROOT/build/artifacts.json")"
codesign -dv --verbose=4 "$APP" 2> "$OUTPUT/signature.txt"
if ! grep -q '^Authority=Developer ID Application:' "$OUTPUT/signature.txt" || ! grep -q 'flags=.*runtime' "$OUTPUT/signature.txt" || ! grep -q '^Timestamp=' "$OUTPUT/signature.txt"; then
  printf 'Public releases require timestamped Developer ID signing with Hardened Runtime.\n' >&2
  exit 1
fi
if [ "$(lipo -archs "$APP/Contents/MacOS/Ribbon")" != arm64 ] || [ "$(lipo -archs "$APP/Contents/MacOS/ribbon-engine")" != arm64 ]; then
  printf 'This release asset is for Apple silicon only.\n' >&2
  exit 1
fi
codesign --verify --deep --strict "$APP"
NOTARY_ARCHIVE="$OUTPUT/notarization-upload.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$NOTARY_ARCHIVE"
xcrun notarytool submit "$NOTARY_ARCHIVE" --keychain-profile "$PROFILE" --wait --timeout 20m --output-format json > "$OUTPUT/notarization.json"
python3 - "$OUTPUT/notarization.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
if result.get("status") != "Accepted":
    raise SystemExit(f'Notarization did not pass: {result.get("status")}. Submission: {result.get("id")}')
print("Apple notarization: Accepted", flush=True)
PY
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --deep --strict "$APP"
spctl --assess --type execute --verbose=2 "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUTPUT/$ASSET"
python3 - "$ROOT" "$OUTPUT" "$APP" <<'PY'
import hashlib, json, pathlib, subprocess, sys, zipfile
root, output, app = map(pathlib.Path, sys.argv[1:])
release = json.loads((root / "release.json").read_text())
asset = output / release["asset"]
with zipfile.ZipFile(asset) as archive:
    bad = archive.testzip()
    if bad:
        raise SystemExit(f"Archive integrity failed: {bad}")
checksum = hashlib.sha256(asset.read_bytes()).hexdigest()
(output / "SHA256SUMS.txt").write_text(f'{checksum}  {asset.name}\n')
build = json.loads((app / "Contents/Resources/BUILD.json").read_text())
commit = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
if build["source_commit"] != commit:
    raise SystemExit("Bundle source commit does not match HEAD")
manifest = {**release, "source_commit": commit, "architecture": "arm64", "minimum_macos": "15.0",
            "sha256": checksum, "signing": "Developer ID", "hardened_runtime": True,
            "notarization": "Accepted", "stapled": True, "gatekeeper": "accepted"}
(output / "release-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(f"Release archive: {asset}")
print(f"SHA-256: {checksum}")
PY
