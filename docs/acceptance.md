# Ribbon local beta

Working title: Ribbon. A native scrolling window manager, initially for Apple
silicon running macOS 15 or later. Initial verification hardware is macOS 27.

## First deliverable

An installable .app with a SwiftUI settings window, menu bar controls, a bundled
Rust engine, an included disposable test-window app, keyboard navigation,
modifier scrolling, width presets, stacks and safe pause/quit behavior.

The app starts stopped. When enabled, it manages normal open applications,
including newly launched apps, with optional exclusions in Excluded Apps.
The engine enforces the policy, including recovery. Legacy selected-app policies
remain restricted when read directly by the engine; the native app migrates old
settings to the automatic policy. Missing or invalid engine scope fails closed.
QA always supplies an explicit fixture-only allowlist. Ribbon, System Settings
and excluded applications remain outside management.

Pause asks the engine to quit gracefully, waits for completion and restores the
saved pre-session frames of the scoped windows where AX accepts the request.
The recovery journal remains available after an interrupted session. A running
engine exits if its app parent disappears. Start/stop requests are serialized;
unexpected exits are visible and do not silently restart window management.

## Ownership

- Paneru fork: layout, focus, keyboard input, gestures and Mac window events.
- Native controller: settings, scope, permission guidance, owned child processes,
  recovery journal and lifecycle status. It does not calculate strip geometry.
- Fixture app: disposable windows and actual-frame reports for isolated QA.

Only configuration and recovery metadata persist locally. A recovery record may
include application IDs, PIDs, window identifiers and frames; do not persist
document titles or window contents. No accounts, analytics or network service.

## Verification

Require passing upstream deterministic tests plus focused tests for added scope,
parent lifecycle, configuration, command execution and recovery behavior. Verify
with real fixture windows: startup, focus navigation, width preservation, rapid
commands, stacking, pause restoration, restart and parent termination. Sample
actual frames during scrolling and resizing on each monitor to catch temporary
overlap; check the configured gap both between columns and in stacks. Reordering
must place tiles in their new slots without animating through neighboring tiles.

Record AX trust, actual desktop results and performance observations separately.
Dual-display behavior is defined in [dual-monitor.md](dual-monitor.md) and is
part of the first beta. Record the physical suite separately from deterministic
display lifecycle tests. Mixed-refresh-rate, trackpad feel, unplug/reconnect
and sleep/wake checks remain unverified until exercised on hardware. Do not automatically
change system gestures, stop existing managers or grant OS permissions.

## Later scope

Commercial licensing, payments, auto-updates, launch at login, pinning and a
claim of ChainYourMac feature parity are outside the beta. Shortcut customization
was added to the local beta: every exposed global action supports recording,
alternate assignments, disabling and reset, with the engine retaining global
input ownership. Developer ID signing/notarization requires the chosen distribution
identity; local ad-hoc signing is acceptable for this build.
