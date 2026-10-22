# Directional navigation and visible neighbors

The reported leftward blank area came from presentation at a physical monitor
seam. An unfocused, full-width neighbor was parked in its entirety as soon as
its frame crossed the seam. The opposite desktop edge did not trigger that
protection, which made the behavior look direction dependent.

Ribbon now fits a partially visible window's native body into the exposed slot
on either edge. The logical strip width, width preset, and preferred width stay
intact. Focusing that window brings its full width back into view. Windows with
less than 200 points exposed remain parked. If an app refuses the requested
width, Ribbon learns its minimum and parks it before moving the oversized body
onto another display. The minimum is a per-window session hint.

Two motion costs were also removed. Native focus/raise now follows the first
geometry commit instead of blocking the beginning of the movement. Multiple
requests in a frame are coalesced, and focus verification starts after the native
request. Move/resize echoes from an animating strip no longer trigger redundant
AX frame reads or overwrite the layout. Manual geometry changes at rest still
work. Native shrinking and growth retain parallel execution; position commits
retain their existing ordering.

Exit restoration also runs in Bevy's final schedule, after native animation and
focus writes. This prevents the last animation tick from re-parking a window
just restored during an immediate focus-and-pause operation.

The animation curve and duration have not been shortened to conceal latency.

## Design review

| Severity | Location | Before | After | Why |
| --- | --- | --- | --- | --- |
| HIGH | `vendor/paneru/src/ecs/layout/parking.rs` | A partially visible neighbor disappeared completely at the interior seam. | Fit native presentation into its exposed slot; retain logical width and safe minimum-size fallback. | Spatial continuity: a visible slot should contain its window in either direction. |
| HIGH | `vendor/paneru/src/ecs.rs` | An immediate exit could restore windows before the final animation wrote their frames again. | Restore native frames in the final schedule after movement and focus commits. | Reliable state changes: pause must leave windows restored. |
| MEDIUM | `vendor/paneru/src/ecs/focus.rs` | A synchronous AX raise preceded all movement. | Commit the first geometry frame before the coalesced native focus request. | Immediate feedback: application responsiveness should not delay the beginning of navigation. |
| MEDIUM | `vendor/paneru/src/ecs/systems.rs` | Strip animation echoes were handled as external geometry changes. | Ignore echoes while the owning strip moves, and keep manual changes at rest. | Interruptible, consistent motion: one owner drives geometry during a transition. |

Scope verdict: **Approve** for these repaired paths. This is not a visual
audit of every app screen or a guarantee about other applications' redraw speed.

## Verification

`scripts/verify.sh` passes formatting, strict Clippy, both Rust feature builds,
Swift formatting, 26 Swift tests, configuration validation and signature checks.
The engine suites contain 490 default-feature and 407 no-default-feature tests,
plus 46 and 39 library tests respectively. New regressions cover symmetric edge
presentation, preservation of logical widths, rejected native minimum sizes and
external focus recovery, native geometry echoes during motion versus manual
changes at rest, and restoration after an in-flight focus/animation frame. Existing grouping, stacking, display transfer and motion tests
remain included.

Physical checks use disposable Ribbon Demo windows and an exact engine allowlist
of `dev.ribbon.fixture`. Personal applications are outside the automated engine
scope. Both the 2560 × 1440 external display and 1728 × 1117 laptop display are
connected, at 2× backing scale. The fixture samples real AppKit frames at 60 Hz;
these observations do not measure compositor/GPU frame delivery. Screenshots and
raw observations stay in ignored `build/qa/navigation-profile/` directories.

The baseline command-path sample on the external display measured median first
movement at 25.4 ms rightward and 42.8 ms leftward. The initial repaired sample
measured 23.0 ms rightward and 19.7 ms leftward. The largest interval between
observed native geometry changes fell from 41.5 ms to 20.6 ms for leftward moves.
These are six moves in each direction, not a performance claim for every client
application. Raw samples: `baseline-ipc/` and `after-1/`.

`keyboard-2/` additionally verifies 24 injected Control–Option arrow changes
through the native event tap, across both physical monitors. Its recorded frame
samples contain no native body on the wrong display. Centered two-thirds tiles
retain a visible neighboring tile in the screenshots. Input was sent by the
approved native Swift interpreter; a separately compiled helper and generic
System Events modifier injection did not dispatch those shortcuts and were not
counted as passing checks.


The intermediate verified engine SHA-256 is
`7e507efe017b676c4af502c922815101bbe70be8f7cc72a2e0ff8fe97d100185`.
`final-ipc-2/` and `final-keyboard-2/` each pass 14 physical checks: eight native
external activations reveal their tile on its original monitor, centered tiles
retain a neighbor on each display, recorded navigation frames have no significant
body intersection with the wrong display, 24 direction changes move windows,
and every original fixture frame is restored even when stopping immediately
after focus. The keyboard run additionally requires the actual focused native
window to change after every injected chord. This verifies the activation route
used when another app focuses a window; it does not exercise Raycast itself.

Final IPC samples on the large display measure median first movement at 35.4 ms
rightward and 29.4 ms leftward, with a worst observed leftward geometry interval
of 23.5 ms (baseline 41.5 ms). Timings varied between runs, including concurrent
build load; the earlier 19.7 ms leftward sample is not presented as a guaranteed
latency. The 60 Hz fixture sampler does not establish 120 Hz compositor delivery
or smooth redraw by heavyweight third-party applications.

A failed immediate-exit run (`final-ipc/`) was retained and led to the final
schedule fix. Initial test harness runs did not qualify as passing verification.

The complete native app lifecycle suite also passes on the installed binary:
`build/qa/navigation-startup-delivery/summary.json`, nine checks in each of the
single- and dual-display runs. These cover the sidebar window, native status
menu, switch start/pause/restart, maximized tile activation on its owner, excluded
sentinel isolation, and original-frame restoration. Earlier dual runs could not
activate the restart switch after restoration; the external test driver now
explicitly raises General and allows its activation to settle before measuring
the live AX hit target. The product's switch implementation was not changed.

The final width-ratio regression also verifies that deriving an edge-only native
size leaves the stored ratio untouched. Full final code verification:
`build/motion-delivery-checks.log`. The final installed engine SHA-256 is
`b338c886569f347da02a5713bdd69bc11e88e413b2d996792d3056d5e7ae7c80`.
`delivery-keyboard/` passes the same 14 physical checks, including 24 injected
Control–Option arrow changes and original-frame recovery on both monitors. The public download
archive on GitHub was not replaced by these local installation checks.
