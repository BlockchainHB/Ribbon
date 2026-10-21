# Local beta verification — 20 October 2026

Ribbon 0.1.1 was built, installed and verified as a local ad-hoc signed app.
The installed optimized engine and native executable match the delivered ZIP.
The machine-readable results, artifact hashes and physical checks are in
[verification.json](verification.json).

## Automated checks

| Check | Result |
| --- | --- |
| Rust default features | 46 library + 448 binary tests passed |
| Rust shipping configuration, without Lua | 39 library + 365 binary tests passed |
| Native core | 7 tests passed |
| Rust formatting and Clippy, warnings denied | Passed |
| Swift formatting | Passed |
| Deep strict bundle signature verification | Passed |
| ZIP integrity and packaged executable hashes | Passed |

The shipping-feature tests overlap the default-feature suite. They are recorded
separately rather than added to a unique test count.

## Actual desktop checks

The installed release passed 11 single-strip checks and 11 dual-display checks
using disposable test windows and an excluded sentinel. The suite verifies:

- Exact application scope, native focus navigation, width changes and a 12 pt vertical stack gap.
- Intermediate native frames during scrolling and resizing on both monitors.
- Independent strips and shared-edge overflow on both physical monitors.
- Full width and height using the selected monitor's usable dimensions.
- Six display transfers preserving width proportions and other windows' widths.
- Opening a ninth window on the second monitor while focus starts on the first.
- Excluded-window protection, original-frame restoration and restart recovery.
- Absence of title-bearing engine session snapshots.

Hardware was macOS 27.0.1 on Apple silicon, with a 2560 × 1440 external display
beside a 1728 × 1117 built-in display. Both used 2× scale. Physical frame reports
come from the fixture's own NSWindows; engine ownership is checked separately.
Focus observations include the fixture's 100 ms reporting cadence and CLI
transport. They do not establish input-to-photon latency or language superiority.

The windowless parent-lifetime check also passed; its current polling observation
is recorded in verification.json. It is separate from the real-window graceful
pause/restoration checks.

The overlap fix was reproduced before changing product code: a full-width tile
shrinking toward its next preset covered a returning neighbor in native frame
samples. The engine now packs each animation frame from current widths and one
strip origin, and commits AX operations in shrink / ordered movement / growth
phases. The default 12 pt setting applies between tiles and at screen edges.
Reordering snaps to new slots instead of animating tiles through each other.

The installed optimized release retained a minimum 12 pt gap across 654 sampled
frames (single strip plus both physical monitors), with no observed tile overlap.
Reports are in build/qa/spacing-release-acceptance. All 22 desktop checks passed.

The motion fixture samples its own NSWindow frames on a nominal 60 Hz timer;
these are sampled geometry observations, not compositor or visual proof. Only
tiles with most of their area on the display are included. Parked edge slivers
share their parking location and are excluded; display ownership remains a
separate check. Raw motion samples and minimum gaps are retained in the QA output.
The deterministic regression checks each simulated 20 ms frame through navigation,
growth, shrink, stacking and reordering, while asserting resizing still animates.

All desktop tests used explicit demo scope. Other window managers and system
display/gesture preferences were left unchanged.

## Remaining verification

Physical unplug/reconnect, sleep/wake, clamshell transitions, portrait displays,
mixed refresh rates and trackpad feel have not been exercised. Deterministic
engine tests cover display removal/return, geometry changes and wake events.

Native UI visual capture was unavailable because the computer-use capture
service could not start its screen stream. Compilation and native window tests
passed; a visual review is not claimed. Accessibility trust was available to
the test process; fresh Finder-launch permission onboarding was not verified.

This build is not notarized and does not claim full ChainYourMac feature parity.

## Reproduce

    scripts/build-app.sh
    scripts/install.sh
    scripts/verify.sh
    python3 scripts/desktop-qa.py "$HOME/Applications/Ribbon.app" "$PWD/build/qa/fresh-run"

The desktop runner requires exactly two connected displays, a fresh output
directory and no existing Ribbon instance. It restores and closes its own test
windows, preserves failure evidence and stops its owned app process.
