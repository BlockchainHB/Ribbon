# Dual-monitor contract

Dual monitors are a first-beta acceptance requirement. The Rust engine remains
the only owner of display topology, strip geometry, focus and transfers. Swift
owns controls, process lifecycle and restoring pre-session window positions.

## Required behavior

- Each physical display has an independent strip. Navigating, opening, stacking
  or resizing windows on one display must preserve the other display's widths.
- Hidden columns retain a sliver on their owning display. At a shared monitor
  edge, park them at a free outer edge instead of inside the neighboring screen.
  Entering and leaving that parking position snaps rather than animating across
  the neighboring strip.
- Control–Option–N moves the focused window to the next display and follows it.
  Preserve its width as a proportion of usable screen width, accounting for the
  Dock and margins. A round trip must recover its width within pixel rounding.
- A smaller screen uses its own height and menu/notch clearance. It must not
  inherit dimensions from a larger external display.
- Pause restores recorded positions on both displays. If a display is missing,
  fit the window onto a connected display. Keep failed recovery records.
- Display changes belong to the engine's existing event/reconciliation path;
  the native UI must not keep a second layout model or poll window geometry.

## Hardware verification

The isolated dual suite creates four disposable windows on each connected
display and one excluded sentinel. It checks independent layouts, shared-edge
overflow, six display transfers, width proportions, opening a ninth window on
the second monitor while focus starts on the first, and pause/restart recovery.
Actual NSWindow reports and engine state are checked independently.

Run the installed app with both --qa-dual and
--qa-output /absolute/path/to/fresh/report.json. Reports include screen geometry,
scale and an engine SHA-256. Only the test applications enter the managed scope.

Current test hardware is a 2560 × 1440 external display beside a 1728 × 1117
built-in display, both at 2× scale. Deterministic tests additionally cover
negative coordinates, vertically arranged displays, display removal and return,
transient enumeration failures, geometry changes and wake reconciliation.

Physical unplug/reconnect, clamshell transitions, sleep/wake, mixed refresh rates,
portrait arrangements and trackpad feel require separate manual hardware runs.
Automated QA does not change system display arrangement or sleep the user's Mac.
