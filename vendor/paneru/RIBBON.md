# Ribbon engine integration

Upstream: https://github.com/karinushka/paneru
Snapshot: 12c58b2225a40e434053ea9343a41e2012466f9a (0.5.2)
License: MIT; see LICENSE.txt. All upstream notices remain in place.

The checked-in engine is built with `--no-default-features` so the product has
one TOML configuration owner and does not load arbitrary user Lua startup files.
The upstream default-feature test suite is also retained.

Local changes:

- Oversized-minimum focus: a safely owner-anchored projected window can receive
  native focus after its strip and native geometry settle, even when its minimum
  size cannot fit inside the viewport. Ordinary partial/parked/pending windows
  still defer focus. Includes a regression and opt-in oversized native fixtures.

- Fixed-content presentation on supported macOS 26+ runtimes:
  `manager/projection.rs` owns main-thread compositor handles and a mockable
  native boundary. `ecs/projection.rs` controls asynchronous preparation,
  active-native-Space visibility, projection/reveal and resource cleanup.
  `Window` normalizes AX coordinates with a presentation offset while its
  underlying native frame stays on the owning display. Full logical bounds
  bypass edge-width fitting; focus waits for ordinary coordinates on reveal.
  Native writes retain departure/leader/reveal ordering. Native fullscreen
  strips retire projection and retain native presentation. Unsupported runtimes
  keep compatibility; `RIBBON_NATIVE_PROJECTION=0` explicitly selects it, while
  `=1` requires the new backend. See
  `../../docs/fixed-width-edge-investigation.md` for independent pixel evidence
  and remaining limitations. No dependency or upstream pin changes.

- Startup visibility: fit newly adopted oversized tiled columns to their own
  monitor's usable width when compact parking is enabled. Native maximized
  windows otherwise exceed the viewport after padding and can be parked at
  the neighboring screen's corner even when focused. Seam protection keeps a
  focused oversized tile reachable if the application refuses to fit; hidden
  and inactive tiles still park normally. Regression coverage includes
  differently sized adjacent displays, external focus, and explicit oversized
  windows. The native recovery journal retains the original pre-session size.

- `ribbon.rs`: explicit all-app policy with exact exclusions, legacy/QA bundle-ID allowlists,
  fail-closed invalid policies, parent lifetime
  watchdog, and original-frame recovery geometry with focused tests.
- `manager/process.rs`: do not observe applications outside that scope.
- `manager/windows.rs`: enforce the same scope for direct window-creation events
  and retain original frames before tiling.
- `ecs/systems.rs`: on exit restore the original frame when available, fitting
  it onto a connected display if necessary. The upstream centering fallback
  remains for windows whose original frame could not be captured. Commit AX
  frame changes in shrink / ordered movement / growth phases so a neighbor's
  old frame is released before another tile moves into its place.
- `ecs/layout/parking.rs` and its layout integration: avoid parking columns
  inside adjacent displays. Keep a sliver on the owning display, prefer a free
  outer edge, and snap between parking and visible positions. Covers horizontal,
  offset and vertical arrangements with deterministic tests. The hidden-stack
  regression now checks display ownership and absence of neighbor overlap.
- `ecs.rs` and `ecs/layout.rs`: advance strip and resize animations before
  packing physical frames from current sizes. All tiles follow one strip origin;
  they no longer ease independently toward future slots. Keep the existing target
  layout for scroll decisions. Reordering and hidden-strip parking snap to avoid
  sliding tiles through each other. Geometry work remains change-driven. Per-frame
  regression checks cover navigation, growth, shrink, stacking and reordering.
- `ecs/focus.rs`: project the mouse target from the strip destination consistently
  now that member windows no longer carry their own animation targets.
- `ecs/state.rs`: do not write title-bearing engine session snapshots when
  restore is disabled. The native app owns the title-free recovery journal.
- `ecs/triggers.rs`: insert a new window into its physical display's selected
  strip instead of the currently active display's strip. Includes a regression
  test for opening on a second display while the first retains focus.
