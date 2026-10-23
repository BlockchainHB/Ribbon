# Ribbon 0.2.0 beta 2

Smoother window movement, with less work behind it.

Move left or right without losing the neighboring tile. When resizing makes
room for a hidden window, it can return sooner and restores its visible size
immediately, instead of waiting for a fixed-width cutoff.

![Ribbon workspace](https://raw.githubusercontent.com/BlockchainHB/Ribbon/v0.2.0-beta.2/.github/assets/workspace-agent.png)

## What changed

- More consistent movement in both directions and better visibility beside a
  centered or resized window.
- Safer ordering when tiles leave or return, including focusing hidden windows
  through normal application activation.
- Fewer native window queries and intermediate resize operations. Controlled
  two-monitor fixture tests measured about **32% less engine CPU time** than the
  uncapped, sequential comparison mode. This is not a system-wide or FPS claim.
- More focused verification of resize returns, keyboard navigation, pairing and
  recovery. App-imposed minimum sizes still apply.
- A project handoff and agent guide for continuing development.

Pairing, independent thirds arrangements, vertical stacks, customizable
shortcuts and automatic app inclusion with exclusions remain available.

## Install or update

Download **Ribbon-macOS-arm64.zip**. Pause and quit an existing Ribbon session,
unzip the archive, then replace **Ribbon.app** in **Applications**. Open it,
allow Accessibility access if requested, and enable **Settings → General →
Window management** when ready.

Requires **Apple silicon** and **macOS 15 or later**. Public packages must pass
Developer ID signing, Apple notarization, stapling and Gatekeeper assessment.
`SHA256SUMS.txt` and `release-manifest.json` accompany the verified archive.

[Getting started](https://github.com/BlockchainHB/Ribbon/blob/v0.2.0-beta.2/docs/GETTING_STARTED.md) · [Keyboard shortcuts](https://github.com/BlockchainHB/Ribbon#at-your-fingertips) · [Report an issue](https://github.com/BlockchainHB/Ribbon/issues)

## Beta limits

The performance checkpoint was tested on both physical monitors. The final
resize-return follow-up was verified on the laptop after relocation; fresh
physical two-monitor verification of that follow-up remains outstanding. Native
application activation was tested; actual Raycast Quicklink UI execution remains
separate. Busy third-party redraw, compositor frame pacing, mixed-scale display
transfers, reconnects and sleep/wake need further physical testing.

Pairs last for the current session. Some apps enforce minimum sizes, and macOS
can leave a small edge of a hidden window visible. Intel builds and automatic
updates are not included. Pause Ribbon before switching window managers.

No account or telemetry is required. Built on
[Paneru](https://github.com/karinushka/paneru), with upstream MIT notices preserved.
