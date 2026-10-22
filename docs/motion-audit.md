# Ribbon motion polish — build 14

Applied better-ui and emil-design-eng to native SwiftUI/AppKit and the engine.
This is native window geometry, not a CSS/GPU transform. Keyboard opening and
selection in the overview remain immediate. The user explicitly requested smooth
actual tile movement/resizing, including shortcut-driven geometry; this takes
precedence over the skill's general recommendation to remove keyboard animation.

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| HIGH, fixed | `vendor/paneru/src/ecs/scroll.rs:104` | Old momentum could override focus, stacking, or a workspace switch | Explicit window commands cancel the fling; direct gestures cancel old strip animation | Interruptibility: the newest action controls the strip |
| MEDIUM, fixed | `vendor/paneru/src/ecs/scroll.rs:360` | Raw gestures also integrated velocity while fingers were down | Direct displacement while held, synthetic momentum after release | Functional motion follows the input |
| MEDIUM, fixed | `vendor/paneru/src/ecs/scroll.rs:387` | Small deltas lost their fractional points every frame | Preserve sub-point movement inside bounds; discard outward momentum at an edge | Slow scrolling no longer loses travel |
| MEDIUM, fixed | `vendor/paneru/src/ecs/motion.rs:20` | Integer exponential interpolation lingered and snapped its last 5 points | Sub-point, monotonic Hermite motion with carried velocity and a finite end | Continuous retargeting and clean settling without bounce or overshoot |
| MEDIUM, fixed | `native/Sources/Ribbon/Overview/OverviewController.swift:43` | Small loading panel jumped to the loaded width | Read the engine snapshot and size before ordering the panel in | No distracting keyboard entrance or resize jump |
| MEDIUM, fixed | `native/Sources/Ribbon/Overview/OverviewController.swift:232` | Confirmed drop order snapped | Native zero-bounce 200ms smooth transition only for pointer drops | Spatial continuity; engine stays the only owner of order |
| LOW, fixed | `native/Sources/Ribbon/Overview/OverviewView.swift:80` and `:182` | Little press/drag feedback | 0.96 press scale with 120ms (0.2,0,0,1) timing; dragged icon opacity 0.45; existing insertion marker | Tactile feedback with a static state cue |
| LOW, fixed | `native/Sources/Ribbon/Overview/OverviewController.swift:166` | Repeated workspace/icon lookups on view updates | Cache each bundle's native icon for the controller lifetime | Keep filesystem lookups out of drag feedback |

Geometry timing is 3.2/speed seconds, capped at 300ms; the existing speed setting
is preserved. At speed 14 this is approximately 229ms of animation time. Slow AX
round trips can extend wall-clock presentation; this is not a frame-rate promise.
Position and resize use the same interpolation. Fractional state is transient,
engine-owned, and never duplicated in Swift. No new dependencies.

Overview first render, keyboard selection/reordering, opening/closing, and theme
changes have no custom animation. Hover is an immediate semantic surface cue.
Pointer drop animation and press scale honor Reduce Motion; engine instant mode
still snaps to its target. Empty, loading and error states remain native text or
ProgressView. Cross-display drag stays disabled. Native columns are repacked
without an artificial crossing animation that would reintroduce overlapping
windows; the overview animates the icon order after engine confirmation.

Verification: `scripts/verify.sh` passed (46+472 default Rust, 39+389 shipping
Rust, 22 Swift). Native receipt: `../build/qa/motion/build14-release-5/report.json`,
14 passing checks, 308 geometry samples, 76 moving samples, 12 pt minimum/settled
gap. Native modifier-scroll, rapid reversal/resize, drag insertion, keyboard
navigation, hidden-tile focus, stack gaps, sentinel isolation and restore passed.
Light/dark PNGs in the same directory were inspected. External capture is used;
no new Screen Recording grant was given to Ribbon.

Not verified: physical second monitor (disconnected), actual finger-trackpad feel,
slowed screen-video replay, VoiceOver, and flipping the OS Reduce Motion preference.
The 30/60/120Hz interpolation checks are software tests, not hardware frame-rate
claims. No GPU-composited cross-process animation claim is made. First-render,
hover, pressed, dragging, busy, selected, loading, empty and error paths were
inspected in code; selected/drag/focus paths were exercised natively.

Approve for the inspected code and connected-display checks; the hardware coverage
limits above remain open.
