# Ribbon

A native scrolling-window beta for Apple silicon Macs. SwiftUI/AppKit controls a
pinned Paneru Rust engine. The app starts paused and defaults to managing only
its disposable demo windows.

## Build and install

Requires Xcode command-line tools, Python 3 and Rust 1.95.0 (pinned in
rust-toolchain.toml). Rust's default toolchain is not changed.

    scripts/build-app.sh
    scripts/install.sh

For faster engine iteration, scripts/build-app.sh --debug-engine creates a
separate debug bundle and archive; installation continues to use the release.

The deliverable is build/Ribbon-beta.zip; installation uses
~/Applications/Ribbon.app. The local build is ad-hoc signed, verified and not
notarized. The physical signed app and Swift build products use Library/Caches
because Documents/iCloud rewrites bundle metadata after signing. The exact
staged app path is recorded in build/artifacts.json.

Launch Ribbon, enable it in macOS Accessibility settings, and check access in
the app. Demo mode manages only Ribbon Demo. Selected-app mode manages exactly
the applications explicitly selected. Scope changes require pausing first.

Control–Option + arrows navigates; add Shift to reorder. R cycles widths, F
toggles full width, C centers, ] stacks, Shift–] unstacks, and Q stops the engine.
Control–Option + horizontal scroll slides the strip.
Each display has an independent strip. Control–Option–N transfers the focused
window and preserves its width proportion on the destination screen.

Window spacing defaults to 12 pt between tiles and at screen edges. The setting
applies horizontally and vertically; scrolling and resizing keep a shared strip
geometry. Reordering snaps to the new order instead of crossing other tiles.

## Verification

Results for the installed release: [docs/verification.md](docs/verification.md).

    scripts/verify.sh
    python3 scripts/watchdog-check.py "$HOME/Applications/Ribbon.app"
    python3 scripts/desktop-qa.py "$HOME/Applications/Ribbon.app" "$PWD/build/qa/fresh-run"

The isolated desktop suite runs by launching the installed app with
--qa-output /absolute/path/to/report.json. It requires Accessibility access,
creates disposable fixture and excluded-sentinel windows, checks navigation,
widths, stacking and original-frame restoration, then closes those test apps.
Use a fresh output directory and quit any existing Ribbon instance first.
Its focus samples include fixture-reporting delay and are not input-to-photon
benchmarks.
Add --qa-dual for the eight-window physical two-monitor suite. The behavior
contract and remaining hardware matrix are in [docs/dual-monitor.md](docs/dual-monitor.md).

Settings and a private recovery journal live in
~/Library/Application Support/Ribbon. Original frames are restored when
possible; newly created windows without a pre-session record are fitted back
onto a visible display. Missing windows are ignored, failed recovery remains
available, and no document titles or window contents are persisted.

## Source ownership

Engine changes and provenance: [vendor/paneru/RIBBON.md](vendor/paneru/RIBBON.md).
Scope and acceptance: [docs/acceptance.md](docs/acceptance.md).
Engine decision: [docs/engine-decision.md](docs/engine-decision.md).
The research report is in research/window-manager-study.html.

Public distribution, auto-updates, startup at login, pinning, a complete shortcut
recorder and full ChainYourMac parity are outside this first beta. Physical
multi-display, trackpad feel and sleep/wake results must be recorded separately.
