# Fixed-width edge investigation

Checkpoint: **23 October 2026**. This records experiments, not a delivered jitter fix.

The requested behavior is a stable native content size while windows slide past a
monitor boundary, exposing only their intersection with their owning display.
Independent strips must remain independent. Squeezing content into the exposed
slot and hiding every partial window until its full width fits are not acceptable
substitutes.

## What causes the width churn

Ribbon's `9515ed0` added `EdgePresentation` to fit native window bodies into
exposed slots. The engine preserves logical widths, but commits smaller native
AX widths as those slots change. A full logical width does not prevent content
reflow when the native window is resized.

A temporary mocked First / Last / First navigation comparison produced 24
distinct native widths for an edge window with compact presentation, versus one
with the older presentation, on both simulated single- and dual-display layouts.
This identifies a source of content reflow. It does not measure actual application
rendering or prove that all reported jitter has the same cause.

Pinned [Paneru layout source](https://github.com/karinushka/paneru/blob/12c58b2225a40e434053ea9343a41e2012466f9a/src/ecs/layout.rs)
preserves full widths when moving windows offscreen. Its
[current documentation](https://github.com/karinushka/paneru/blob/b9785a13154e94f6a9b57e15de5287f039927e3f/README.md)
recommends vertical monitor arrangements because macOS relocates windows moved
too far onto adjacent displays. [PaperWM documents the same limitation](https://github.com/mogenson/PaperWM.spoon/blob/2a561eb63df4fd72fc2556e411bd4e1c88f57f48/README.md#limitations).
Copying their positioning policy alone does not establish correct clipping for
Ribbon's horizontal two-display setup.

## Native experiments

The desktop had an external 2560 × 1440 / 60 Hz display and a built-in
1728 × 1117 / 120 Hz display, both at 2× scale, with separate Spaces enabled.
Tests used owned disposable windows while Ribbon's engine was paused. No user
windows, display arrangement, privacy grants or system security settings changed.

| Candidate | Observed result | Limit |
| --- | --- | --- |
| Ordinary full-size offscreen movement | Content width stays fixed; macOS can adopt the window onto the adjacent display | Ownership and clipping do not remain stable |
| Atomic native Space add followed by removal of unintended membership | An 800 × 432 child window held its requested position and owner membership through 99% offscreen | Full-size external windows could shorten from 1301 to 1084 points and bounce back when corrected; not a viable general fix |
| Direct foreign window shape and compositor-origin writes | Standalone caller readback initially appeared to pass | Independent child readback invalidated those apparent passes |
| Same direct shape/move calls from signed, Accessibility-trusted Ribbon | Owned-window control succeeded; foreign-process calls returned status 1000 on both displays | Existing Accessibility access did not authorize the tested foreign-window masking route |

The last test is repeatable in the signed application through
[NativeEdgeVerification.swift](../native/Sources/Ribbon/NativeEdgeVerification.swift).
It checks a positive owned-window control, validates the child PID and window
owner connection, and compares caller-local bounds, public WindowServer bounds,
and the child process's own bounds. A successful setter return or caller-local
readback alone is insufficient evidence.

The current signed receipt is
`build/qa/native-edge-signed-20261023-c/report.json`: Accessibility trusted,
owned control confirmed, four foreign cases rejected, with five held observations
per case. Screen Recording was not granted. This rejection is a native API
result; it is not a compositor pacing assessment or a test of Codex, Claude,
Dia or T3 content under a repaired engine.

Earlier local `foreign-peek-native-shape-*` receipts have explicit independent
readback warnings. They must not be cited as working cross-process clipping.
The first signed attempt (`native-edge-signed-20261023-a`) stopped before the
control window was independently queryable and is not a completed test.

### Follow-up after the user's visual observation

The user reported seeing only a narrow pink slice at the external monitor's
right edge, without spill onto the laptop. This is positive manual evidence for
the demonstrated external peek. Several demo variants ran, so that observation
alone cannot identify which native mechanism produced it.

Fresh drawn-window controls, kept behind existing apps without activation,
compared public WindowServer bounds from both processes:

- `foreign-peek-natural-public-drawn-20261023-a`: the ordinary movement plus
  native Space-membership correction route passed six held positions across both
  monitors. An 800 × 432 window retained its full content dimensions and owner
  membership through 99% offscreen. Public bounds agreed between both processes.
- `foreign-peek-natural-fullsize-public-drawn-20261023-a`: the laptop-sized cases
  passed, but the 2548 × 1301 external window became 2548 × 1084 at 99% offscreen,
  moving down to the laptop's native top edge. Width and corrected owner Space
  stayed stable; height and vertical position did not. In this shorter sequence
  it did not bounce horizontally, unlike an earlier multi-position sequence.
- `foreign-peek-shape-public-drawn-20261023-b`: drawing the fixture did not rescue
  direct masking. The caller's apparent cropped bounds still disagreed with
  unchanged public bounds read by both processes.

The initial drawn masking attempt (`...-20261023-a`) encountered an `ENOSPC`
report-write failure and is invalid. Its receipts were preserved. Only generated
Rust release output from this investigation was cleaned before the successful
reruns; personal files and previous QA receipts were retained.

These results confirm a working smaller-window offscreen case. The unresolved
problem is preserving full content dimensions and position for larger windows
across unequal monitors, together with reliable motion, focus and restoration.

## Reproduce the permission-context check

Build with the existing Developer ID identity. Keep the installed app unchanged;
this diagnostic runs from the staged signed bundle, never starts an engine, and
exits after closing its own invisible windows. Pause Ribbon first, keep the
desktop unlocked, and connect both displays. Use a fresh output directory.

```sh
scripts/build-app.sh
APP="$(python3 -c 'import json; print(json.load(open("build/artifacts.json"))["app"])')"
open -n -g "$APP" --args --qa-native-edge "$PWD/build/qa/fresh-native-edge"
```

Inspect `report.json` after the process exits. `blocked` means the preconditions
or a query failed. `rejected` means the tested crop was not independently
confirmed; inspect the owned control before interpreting that result. Even
`confirmed` would establish geometry only, requiring separate rendered-content,
input, restoration and compositor verification before a product change.

## App-owned compositor-space candidate

A separately launched signed fixture (parent PID 1, independent WindowServer
connection) retains its original managed Space while also belonging to one
app-owned unmanaged compositor space. Translating that space and clipping it to
the owner's global viewport leaves native frame/content dimensions anchored on
the owner. The temporary space uses level 0. Managed Spaces remain unchanged.

- `foreign-peek-owned-independent-20261023-c`: external 2548 × 1301 native frame,
  2548 × 1269 content, 26-point right peek. Literal display-rectangle captures
  contain pink only in the owner slice; the neighboring display and original
  source location contain none. Native hit testing maps the visible slice to
  correct fixture-local coordinates, with no hidden input surface on the neighbor.
- `foreign-peek-owned-independent-reverse-20261023-a`: laptop 1716 × 1084 frame,
  1716 × 1052 content, 18-point left peek, no neighboring-display spill. Its
  source capture overlaps the genuine slice by 12 points, so those pixels do
  not establish a duplicate window.
- Both runs restore ordinary public window coordinates and successful normal
  desktop-independent window capture after hiding the temporary space. Cleanup
  destroys only the owned space; managed-display/Space dictionaries are unchanged.
- `foreign-peek-owned-independent-motion-20261023-b`: 50 independent observations
  through both edges, fully hidden positions, reversals and returns preserve
  exact dimensions and requested public WindowServer positions.

Capture guards require opaque fixture panels covering each sampled rectangle
and reject unrelated windows above them. The first independent run stopped on
an occluder before capture. Motion attempt `...-a` had a test-runner numeric cast
failure and is not passing evidence; the fixture's liveness guard closed it.
The corrected `...-b` passed. No privacy/security changes were made.

AX coordinates remain at the native anchor during projection. Rust normalizes
reads using a presentation offset and removes projection from fully visible
windows. A CUA click attempt during partial projection returned ScreenCaptureKit
-3811 before clicking; native hit testing is established, real interaction still
needs verification. Ordinary window capture succeeds after projection is removed.

The Rust implementation prepares hidden spaces asynchronously, preserves full widths, keeps new FFI on
the main thread, and clears resources on unmanage/removal/exit. Eight-window
integration first exposed a startup focus race in the QA driver. Waiting for
initial native geometry/focus allows activation to proceed. The next run caught
native height changes: inactive strips started at the unpadded Y origin, letting
AppKit shorten their bodies before focus restored them. The candidate now anchors
rows to the final usable top and clips to the physical usable viewport. That
correction passed the integrated native checks.

`build/qa/fixed-content-engine-20261023-i/report.json` records **21 passing native
checks** against the signed diagnostic engine: eight fixture windows across both
displays, native modifier scrolling, interrupted width changes without resizing
neighbors, three pair ratios, pair reorder, hidden-pair application activation,
independent public WindowServer positions/full client sizes, excluded sentinel,
exact original-frame restoration, and start/pause/start. Earlier `...-a` through
`...-h` failures are retained, including startup/setup issues and the vertical
anchor defect. Geometry readback uses actual full client sizes because native
constraints need not accept every requested logical point.

The independently launched live WebKit runs
`foreign-peek-owned-web-motion-20261023-a` and
`foreign-peek-owned-web-reverse-20261023-a` passed 50 observations each. During
projection motion their JavaScript viewport remained 2548 × 1269 and 1716 × 1052,
respectively, while animation frames advanced and resize-event counts stayed at
one. This verifies a live browser fixture, not the named Electron/browser apps.

## Delivery state

The source now selects fixed-content projection by default on macOS 26+ when
the required runtime symbols and Objective-C methods exist. Older/unsupported
systems retain compatibility presentation. `RIBBON_NATIVE_PROJECTION=0` selects
that compatibility path; `=1` requires projection and fails if unavailable, so QA
cannot silently pass against a fallback. Native fullscreen strips retain native
presentation and retire existing compositor handles; mocked regressions cover
fullscreen cleanup and native Space suspension/resumption.

The normal signed build and exact-build native confirmation are being prepared.
Direct Codex/Claude/Dia/T3 interaction, physical fullscreen/Space transitions,
mixed-scale/portrait topology and 120 Hz compositor delivery remain unverified.
No public release or merge is authorized by this local fix.

`scripts/verify.sh` passed after the source fix: Rust formatting and
Clippy, 510/427 engine tests and 46/39 library tests in the two overlapping
feature suites, Swift formatting, 26 Swift tests, and staged configuration and
signature checks. `scripts/build-app.sh` produced and verified the signed staged
diagnostic bundle used for the native receipt. Mocked tests, native frame tests,
literal display pixels and compositor delivery are separate forms of evidence.