- `main.rs`: start the owned-parent watchdog for a launched engine.
- `config.rs`: recognize explicit `keycode:0` through `keycode:126` bindings
  before keyboard-layout translation. Ribbon's local recorder validates and
  persists physical keys; the engine remains the only global shortcut owner.
  A regression checks numeric bindings and invalid ranges against
  a different virtual keyboard map. Existing upstream key names still work.

All engine calls use the app's distinct `PANERU_MACH_SERVICE`, config and state
directories. Ribbon does not install or invoke Paneru's launchd service.

Automatic management is enabled only by `RIBBON_MANAGEMENT_SCOPE=all`. Missing
policy remains fixture-only; malformed policies/exclusions manage nothing. The
app always sends explicit selected fixture scope during automated QA, including
the watchdog probe. Newly launched normal applications are admitted by the same
engine process/window boundary; Ribbon and System Settings stay protected.

## Compact parking (Ribbon build 9)

`compact_parking = true` is generated by Ribbon; upstream configurations retain
legacy side slivers by default. Lua's configuration readout includes the option.

- `ecs/layout/parking.rs`, `ecs/layout.rs`: derive compact right-corner presentation
  from the full display arrangement. Prefer the owner, otherwise use an outer
  monitor edge. Guard interior seams before a partial tile body can cross them.
  Keep logical bounds and strip ownership independent of native parking frames.
  The compatibility sliver algorithm is extracted without changing its policy.
- `ecs/systems.rs`, `ecs/focus.rs`: cap native presentation to the parking host
  before moving it, avoiding a native fit-to-display flash. Skip native resizing
  while parked, restore intended dimensions on reveal, and exclude parking echoes
  and focus-time native size corrections from canonical bounds. Use the existing
  bounded position verifier and log requested/observed parking frames during QA.
- `manager/windows.rs`: check AX position setter results before acknowledging them.
- `ecs/params.rs`, `ecs/state.rs`: query parked state; report hidden tiles as hidden
  and retain their logical display owner in Ribbon's compact mode.
- `ecs/workspace.rs`, `ecs/display.rs`, `ecs/triggers.rs`: native Space reassignment
  caused by parking must not move a tile between connected displays or remove its
  membership during Mission Control. Explicit engine display transfers still own
  that operation. Disconnected-display reconciliation remains separate.
- `commands.rs`: display transfers use the final resize target rather than an
  intermediate animated width when calculating the destination width ratio.
- Tests cover seam rejection, stable placement across display order/negative
  coordinates, constrained native sizes followed by external reveal, and native
  parking Space activation without logical tile migration.

Hardware receipts, failures and unperformed topology checks are recorded in
`docs/verification.md` in the application root. All automated desktop runs retain
an explicit disposable-fixture allowlist. No real-user all-app engine is run by QA.

## Optional fill width policy (Ribbon build 10)

`fill_available_width` defaults false in upstream and Ribbon. The native Layout
picker persists Preserve widths / Fill available space and generates this one
engine option; Swift owns no layout geometry.

- `ecs/layout/width_policy.rs`: derive per-strip proportional expansion only when
  preferred column widths fit the Dock/padding-adjusted viewport. Integer
  apportionment fills the remaining points exactly. Keep preferred widths separate
  from applied animated widths; overflow and disabling fill restore preferences.
  Stacks/native tabs remain a single column. Floating/fullscreen members leave
  the policy, and display changes scale preferences to the destination viewport.
- `ecs/layout.rs`: run the width policy before logical slot packing. Fitting fill
  strips align with the viewport even if focus centering is enabled; overflowing
  strips retain normal centering and scrolling.
- `ecs/params.rs`, `commands.rs`: width presets, full-width restoration and display
  transfers use preferred widths when fill is active, avoiding accumulated growth.
- `config.rs`, `lua/api.rs`: parse and expose the opt-in option consistently.
- Regression tests cover mode round trips, window admission/removal, overflow,
  independent display sizes, resize intent, focus centering and full-width toggles.

