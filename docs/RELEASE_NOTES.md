# Ribbon 0.2.0 beta 3

Window content keeps its full size as it slides past a screen edge.

On supported macOS 26+ systems, Ribbon can show a partial window without
squeezing its content or spilling that peek onto the next monitor. Moving
between windows preserves their content layout.

![Ribbon workspace](https://raw.githubusercontent.com/BlockchainHB/Ribbon/v0.2.0-beta.3/.github/assets/workspace-agent.png)

## What changed

- Full-size content at monitor edges on supported macOS 26+ systems, with
  independent strips on each display. Older or unsupported systems retain the
  compatibility behavior.
- Reliable focus for windows whose native minimum size is wider than their
  monitor, including when automatic centering is off.
- Correct pause and recovery for oversized windows that are already back at
  their original frames, without reporting an unfinished recovery.
- More native verification of pairing, hidden-window activation, interrupted
  width changes, exclusions, restoration and restart.

Default animation timing is unchanged. A display-timing experiment remains
disabled by default because the comparison showed higher resize costs.

## Install or update

Download **Ribbon-macOS-arm64.zip**. Pause and quit an existing Ribbon session,
unzip the archive, then replace **Ribbon.app** in **Applications**. Open it,
allow Accessibility access if requested, and enable **Settings → General →
Window management** when ready.

Requires **Apple silicon** and **macOS 15 or later**. The public download is
Developer ID signed, notarized by Apple, stapled and checked with Gatekeeper.
`SHA256SUMS.txt` and `release-manifest.json` accompany the archive.

[Getting started](https://github.com/BlockchainHB/Ribbon/blob/v0.2.0-beta.3/docs/GETTING_STARTED.md) · [Keyboard shortcuts](https://github.com/BlockchainHB/Ribbon#at-your-fingertips) · [Report an issue](https://github.com/BlockchainHB/Ribbon/issues)

## Beta limits

Native fixture checks cover two physical monitors at 60 Hz and 120 Hz, including
full-size content, focus, pairing and recovery. These geometry checks do not
establish 120 Hz compositor delivery or a busy third-party app performance gain.
Actual Raycast Quicklink UI, mixed-scale and portrait arrangements, reconnects
and sleep/wake still need further physical verification.

Pairs last for the current session. Apps keep their native minimum sizes.
Intel builds and automatic updates are not included. Pause Ribbon before
switching window managers.

No account or telemetry is required. Built on
[Paneru](https://github.com/karinushka/paneru), with upstream MIT notices preserved.
