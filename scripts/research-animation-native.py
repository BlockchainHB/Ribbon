#!/usr/bin/env python3
"""Exercise the actual Rust display callback/pump without windows or an engine."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
PROBE = r'''
use std::sync::{Arc, OnceLock};
use std::sync::atomic::{AtomicBool, Ordering};
use std::ptr::NonNull;
use std::ffi::c_short;
use objc2::{MainThreadMarker};
use objc2::rc::{Retained, autoreleasepool};
use objc2_app_kit::{NSApplication, NSApplicationActivationPolicy, NSEvent, NSEventMask,
    NSEventModifierFlags, NSEventType, NSScreen};
use objc2_foundation::{NSDate, NSDefaultRunLoopMode, NSPoint, NSString, NSNumber};
use tracing::error;
WAKER
#[path = "ANIMATION_PATH"]
mod animation;
mod performance {
    use std::collections::BTreeMap;
    use std::sync::{LazyLock, Mutex};
    use std::time::Instant;
    #[derive(Default)]
    pub struct Samples { pub callbacks: Vec<f64>, pub updates: Vec<f64> }
    pub static RECORDS: LazyLock<Mutex<BTreeMap<u32, Samples>>> = LazyLock::new(Default::default);
    static START: LazyLock<Instant> = LazyLock::new(Instant::now);
    pub fn display_tick(id: u32, consumed: bool) {
        let now = START.elapsed().as_secs_f64();
        let mut records = RECORDS.lock().unwrap();
        let record = records.entry(id).or_default();
        if consumed { record.updates.push(now); } else { record.callbacks.push(now); }
    }
    pub fn display_stopped(_: u32) {}
}
struct Events(Arc<EventLoopWaker>);
impl Events { fn waker(&self) -> &Arc<EventLoopWaker> { &self.0 } }
struct Pump { events: Events, cocoa_app: Retained<NSApplication> }
impl Pump { PUMP }
fn main() {
    let output = std::env::args().nth(1).expect("output path");
    assert!(!std::path::Path::new(&output).exists());
    let marker = MainThreadMarker::new().unwrap();
    let app = NSApplication::sharedApplication(marker);
    app.setActivationPolicy(NSApplicationActivationPolicy::Prohibited);
    app.finishLaunching();
    let waker = Arc::new(EventLoopWaker::new());
    waker.install(&app);
    let mut pump = Pump { events: Events(waker.clone()), cocoa_app: app };
    let mut clocks = animation::DisplayLinks::new(waker, marker);
    let displays: Vec<_> = NSScreen::screens(marker).iter().map(|screen| {
        let id = screen.deviceDescription().objectForKey(&NSString::from_str("NSScreenNumber"))
            .unwrap().downcast::<NSNumber>().unwrap().unsignedIntValue();
        (id, 1.0 / screen.maximumFramesPerSecond() as f64)
    }).collect();
    assert!(!displays.is_empty());
    let mut rounds = Vec::new();
    for _ in 0..3 {
        performance::RECORDS.lock().unwrap().clear();
        clocks.configure(&displays);
        let start = std::time::Instant::now();
        let mut returns = 0;
        while start.elapsed().as_secs_f64() < 1.2 {
            pump.pump_cocoa_event_loop(clocks.wait(0.5));
            let _ = clocks.take_due();
            returns += 1;
        }
        clocks.configure(&[]);
        assert!(clocks.take_due().is_empty());
        let before: usize = performance::RECORDS.lock().unwrap().values().map(|r| r.callbacks.len()).sum();
        for _ in 0..4 { pump.pump_cocoa_event_loop(0.05); }
        let records = performance::RECORDS.lock().unwrap();
        assert_eq!(before, records.values().map(|r| r.callbacks.len()).sum::<usize>(), "callback leaked after idle");
        assert!(displays.iter().all(|(id, _)| records.get(id).is_some_and(|r| r.callbacks.len() > 10 && r.updates.len() > 10)));
        rounds.push(serde_json::json!({"pump_returns": returns, "displays": records.iter().map(|(id, r)| {
            (id.to_string(), serde_json::json!({"callbacks": r.callbacks, "updates": r.updates}))
        }).collect::<serde_json::Map<_, _>>(), "idle_callbacks": 0}));
    }
    let report = serde_json::json!({"rounds": rounds, "configured_displays": displays,
        "environment_gate": animation::enabled(),
        "note": "Actual Rust display-link module, event waker and Cocoa pump; windowless, no engine/AX/system input/capture; callbacks are not pixel delivery."});
    std::fs::write(output, serde_json::to_vec_pretty(&report).unwrap()).unwrap();
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    platform = (ROOT / "vendor/paneru/src/platform.rs").read_text()
    waker = platform[platform.index("const WAKE_EVENT_SUBTYPE:"):platform.index("/// `PlatformCallbacks` aggregates")]
    start = platform.index("    pub fn pump_cocoa_event_loop(")
    # Balanced braces extract the exact native pump, excluding its parent impl.
    opening = platform.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (platform[end] == "{") - (platform[end] == "}")
        end += 1
    source = PROBE.replace("WAKER", waker).replace("PUMP", platform[start:end]).replace(
        "ANIMATION_PATH", str(ROOT / "vendor/paneru/src/platform/animation.rs"))
    probe = args.output / "probe.rs"
    probe.write_text(source)
    deps = ROOT / "build/cargo/release/deps"
    command = ["rustc", "--edition=2024", "-O", str(probe), "-L", f"dependency={deps}"]
    for name in ["objc2", "objc2_app_kit", "objc2_foundation", "objc2_quartz_core", "tracing", "serde_json"]:
        libraries = list(deps.glob(f"lib{name}-*.rlib"))
        assert len(libraries) == 1, f"Expected one pinned {name} release dependency"
        command += ["--extern", f"{name}={libraries[0]}"]
    binary = args.output / "probe"
    subprocess.run(command + ["-o", str(binary)], check=True)
    subprocess.run([str(binary), str(args.output / "report.json")], check=True, timeout=15)
    paths = ["vendor/paneru/src/platform.rs", "vendor/paneru/src/platform/animation.rs"]
    (args.output / "source-hashes.json").write_text(json.dumps(
        {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in paths}, indent=2) + "\n")
    print(f"Three live Rust clock rounds passed; no callbacks after idle: {args.output}")


if __name__ == "__main__":
    main()