## Icon overview and flush vertical edges (Ribbon build 13)

- `commands/overview.rs` adds managed-window focus by id and column insertion
  within one selected strip. Unknown, floating, cross-strip and stale ids are
  ignored. Reordering preserves intervening columns and stack/tab membership.
- The engine-owned overview hotkey posts a payload-free distributed notification
  scoped to its owning GUI PID; the native app owns only its transient panel.
- `overview-state` exposes the existing WindowSet query as JSON; its selected
  strip flags now include the selected workspace on the other monitor. The GUI
  displays immutable responses and waits for confirmed order after each drop.
- Signed top/bottom padding offsets cancel per-window padding at outer vertical
  edges while preserving the normal internal stack gap. Existing positive padding
  and legacy option values remain supported; Ribbon generates the compensation.
- Tests exercise insertion in both directions, stale/cross-display/floating
  rejection, stack preservation and targeted focus. Native fixture QA is recorded
  separately in docs/verification.md.


## Continuous native motion (Ribbon build 14)

- `ecs/motion.rs`, `ecs/systems.rs`: shared sub-point Hermite interpolation for
  movement and resizing, finishing in 3.2/speed seconds (maximum 300ms).
  Retarget from the current sample and carry a monotonic, bounded tangent.
  Native geometry remains integer; intermediate precision stays in the engine.
  Idle wakeup is not charged to a new transition. Instant/Reduce Motion speeds
  retain one-frame assignment. Animator-local caches retain only active entities.
- `ecs/scroll.rs`: while fingers are down, apply the input displacement once,
  without also integrating synthetic velocity. Retain fractional scroll points
  inside the viewport and discard outward momentum at a clamped edge.
  Momentum cutoff uses points/second, independent of the frame interval.
  Explicit window commands cancel a fling; a new gesture cancels an old
  animated strip correction so input never fights the previous operation.
- Tests cover 30/60/120Hz settling, interruption/reversal, one-point travel,
  idle wakeup, instant mode, direct gesture tracking and fractional accumulation.
  Native fixture motion/overview receipts are recorded separately.


## Side-by-side pairs (Ribbon build 16)

- `ecs/layout/pairing.rs`: non-nested pairs of adjacent columns. Each side is
  identified by all generation-tagged window entities, refreshed at topology
  edits; neither column indexes, app identity, nor the current stack/tab leader
  owns membership. Closing a leader preserves surviving-column membership.
- `LayoutStrip` insertion, removal, extraction, append and reorder keep pairs
  contiguous. Stack/unstack, floating and fullscreen explicitly detach affected
  columns. Whole-pair display transfer preserves stacks/tabs and updates active
  display/workspace state. Fitted pairs recompute for the destination viewport.
- Shared reveal bounds cover both members if their combined width fits; an
  oversized pair falls back to revealing the focused member. Keyboard focus,
  native activation, overview focus and reorder use this same rule. Explicit
  centering targets the pair span; internal focus leaves a visible pair still.
- `commands/pairing.rs`, command vocabulary/argv: directional join, ungroup,
  window-addressed equivalents and exact two-column arrangements. Pairing
  preserves widths. Independent arrangements do not create group membership.
  All addressed columns must be managed. Fractions are finite and range-checked.
- Fitting splits logical slot width exactly once (slots already include window
  padding). Issue once per explicit fit or viewport change; native width readback
  remains authoritative, without repeatedly forcing a rejected client size.
  Independent resizing clears the stored fit intent. Existing fill policy and
  ordinary width cycling remain available.
- WindowSet adds optional `pair_id` for read-only native overview rendering.
  Existing snapshots decode without it. Swift sends commands and never owns the
  column membership/order. Upstream source and dependencies remain pinned.
- Membership is session-local. Ribbon's existing frame-recovery journal restores
  native frames, not pairing by app name; a fresh engine session safely starts
  unpaired. No broad desktop admission or recovery scope changes were introduced.
