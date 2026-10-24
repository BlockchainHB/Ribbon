#!/usr/bin/env python3
"""Compile the current pure Motion implementation, without launching an engine.

Uses the pinned, already built bevy_math rlib. Receipts retain the exact source
and hash. Half-point presentation is a mathematical counterfactual, not an
implemented native backend. No app/window/privacy APIs are called.
"""
import argparse
import csv
import hashlib
import io
import json
from pathlib import Path
import statistics
import subprocess

ROOT = Path(__file__).resolve().parents[1]

RUST = r'''
use bevy_math::{DVec2, IVec2};
mod actual {
    use super::*;
    SOURCE
    pub fn run(name: &str, distance: i32, hz: f64, schedule: &[f64], retarget: bool) {
        let mut motion = Motion::default();
        let mut frame = IVec2::ZERO;
        let mut now = 0.0;
        for i in 0..2000 {
            let delta = schedule[i % schedule.len()];
            now += delta;
            let target = if retarget && now > 0.08 { -distance } else { distance };
            let old = frame.x;
            // Tick-only counterfactual: the driver already selects the owner's
            // display ticks, so avoid applying a second elapsed-time rate cap.
            let interval = if name == "clock_deadline_tick" { 0.0 } else { 1.0 / hz };
            let (output, done) = motion.step(frame, IVec2::new(target, 0), 14.0, delta, interval);
            frame = output;
            println!("{name},{distance},{hz},{now},{target},{},{},{},{},{done}",
                     output.x, motion.current.x, motion.velocity.x, old != output.x);
            if done && (!retarget || now > 0.08) { break }
        }
    }
}
fn main() {
    println!("case,distance,hz,time,target,output,ideal,velocity,changed,done");
    for hz in [60.0, 120.0] {
        for distance in [1, 4, 12, 64, 512, 1800] {
            actual::run("fixed", distance, hz, &[1.0 / hz], false);
            actual::run("busy_1ms", distance, hz, &[0.001], false);
            actual::run("reverse_80ms", distance, hz, &[1.0 / hz], true);
        }
        actual::run("clock_quiet", 512, hz, &CLOCK_QUIET, false);
        actual::run("clock_work6", 512, hz, &CLOCK_WORK6, false);
        let deadlines: &[f64] = if hz == 60.0 { &CLOCK_DEADLINE60 } else { &CLOCK_DEADLINE120 };
        actual::run("clock_deadline", 512, hz, deadlines, false);
        actual::run("clock_deadline_tick", 512, hz, deadlines, false);
    }
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--clock", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    source = (ROOT / "vendor/paneru/src/ecs/motion.rs").read_text()
    # Compile the exact production implementation; fail if its boundaries drift.
    start = source.index("#[derive(Default)]\npub(super) struct Motion")
    end = source.index("#[cfg(test)]", start)
    implementation = source[start:end]
    clock_bytes = args.clock.read_bytes()
    clock = json.loads(clock_bytes)
    template = RUST.replace("SOURCE", implementation)
    for name, mode, work in [("QUIET", "current", 0), ("WORK6", "current", 6),
                             ("DEADLINE60", "deadline60", 0),
                             ("DEADLINE120", "deadline120", 0)]:
        trial = next(t for t in clock["trials"] if t["mode"] == mode and t["work_ms"] == work)
        template = template.replace("CLOCK_" + name,
            "[" + ",".join(repr(r["interval"]) for r in trial["rows"]) + "]")
    probe = args.output / "probe.rs"
    probe.write_text(template)
    deps = ROOT / "build/cargo/release/deps"
    libraries = sorted(deps.glob("libbevy_math-*.rlib"))
    if len(libraries) != 1:
        raise RuntimeError("Expected exactly one pinned release bevy_math rlib; build the release engine first")
    binary = args.output / "probe"
    subprocess.run(["rustc", "--edition=2024", "-O", str(probe), "-L", f"dependency={deps}",
                    "--extern", f"bevy_math={libraries[0]}", "-o", str(binary)], check=True)
    output = subprocess.check_output([str(binary)], text=True)
    (args.output / "samples.csv").write_text(output)
    groups = {}
    for raw in csv.DictReader(io.StringIO(output)):
        key = (raw["case"], int(raw["distance"]), int(float(raw["hz"])))
        row = {k: float(raw[k]) for k in ["time", "target", "output", "ideal", "velocity"]}
        row.update(changed=raw["changed"] == "true", done=raw["done"] == "true")
        groups.setdefault(key, []).append(row)
    summaries = []
    for (case, distance, hz), rows in groups.items():
        assert rows[-1]["done"] and rows[-1]["output"] == rows[-1]["target"], (case, distance, hz)
        if case != "reverse_80ms":
            assert all(0 <= r["output"] <= distance for r in rows)
            assert all(a["output"] <= b["output"] for a, b in zip(rows, rows[1:]))
        else:
            assert all(-distance <= r["output"] <= distance for r in rows)
            for a, b in zip(rows, rows[1:]):
                assert b["output"] <= a["output"] if b["target"] < 0 else b["output"] >= a["output"]
        changes = [r for r in rows if r["changed"]]
        gaps = [b["time"] - a["time"] for a, b in zip(changes, changes[1:])]
        # At nominal display cadence only, compare whole and half-point grids
        # against the same curve without changing its timing or velocity.
        rounded_half = [round(r["ideal"] * 2) / 2 for r in rows]
        summaries.append(dict(case=case, distance=distance, hz=hz,
            completion_ms=rows[-1]["time"] * 1000, changed_outputs=len(changes),
            first_change_ms=changes[0]["time"] * 1000 if changes else None,
            maximum_change_gap_ms=max(gaps, default=0) * 1000,
            rms_presented_curve_error_pt=statistics.mean((r["output"] - r["ideal"]) ** 2 for r in rows) ** 0.5,
            rms_integer_grid_error_pt=statistics.mean((round(r["ideal"]) - r["ideal"]) ** 2 for r in rows) ** 0.5,
            rms_halfpoint_error_pt=statistics.mean((a - r["ideal"]) ** 2 for a, r in zip(rounded_half, rows)) ** 0.5,
            hypothetical_halfpoint_changes=sum(a != b for a, b in zip([0] + rounded_half, rounded_half))))
    result = {"source_sha256": hashlib.sha256(source.encode()).hexdigest(),
              "clock_sha256": hashlib.sha256(clock_bytes).hexdigest(),
              "source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
              "note": "Pure production Motion with synthetic or measured windowless deltas; no compositor evidence.",
              "scenarios": summaries}
    (args.output / "summary.json").write_text(json.dumps(result, indent=2) + "\n")
    print(f"{len(summaries)} scenarios passed endpoint and monotonic-bounds checks; {args.output}")


if __name__ == "__main__":
    main()
