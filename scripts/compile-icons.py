#!/usr/bin/env python3
"""Compile the approved adaptive icon and merge Apple's generated bundle metadata."""
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

root, app, staging = map(Path, sys.argv[1:])
document = root / "branding/IconComposer/Ribbon.icon"
compiled = staging / "IconAssets"
compiled.mkdir(exist_ok=True)
partial = compiled / "Info.plist"
subprocess.run([
    "xcrun", "actool", str(document), "--compile", str(compiled),
    "--app-icon", "Ribbon", "--platform", "macosx", "--minimum-deployment-target", "15.0",
    "--output-partial-info-plist", str(partial), "--output-format", "human-readable-text",
    "--warnings", "--notices",
], check=True)
resources = app / "Contents/Resources"
for name in ("Assets.car", "Ribbon.icns"):
    source = compiled / name
    if not source.is_file() or source.stat().st_size == 0:
        raise SystemExit(f"Icon Composer compilation did not produce {name}")
    shutil.copy2(source, resources / name)

info_path = app / "Contents/Info.plist"
with info_path.open("rb") as handle:
    info = plistlib.load(handle)
with partial.open("rb") as handle:
    info.update(plistlib.load(handle))
with info_path.open("wb") as handle:
    plistlib.dump(info, handle)

(resources / "IconBuild.json").write_text(json.dumps({
    "document": "branding/IconComposer/Ribbon.icon", "name": "Ribbon",
    "manifest_sha256": hashlib.sha256((document / "icon.json").read_bytes()).hexdigest(),
    "catalog_sha256": hashlib.sha256((resources / "Assets.car").read_bytes()).hexdigest(),
    "minimum_deployment_target": "15.0",
}, indent=2) + "\n")