- Eleven command/layout regression tests cover grouping, exact ratios, activation,
  block moves, stack leader removal, insertion, ungroup geometry, rejected-width
  readback, fill interaction, geometry changes and simulated dual-display transfer.
  Real-desktop verification is recorded separately in docs/pairing.md.

## Native edge presentation and directional motion

- `ecs/layout/parking.rs`: constrain a partially visible native window to its
  exposed horizontal slot on either edge. `EdgePresentation` is presentation
  only; full `Bounds`, ratios and preferred widths remain owned by the strip.
  Tiny slots stay parked. A refused AX shrink records a session-local minimum
  width and parks before repositioning, preserving adjacent-display protection.
- `ecs/systems.rs`: commit the derived native size without changing logical
  packing; restore full native size on reveal. Ignore own move/resize echoes
  while the owning strip animates, and ignore clipped/parked presentation sizes.
  Preserve manual geometry reads at rest and parallel native size commits.
- `ecs/focus.rs`: coalesce native focus requests and issue them after geometry
  commits, before mouse-follow behavior. Start rejection timing at the actual
  native request. External activation still follows the existing focus/reveal
  route; clipping does not become a new layout or focus authority.
- Regression tests exercise both edges, preserved logical widths, minimum-size
  fallback/recovery and geometry echo handling. Physical dual-monitor keyboard,
  frame sampling, focus and recovery evidence is in docs/navigation-motion.md.
- `ecs.rs`: restore native original frames in `Last`, after every geometry and
  focus commit, so an immediate exit cannot be overwritten by its final frame.
  A regression covers exit while strip movement is still active.

## Measured native geometry performance

- `manager/frame.rs` batches position/size AX reads, validates returned geometry,
  and retains a per-window compatibility fallback. Unsupported results are
  cached; transient failures are retried. Native resize validation is retained.
- `ecs/motion.rs` samples intermediate geometry at the owning display interval,
  resolving canonical strip membership. Targets/endpoints bypass sampling;
  continuing transitions consume actual elapsed time after slow native calls.
  `manager/display.rs` caches reported refresh timing with existing topology.
  No new event-loop sleep, compositor API, command queue or Swift layout state.
- `ecs/systems.rs` avoids duplicate parking readback when verification is already
  scheduled. Keeps minimum-size fallback, ordered positions and parallel sizes.
- `performance.rs` adds opt-in bounded aggregate histograms, with no title/content
  collection or per-frame disk writes. Disabled profiling registers no systems.
  Reproducible isolated hardware measurements and limits are documented in
  `docs/engine-performance.md`; upstream source/dependencies remain pinned.
- A one-commit `NativeReveal` fence parks outgoing bodies first, moves visible
  leaders next, then reveals parked neighbors. Artificial parking coordinates
  must not put an incoming left tile before the visible tile moving aside.
  An ordered native-write regression covers the one-frame overlap found during
  interrupted dual-display resizing.
- Mid-sample retargeting starts at the last emitted native geometry while
  carrying bounded velocity. A 60 Hz reversal regression prevents jumping to
  an uncommitted curve point before moving in the new direction.
- `ecs/focus.rs` retains coalesced native focus while a tile is compact-parked,
  preventing activation of the parking monitor's last key window. Geometry still
  advances immediately; rejection checks exclude pending requests and the timer
  starts on actual focus dispatch. A regression covers parked/revealed dispatch.
- Profiling-only `RIBBON_PERF_BASELINE=1` selects uncapped output/sequential
  frame queries for controlled A/B runs in one binary, retaining all correctness
  guards. It has no effect unless the profile output is explicitly enabled.

- Returning edge presentations no longer wait for a fixed 200-point slot. The
  first native attempt uses a positive content width including padding; accepted
  minimum-size readback still parks rejected bodies before any seam crossing.
  Returning tiles restore exposed native size directly after their ordered move,
  before verification or unrelated growth work can expose the parking size.
