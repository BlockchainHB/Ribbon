#!/usr/bin/env python3
"""Opt-in engine profiling with disposable windows and native keyboard input.

Usage: RIBBON_QA_KEYBOARD=1 python3 scripts/qa-performance.py OUTPUT SIGNED_APP
Pause Ribbon first. A fresh output directory is required. No personal windows are managed.
"""

import hashlib
import json
import os
import subprocess
import sys
import time
from pathlib import Path

if len(sys.argv) not in (2, 3):
    raise SystemExit("Usage: qa-performance.py FRESH_OUTPUT [SIGNED_APP]")
root = Path(__file__).resolve().parents[1]
out = Path(sys.argv[1]).expanduser().resolve()
out.mkdir(parents=True, exist_ok=False)
app = (
    Path(sys.argv[2]).expanduser().resolve()
    if len(sys.argv) > 2
    else Path.home() / "Applications/Ribbon.app"
)
engine = app / "Contents/MacOS/ribbon-engine"
helper = out / "input"
subprocess.run(
    ["swiftc", str(root / "scripts/qa-performance-input.swift"), "-o", str(helper)],
    check=True,
)
env = os.environ | {
    "PANERU_MACH_SERVICE": f"dev.ribbon.nav.{os.getpid()}",
    "PANERU_CONFIG": str(out / "engine.toml"),
    "XDG_STATE_HOME": str(out / "state"),
    "XDG_CONFIG_HOME": str(out / "config"),
    "RIBBON_PARENT_PID": str(os.getpid()),
    "RIBBON_MANAGEMENT_SCOPE": "selected",
    "RIBBON_MANAGED_APPS": "dev.ribbon.fixture",
    "RIBBON_EXCLUDED_APPS": "",
    "RUST_LOG": "warn",
    "RIBBON_PERF_OUTPUT": str(out / "performance.json"),
}
config = subprocess.check_output(
    [str(app / "Contents/MacOS/Ribbon"), "--print-config"], text=True
).replace("auto_center = true", "auto_center = false")
(out / "engine.toml").write_text(config)


def run(*args):
    return subprocess.check_output(
        [str(x) for x in args], env=env, text=True, timeout=15
    ).strip()


def cmd(*args):
    return run(engine, "send-cmd", "window", *args)


def load():
    return json.loads((out / "fixture.json").read_text())


def eventually(f):
    for _ in range(100):
        try:
            if f():
                return
        except Exception:
            pass
        time.sleep(0.05)
    raise RuntimeError("timed out")


if (
    subprocess.run(["pgrep", "-x", "ribbon-engine"], capture_output=True).returncode
    == 0
):
    raise RuntimeError("Pause Ribbon before isolated QA")
run(
    "open",
    "-n",
    app / "Contents/Resources/Ribbon Demo.app",
    "--args",
    "--report",
    out / "fixture.json",
    "--dual-displays",
)
eventually(lambda: len(load()) == 8)
# Launching/quitting the QA app changes Dock sizing. Wait for the actual
# NSWindow frames to settle before recording the restoration baseline.
last_geometry = None
stable_since = time.monotonic()
deadline = stable_since + 8
while True:
    original = load()
    geometry = [(w["id"], w["x"], w["y"], w["width"], w["height"]) for w in original]
    now = time.monotonic()
    if geometry != last_geometry:
        last_geometry, stable_since = geometry, now
    if now - stable_since >= 0.75:
        break
    if now >= deadline:
        raise RuntimeError("Fixture geometry did not settle before profiling")
    time.sleep(0.05)
