#!/usr/bin/env python3
"""Fetch public source snapshots and record provenance; never runs project code."""
import concurrent.futures
import datetime
import json
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
REPOS = [
    "karinushka/paneru", "mogenson/PaperWM.spoon", "OmniNull/OmniWM",
    "apphane-dev/nehir", "qeude/Defi", "glide-wm/glide", "acsandmann/rift",
    "niri-wm/niri", "paperwm/PaperWM", "nikitabobko/AeroSpace",
    "asmvik/yabai", "ianyh/Amethyst", "rxhanson/Rectangle", "MrKai77/Loop",
    "Hammerspoon/hammerspoon", "kasper/phoenix", "eczarny/spectacle",
]

def run(args, cwd=None):
    return subprocess.check_output(args, cwd=cwd, text=True, stderr=subprocess.PIPE).strip()

def collect(repo):
    meta = json.loads(run(["gh", "api", "repos/" + repo]))
    name = meta["full_name"]
    dest = ROOT / ".research" / "repos" / name.replace("/", "__")
    if not dest.exists():
        run(["git", "clone", "--depth", "1", "--quiet", meta["clone_url"], str(dest)])
    record = {k: meta.get(k) for k in ["full_name", "html_url", "description", "language", "stargazers_count", "pushed_at", "archived", "default_branch"]}
    record.update(license=(meta.get("license") or {}).get("spdx_id"),
                  commit=run(["git", "rev-parse", "HEAD"], cwd=dest),
                  commit_date=run(["git", "show", "-s", "--format=%cI", "HEAD"], cwd=dest),
                  local_path=str(dest.relative_to(ROOT)))
    print(json.dumps(record), flush=True)
    return record

if __name__ == "__main__":
    records, errors = [], []
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        futures = {pool.submit(collect, repo): repo for repo in REPOS}
        for future in concurrent.futures.as_completed(futures):
            try:
                records.append(future.result())
            except Exception as error:
                errors.append({"repo": futures[future], "error": str(error)})
                print(json.dumps(errors[-1]), flush=True)
    output = {"fetched_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "scope": "Architectural source review; no runtime benchmark or project builds",
              "repositories": sorted(records, key=lambda item: item["full_name"].lower()), "errors": errors}
    (ROOT / "research" / "sources.json").write_text(json.dumps(output, indent=2) + "\n")
