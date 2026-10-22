#!/usr/bin/env python3
import json
import pathlib
import plistlib
import shutil
import subprocess
import sys

root, swift_bin, staging, engine = map(pathlib.Path, sys.argv[1:5])
signing_kind = sys.argv[5] if len(sys.argv) > 5 else "ad-hoc"
release = json.loads((root / "release.json").read_text())
source_commit = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
app = staging / "Ribbon.app"
if app.exists():
    shutil.rmtree(app)

def bundle(path, name, identifier, executable, source):
    macos = path / "Contents" / "MacOS"
    resources = path / "Contents" / "Resources"
    macos.mkdir(parents=True)
    resources.mkdir()
    shutil.copy2(source, macos / executable)
    plist = {
        "CFBundleIdentifier": identifier, "CFBundleName": name,
        "CFBundleDisplayName": name, "CFBundleExecutable": executable,
        "CFBundlePackageType": "APPL", "CFBundleShortVersionString": release["version"],
        "CFBundleVersion": release["build"], "LSMinimumSystemVersion": "15.0",
        "NSHighResolutionCapable": True, "NSPrincipalClass": "NSApplication",
    }
    if identifier == "dev.ribbon.app":
        plist["CFBundleIconFile"] = "Ribbon"
        plist["CFBundleIconName"] = "Ribbon"
    with (path / "Contents" / "Info.plist").open("wb") as output:
        plistlib.dump(plist, output)
    return resources

resources = bundle(app, "Ribbon", "dev.ribbon.app", "Ribbon", swift_bin / "Ribbon")
shutil.copy2(engine, app / "Contents/MacOS/ribbon-engine")
bundle(resources / "Ribbon Demo.app", "Ribbon Demo", "dev.ribbon.fixture", "RibbonFixture", swift_bin / "RibbonFixture")
bundle(resources / "Ribbon Sentinel.app", "Ribbon Sentinel", "dev.ribbon.sentinel", "RibbonFixture", swift_bin / "RibbonFixture")
license_text = (root / "vendor/paneru/LICENSE.txt").read_text()
(resources / "ThirdPartyNotices.txt").write_text(
    "Ribbon includes Paneru 0.5.2, commit 12c58b2225a40e434053ea9343a41e2012466f9a.\n"
    "https://github.com/karinushka/paneru\nLocal integration changes: vendor/paneru/RIBBON.md\n\n" + license_text)
(resources / "BUILD.json").write_text(json.dumps({
    "version": release["version"], "build": release["build"], "engine": "Paneru 0.5.2",
    "upstream_commit": "12c58b2225a40e434053ea9343a41e2012466f9a",
    "signing": signing_kind, "source_commit": source_commit,
    "engine_profile": engine.parent.name,
}, indent=2))
shutil.copy2(root / "docs/about.html", resources / "README.html")
shutil.copy2(root / "build/DependencyLicenses.txt", resources / "DependencyLicenses.txt")
# iCloud adds presentation metadata to bundles in Documents; it is not build input.
for attribute in ("com.apple.FinderInfo", "com.apple.ResourceFork"):
    subprocess.run(["/usr/bin/xattr", "-rd", attribute, str(app)],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
