#!/usr/bin/env python3
"""Collect checked-in license texts for the resolved Rust dependency graph."""
import json
import pathlib
import subprocess

root = pathlib.Path(__file__).resolve().parents[1]
metadata = json.loads(subprocess.check_output([
    "cargo", "+1.95.0", "metadata", "--locked", "--no-default-features",
    "--filter-platform", "aarch64-apple-darwin", "--format-version", "1",
    "--manifest-path", str(root / "vendor/paneru/Cargo.toml"),
], text=True))
active = {node["id"] for node in metadata["resolve"]["nodes"]}
entries, sections = [], []
for package in sorted(metadata["packages"], key=lambda p: (p["name"], p["version"])):
    if package["id"] not in active:
        continue
    directory = pathlib.Path(package["manifest_path"]).parent
    texts = set()
    for pattern in ("LICENSE*", "LICENCE*", "COPYING*", "COPYRIGHT*"):
        texts.update(p for p in directory.glob(pattern) if p.is_file())
    if package.get("license_file"):
        explicit = directory / package["license_file"]
        if explicit.is_file():
            texts.add(explicit)
    record = {
        "name": package["name"], "version": package["version"],
        "license": package.get("license"), "repository": package.get("repository"),
        "license_files": [p.name for p in sorted(texts)],
    }
    entries.append(record)
    sections.append(f'{record["name"]} {record["version"]}\nLicense: {record["license"]}\nSource: {record["repository"]}\n')
    for path in sorted(texts):
        sections.append(f"--- {path.name} ---\n{path.read_text(errors='replace')}\n")
output = root / "build"
output.mkdir(exist_ok=True)
(output / "DependencyLicenses.txt").write_text(
    "Resolved macOS Rust graph, including build and test dependencies. Some entries may not be linked in the app.\n\n"
    + "\n".join(sections))
(output / "dependency-licenses.json").write_text(json.dumps(entries, indent=2) + "\n")
print(f"Collected notices for {len(entries)} resolved packages.")