(out / "original.json").write_text(json.dumps(original))
displays = json.loads(run(helper, "displays"))
(out / "displays.json").write_text(json.dumps(displays))
proc = None
events = []
receipts = []
checks = []
(out / "engine-sha256.txt").write_text(hashlib.sha256(engine.read_bytes()).hexdigest())
try:
    with (out / "engine.log").open("w") as log:
        proc = subprocess.Popen(
            [str(engine), "launch"], env=env, stdout=log, stderr=log
        )
        time.sleep(1)
        (out / "queried.json").write_text(run(engine, "query", "state", "--json"))
        eventually(
            lambda: [
                w
                for s in json.loads(run(engine, "query", "state", "--json"))[
                    "virtual_workspaces"
                ]
                for w in s["windows"]
            ]
        )
        state = json.loads(run(engine, "query", "state", "--json"))
        assert all(
            (
                w["bundle_id"] == "dev.ribbon.fixture"
                for w in [w for s in state["virtual_workspaces"] for w in s["windows"]]
            )
        )
        # Preserve ordinary native frames as the recovery baseline. Creating a
        # maximized window before Dock activation settles can place its bottom
        # outside the later usable area, where AppKit necessarily constrains it.
        # Build the same overflowing full-width workload through Ribbon instead.
        for target in original:
            run(helper, "focus", target["id"])
            owner = next(d for d in displays if d["id"] == target["screenID"])
            eventually(
                lambda: any(
                    w["id"] == target["id"]
                    and w["focused"]
                    and w["x"] >= owner["x"] - 2
                    and w["x"] + w["width"] <= owner["x"] + owner["width"] + 2
                    for w in load()
                )
            )
            time.sleep(0.35)
            cmd("fullwidth")
            time.sleep(0.4)
        for display in displays:
            own = [w for w in original if w["screenID"] == display["id"]]
            run(helper, "focus", own[0]["id"])
            time.sleep(0.4)
            cmd("focus", "first")
            time.sleep(0.4)
            run(helper, "motion", "begin")
            time.sleep(0.1)
            for lap in range(2):
                for direction, code in [("right", 124)] * 3 + [("left", 123)] * 3:
                    before = next((w["id"] for w in load() if w["focused"]))
                    stamp = time.monotonic()
                    if os.environ.get("RIBBON_QA_KEYBOARD") == "1":
                        stamp = float(
                            run(
                                "swift",
                                root / "scripts/qa-performance-input.swift",
                                "key",
                                code,
                            )
                        )
                    else:
                        cmd("focus", "east" if direction == "right" else "west")
                    try:
                        eventually(
                            lambda: any(
                                (w["focused"] and w["id"] != before for w in load())
                            )
                        )
                    except Exception:
                        (out / "failure.json").write_text(
                            json.dumps(
                                {
                                    "display": display,
                                    "direction": direction,
                                    "before": before,
                                    "events": events,
                                    "frames": load(),
                                    "state": json.loads(
                                        run(engine, "query", "state", "--json")
                                    ),
                                }
                            )
                        )
                        run(helper, "motion", "end")
                        raise
                    events.append(
                        {
                            "display": display["id"],
                            "direction": direction,
                            "time": stamp,
                        }
                    )
                    time.sleep(0.6)
            run(helper, "motion", "end")
            eventually(lambda: (out / "motion-frames.json").exists())
            frames = json.loads((out / "motion-frames.json").read_text())
            (out / f"motion-{int(display['id'])}.json").write_text(json.dumps(frames))
            (out / "motion-frames.json").unlink()
            own_events = [e for e in events if e["display"] == display["id"]]
            ids = {w["id"] for w in own}
            for e in own_events:
                samples = [
                    s
                    for s in frames
                    if e["time"] - 0.08 <= s["time"] <= e["time"] + 0.55
                ]
                before = [s for s in samples if s["time"] <= e["time"]]
                if not before:
                    continue
                anchor = {w["id"]: w for w in before[-1]["frames"] if w["id"] in ids}
                moved = [
                    s
                    for s in samples
                    if s["time"] >= e["time"]
                    and any(
                        (
                            abs(w["x"] - anchor[w["id"]]["x"]) > 1
                            for w in s["frames"]
                            if w["id"] in anchor
                        )
                    )
                ]
                receipts.append(
                    e
                    | {
                        "firstMovementMS": (
                            (moved[0]["time"] - e["time"]) * 1000 if moved else None
                        ),
                        "sampleIntervalsMS": [
                            (b["time"] - a["time"]) * 1000
                            for a, b in zip(moved, moved[1:])
                        ],
                    }
                )
            cmd("focus", "first")
            time.sleep(0.4)
            selected = next((w for w in load() if w["focused"]))
            run(helper, "width", selected["id"], display["width"] * 2 / 3)
            time.sleep(0.4)
            cmd("center")
            time.sleep(0.4)
            (out / f"center-{int(display['id'])}.json").write_text(json.dumps(load()))
            run(
                "screencapture",
                "-x",
                "-D",
                displays.index(display) + 1,
                out / f"center-{int(display['id'])}.png",
            )
        for target in original:
            run(helper, "focus", target["id"])
            owner = next((d for d in displays if d["id"] == target["screenID"]))
            eventually(
                lambda: any(
                    (
                        w["id"] == target["id"]
                        and w["focused"]
                        and (w["x"] >= owner["x"] - 2)
                        and (w["x"] + w["width"] <= owner["x"] + owner["width"] + 2)
                        and (w["y"] < owner["y"] + owner["height"] / 2)
                        for w in load()
                    )
                )
            )
            checks.append(
                {
                    "check": "native external activation reveals tile on its owner",
                    "window": target["id"],
                    "passed": True,
                }
            )
        # Retain measurements even when the old baseline fails a stricter
        # correctness assertion. Failed checks are never reported as passing.
        (out / "measurements.json").write_text(json.dumps(receipts, indent=2))
        (out / "engine-cpu-time.txt").write_text(
            run("ps", "-p", proc.pid, "-o", "time=")
        )
        for d in displays:
            centered = json.loads((out / f"center-{int(d['id'])}.json").read_text())
            visible = [
                w
                for w in centered
                if w["screenID"] == d["id"]
                and w["x"] >= d["x"] - 2
                and (w["x"] + w["width"] <= d["x"] + d["width"] + 2)
                and (w["y"] < d["y"] + d["height"] / 2)
            ]
            assert len(visible) >= 2, "Resized tile must retain a visible neighbor"
            checks.append(
                {
                    "check": "native visible neighbor beside centered tile",
                    "display": d["id"],
                    "passed": True,
                }
            )
            for sample in json.loads((out / f"motion-{int(d['id'])}.json").read_text()):
                for w in sample["frames"]:
                    owner_id = next(
                        (o["screenID"] for o in original if o["id"] == w["id"])
                    )
                    for other in displays:
                        if other["id"] == owner_id:
                            continue
                        overlap_x = min(
                            w["x"] + w["width"], other["x"] + other["width"]
                        ) - max(w["x"], other["x"])
                        overlap_y = min(
                            w["y"] + w["height"], other["y"] + other["height"]
                        ) - max(w["y"], other["y"])
                        assert (
                            overlap_x <= 2 or overlap_y <= 2
                        ), "Native body leaked onto another monitor"
            checks.append(
                {
                    "check": "no native body on neighboring display in recorded samples",
                    "display": d["id"],
                    "passed": True,
                }
            )
            # This workload has separate columns, not vertical stacks. Ignore
            # intentional one-point parking edges and check actual content bodies.
            for sample in json.loads((out / f"motion-{int(d['id'])}.json").read_text()):
                visible = []
                for window in sample["frames"]:
                    width = max(
                        0,
                        min(window["x"] + window["width"], d["x"] + d["width"])
                        - max(window["x"], d["x"]),
                    )
                    height = max(
                        0,
                        min(window["y"] + window["height"], d["y"] + d["height"])
                        - max(window["y"], d["y"]),
                    )
                    if width * height > window["width"] * window["height"] / 2:
                        visible.append(window)
                visible.sort(key=lambda window: window["x"])
                assert all(
                    right["x"] >= left["x"] + left["width"] - 1
                    for left, right in zip(visible, visible[1:])
                ), "Native columns overlapped during movement"
            checks.append(
                {
                    "check": "no overlapping native columns in recorded samples",
                    "display": d["id"],
                    "passed": True,
                }
            )

        assert len(receipts) == 24 and all(
            (r["firstMovementMS"] is not None for r in receipts)
        )
        checks.append(
            {"check": "24 left/right changes produce native movement", "passed": True}
        )
finally:
    if proc and proc.poll() is None:
        run(engine, "send-cmd", "quit")
        proc.wait(timeout=8)
    time.sleep(0.25)
    restored = load()
    (out / "restored.json").write_text(json.dumps(restored))
    restored_ok = all(
        (
            any(
                (
                    w["id"] == o["id"]
                    and all(
                        (abs(w[k] - o[k]) < 3 for k in ["x", "y", "width", "height"])
                    )
                    for w in restored
                )
            )
            for o in original
        )
    )
    checks.append(
        {"check": "all original native frames restored on stop", "passed": restored_ok}
    )
    (out / "checks.json").write_text(json.dumps(checks, indent=2))
    run(
        "osascript",
        "-e",
        f'tell application "{app}/Contents/Resources/Ribbon Demo.app" to quit',
    )
    assert restored_ok, "Original fixture frames were not restored"
print(f"{len(checks)} native checks passed; measurements: {out}")
