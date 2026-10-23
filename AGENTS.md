# Ribbon

## Start here

Read [HANDOFF.md](HANDOFF.md) for the current checkpoint, commands, evidence and
remaining work. This file contains durable working rules; the handoff is a dated
snapshot. Check live Git and release state before changing or publishing anything.
Read [vendor/paneru/AGENTS.md](vendor/paneru/AGENTS.md) before engine edits.

Canonical workspace: `/Users/neat/dev/Ribbon`, outside iCloud Documents. The old
Documents/Codex location is a compatibility symlink, not another checkout.
Commands below run from the repository root unless stated otherwise.

## Ownership

- `vendor/paneru/`: pinned Rust/Bevy ECS engine. Owns layout, window geometry,
  display topology, focus, gestures, pairing and management policy.
- `native/Sources/Ribbon/`: SwiftUI/AppKit settings, overview, menu bar,
  Accessibility bridge and engine lifecycle.
- `native/Sources/RibbonCore/`: settings, shortcuts, recovery storage and commands.
- `native/Sources/RibbonFixture/`: disposable native windows for isolated QA.
- `website/`: static Astro marketing site, separate from the native application.
- `branding/IconComposer/Ribbon.icon/`: approved adaptive icon source.

Never duplicate layout/order/pair state in Swift. Keep native operations behind
existing manager/platform wrappers. Follow ECS components, change-driven systems
and schedule ordering. Preserve upstream notices and record vendor changes in
[vendor/paneru/RIBBON.md](vendor/paneru/RIBBON.md). Use pinned source and lockfiles;
avoid dependency churn and broad refactors outside the requested scope.

## Product and design contracts

- Manage normal open apps automatically; settings offer exclusions, not mandatory
  application selection. Enforce the same scope during creation and recovery.
- Keep independent strips on each monitor. Respect native minimum sizes, preserve
  preferred logical widths and never feed clipped/parked native geometry back
  into those preferences.
- Keep native writes ordered: release departing space, move visible leaders,
  reveal incoming tiles. Focus must not activate a tile on its parking display.
- Horizontal padding separates columns. Columns fill usable screen height;
  vertical padding separates actual stacked windows.
- Pairs link exactly two columns; arrangements can size independent columns.
  Pair membership is session-local. Preserve pause/recovery behavior.
- Settings use the native sidebar, blue accent, grouped rows and native controls.
  Do not reintroduce top tabs, a sidebar-close button, demo controls or oversized
  headers. The overview stays centered with large icons and titles.
- Approved identity: Fold / Cobalt. Preserve the Icon Composer appearances.
- Website copy leads with agent + IDE, multiple agent windows, agent + design
  tool, then everyday work. Ribbon arranges apps; it does not run agents or
  integrate with their APIs. Keep copy short, headings medium-weight, and the
  download section/footer white. Preserve the approved layout instead of adding
  badges, excessive headings or extra calls to action.

## Build and verification

```sh
scripts/verify.sh
scripts/build-app.sh
# Only after the existing app has quit:
scripts/install.sh
```

Use `scripts/swift.sh` for Swift build/test commands so signed artifacts stay
outside Documents/iCloud and use the correct linked SDK. Build paths are recorded
in `build/artifacts.json`; install targets `~/Applications/Ribbon.app`.
The debug-engine option builds a separate diagnostic bundle; the normal installer
selects the release bundle. Do not confuse a local ZIP with a notarized release.
See [development](docs/DEVELOPMENT.md) and [release process](docs/RELEASING.md).

Run `scripts/verify.sh` for product-code changes. For website changes, run
`npm ci`, `npm run check` and `npm run build` inside `website/`. For documentation
changes, check links, commands, metadata consistency and `git diff --check`;
do not claim a fresh desktop test based on older receipts. Report unit tests,
physical native QA and compositor/visual review separately.

## Desktop safety and evidence

Never run an unrestricted engine during automated QA. Use the existing
fixture-only harness, explicit bundle allowlist, isolated state/service and a
fresh output directory. Do not interrupt an active user session to test a build.
The desktop must be unlocked; confirm connected monitors before dual-display QA.
Preserve failed receipts, stop owned test processes and restore fixture frames.

Do not reset privacy grants, edit TCC, rearrange displays or alter system
appearance as an incidental test step. Investigate first; obtain explicit user
authorization for privacy resets or disruptive OS changes. Prefer certificate-
backed builds so Accessibility approval survives updates. Keep signed bundles
outside iCloud-managed paths.

Raw `build/qa/` reports and desktop captures are local evidence, not public assets.
Never commit credentials, private recovery journals or personal window captures.
A 60 Hz frame sampler does not establish 120 Hz compositor delivery. Verify real
Raycast UI separately from the native application-activation route.

## Delivery

Use a focused branch and PR. Preserve unrelated local/untracked files. Inspect
staged changes before committing. Merge or publish releases only when requested
by the user; do not infer release authorization from a source-code fix.
Wait for CI and verify the exact merged head. Public releases use a new tag,
committed source, Developer ID signing, notarization, stapling, Gatekeeper
assessment and checked assets. Never replace bytes of an existing release asset.
Do not upload local signing/notarization logs or credentials.

Communicate the outcome, checks and material limits plainly. Unless specifically
asked, do not end responses with suggested next steps.
