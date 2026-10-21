# Ribbon engine integration

Upstream: https://github.com/karinushka/paneru
Snapshot: 12c58b2225a40e434053ea9343a41e2012466f9a (0.5.2)
License: MIT; see LICENSE.txt. All upstream notices remain in place.

The checked-in engine is built with `--no-default-features` so the product has
one TOML configuration owner and does not load arbitrary user Lua startup files.
The upstream default-feature test suite is also retained.

Local changes:

- `ribbon.rs`: exact bundle-ID allowlist, fail-closed scope, parent lifetime
  watchdog, and original-frame recovery geometry with focused tests.
- `manager/process.rs`: do not observe applications outside that scope.
- `manager/windows.rs`: enforce the same scope for direct window-creation events
  and retain original frames before tiling.
- `ecs/systems.rs`: on exit restore the original frame when available, fitting
  it onto a connected display if necessary. The upstream centering fallback
  remains for windows whose original frame could not be captured.
- `ecs/layout/parking.rs` and its layout integration: avoid parking columns
  inside adjacent displays. Keep a sliver on the owning display, prefer a free
  outer edge, and snap between parking and visible positions. Covers horizontal,
  offset and vertical arrangements with deterministic tests. The hidden-stack
  regression now checks display ownership and absence of neighbor overlap.
- `ecs/state.rs`: do not write title-bearing engine session snapshots when
  restore is disabled. The native app owns the title-free recovery journal.
- `ecs/triggers.rs`: insert a new window into its physical display's selected
  strip instead of the currently active display's strip. Includes a regression
  test for opening on a second display while the first retains focus.
- `main.rs`: start the owned-parent watchdog for a launched engine.

All engine calls use the app's distinct `PANERU_MACH_SERVICE`, config and state
directories. Ribbon does not install or invoke Paneru's launchd service.
