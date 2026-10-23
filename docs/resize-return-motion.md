# Resize-triggered returns — 22 October 2026

Returning tiles now enter as space becomes available, without Ribbon's fixed
200-point reveal gate. Native app minimum sizes remain authoritative. This is
presentation logic in the engine; logical widths, strip ownership and grouping
remain unchanged. The existing interruptible curve and display cadence are
preserved, with no added delay, bounce or decorative entrance.

## Motion review

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| MEDIUM | `vendor/paneru/src/ecs/layout/parking.rs:31` | Wait for a 200-point exposed slot, then show the whole slot at once | Allow a positive native content width, including padding; retain learned app minimum widths | Spatial continuity: avoid an artificial pause followed by a wide pop |
| MEDIUM | `vendor/paneru/src/ecs/systems.rs:1209` | Move the parked frame onscreen; restore its size after other positions and verification | Restore exposed size directly after the ordered reveal move | Coordinated geometry: reduce the interval where a parking monitor's shorter frame can appear |

Departing windows still park before visible leaders move, and returning windows
move last. Shrinking still validates accepted size before movement, so a rejected
minimum cannot expose an oversized body across a monitor seam. Native focus waits
until the target is no longer compact-parked. The focused window and its neighbors
continue to use one canonical layout rather than independently eased positions.

## Verification

`scripts/verify.sh` passed: 502/419 engine tests, 46/39 library tests and 26 Swift
tests, plus formatting, strict Clippy, generated configuration and signatures.
Regressions cover sub-200-point exposure, respected learned minimums, reveal write
ordering and immediate restoration of a taller target after the move.

Physical checks on the installed signed bundle:

- `build/qa/resize-return-signed-final/`: 14 checks. Two resize-triggered returns
  on each side, centering, retained visible neighbors, no sampled overlaps, eight
  external hidden-window activations and exact original-frame restoration.
- `build/qa/resize-return-keyboard-final/`: 13 checks, including 12 actual native
  Control–Option arrow presses, both navigation directions, eight external
  activations, sampled separation and exact restoration.
- `build/qa/resize-return-pairing-final/report.json`: 14 checks covering pair
  proportions, stationary internal focus, block reorder, hidden-member activation,
  native overview Ungroup, independent arrangements, exclusions and lifecycle.
  Light/dark overview captures were inspected.
- `build/resize-return-final-verify.log` records the full code checks.

The final engine SHA-256 in all three receipts matches the installed bundle:
`c646552ae49371f05f6e2315f994e656f91c3c29374c668849249ab1afa4bb18`.
The native app's automated external-input flag now consistently uses its external
switch driver. Previously the pairing run used an internal synthetic click and
failed before starting the engine; that failed receipt is retained separately.
The fixture driver also explicitly foregrounds the fixture through LaunchServices
before activation assertions and preserves failure state before recovery.

Only the built-in 1728 × 1117 display was connected after the user moved locations.
**Not verified:** the new reveal changes on two physical monitors, compositor
frame pacing, busy third-party redraw, and slow-motion screen-video review.
The preceding performance checkpoint passed separate dual-display suites; those
results are not claimed as hardware verification of this follow-up. Native frame
sampling here runs at 60 Hz and does not establish 120 Hz compositor delivery.
All automated management remained restricted to disposable fixtures. Normal
Ribbon was reopened paused after verification.

Earlier interrupted/locked-screen and foreground-activation failures remain under
separate `build/qa/resize-return-*` paths and are not counted as passing.

Reproduce with Ribbon paused and a fresh output directory:

```sh
python3 scripts/qa-performance.py "$PWD/build/qa/fresh-resize-return" \
  "$HOME/Applications/Ribbon.app" --resize-return

RIBBON_QA_KEYBOARD=1 python3 scripts/qa-performance.py \
  "$PWD/build/qa/fresh-return-keyboard" "$HOME/Applications/Ribbon.app"
```

Approve for the inspected code and single-display fixture coverage; the unverified
hardware/rendering cases above remain outside this approval.
