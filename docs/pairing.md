# Window pairing

Ribbon 0.2.0 build 16 adds side-by-side pairs without replacing the scrolling
layout engine. The source comparison and rationale are in
[the grouping study](../research/window-grouping/README.md).

## Using it

Press Control–Option–Tab to open Arrange Windows. Right-click a window icon:

- **Pair with Left / Pair with Right** links two neighboring columns and keeps
  their existing widths. A small blue link badge marks each member.
- **Arrange → ½–½, ⅓–⅔, or ⅔–⅓** fits the two columns to the usable screen.
  The fraction describes the left window's share. This also works on two
  independent neighboring columns without linking them.
- **Ungroup** removes the link and leaves the current sizes and positions intact.

Drag either member or use the normal move shortcuts to move both together.
Shift–Left/Right in the overview also moves the whole pair. Clicking/focusing
either member selects that window; it does not center that member separately.
Activating a hidden member through the OS reveals the pair if it fits.
Control–Option–N transfers both to the next display and follows them. The Send to
Next Display action leaves focus on a source neighbor when one exists.

Settings → Shortcuts contains Pair with Left, Pair with Right, Ungroup Pair, and
the three arrangement actions. No new default shortcuts override existing keys.
Pause Ribbon before recording assignments, as with the other shortcuts.

## Boundaries

- Pairs have exactly two columns and cannot nest. Ungroup before pairing with a
  different neighbor. Existing vertical stacks/native tabs remain inside their
  original columns; pairing does not change which stack members are visible.
- Explicit stack/unstack, floating, and native fullscreen transitions detach the
  affected column. Closing a stack/tab leader keeps the pair if its column
  survives; closing the final member dissolves the pair.
- New windows insert outside the pair. Reorder drops before/after another pair
  never split that target pair.
- Native minimum sizes win. If both columns cannot fit, Ribbon keeps the link
  and reveals the focused member rather than repeatedly forcing a rejected size.
  Changing an individual width clears that pair's stored fitting ratio.
- Membership is session-local. Pausing restores original native frames through
  the existing recovery journal; a new engine session starts unpaired. Recovery
  does not infer groups from app names or broaden management scope.

## Ownership

The Rust `LayoutStrip` owns pairing, order, fitting and visibility. Each column's
full set of generation-tagged window entities witnesses its identity. Mutation
cleanup refreshes those witnesses, so deleting the first stack/tab member cannot
silently reassign the pair to the next column. No stored array index or app ID
defines membership. The Swift overview reads optional engine `pair_id` values
and sends window-addressed commands; it never predicts/persists membership.

Logical column widths already include per-window padding. Pair fitting splits
the available logical width once and consumes the rounding remainder in the
second column. The existing native geometry/readback pipeline owns accepted
sizes. Fitting is requested only on explicit action or a viewport-width change.

## Verification

Engine regression coverage includes:

- width preservation on join; exact thirds and halves; rounding remainder;
- stationary internal focus; native-focus-event reveal of a hidden member;
- block reorder through either member and preservation of another target pair;
- ungroup without movement; independent arrangement without linking;
- insertion around a pair; surviving stack leader deletion; final-column removal;
- floating/stale command rejection and oversized-pair focus fallback;
- accepted larger native width without repeated fitting;
- compatibility with Fill available space and explicit individual resizing;
- viewport geometry changes and transfer/follow/send between simulated monitors
  with different dimensions.

Eleven pairing engine tests passed. The complete `scripts/verify.sh` run passed:
46+483 default Rust tests, 39+400 shipping Rust tests, and 26 Swift tests.
[The real-desktop receipt](../build/qa/pairing/build16-release-2/report.json)
contains 14 passing checks. Its exact installed engine hash is recorded with
that receipt. Native light/dark captures were visually inspected.

Native receipt and current complete-check totals are recorded in
[verification.md](verification.md) and [verification.json](verification.json).
Desktop QA uses only allowlisted disposable fixtures and an excluded sentinel.
It exercises actual native frames, app activation, the overview menu, and light
and dark captures. It is distinct from the mocked dual-display engine tests.

Only the built-in 1728 × 1117 logical-point Retina display was connected for this
run. The user explicitly chose one-display verification. Physical second-monitor
transfer, mixed-scale behavior, disconnect/reconnect, and second-monitor edge
flashes remain **not verified for pairing**. Actual Raycast Quicklink UI execution
is also separate from the verified native application-activation route.
