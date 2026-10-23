# Ribbon handoff

Snapshot: **22 October 2026, America/Toronto**. Open
`/Users/neat/dev/Ribbon` as the project in T3 Code. Read [AGENTS.md](AGENTS.md),
then the relevant source/documentation below. Commands use ordinary Git, shell,
Rust, Swift and Node tooling; this handoff does not depend on the previous chat.

## Current checkpoint

Ribbon is a native scrolling window manager for Apple silicon Macs, macOS 15+.
The repository is [BlockchainHB/Ribbon](https://github.com/BlockchainHB/Ribbon).
[PR #1](https://github.com/BlockchainHB/Ribbon/pull/1) merged the recent engine
work into `main` at `113ad65efd40544e73cd5ac1434552d3024ad54d`:

| Commit | Change |
| --- | --- |
| `9515ed0` | Preserve visible neighbors in both directions and improve focus/geometry ordering |
| `b9b1cfe` | Batch native frame reads, sample intermediate geometry per display, add opt-in profiling |
| `8c7296b` | Remove the fixed return-width gate and restore exposed size directly after reveal |

This handoff update prepares **0.2.0 build 18 / `v0.2.0-beta.2`**. Read
[release.json](release.json) for the configured version and
[GitHub Releases](https://github.com/BlockchainHB/Ribbon/releases) for actual
publication state. A configured tag or a local archive does not establish that
publication/notarization succeeded. The prior public prerelease is
`v0.2.0-beta.1`; its existing assets must remain intact.

At snapshot, the installed local app was `~/Applications/Ribbon.app`, open and
paused. Recheck before installing or testing. Do not stop a newly active user
session. The pre-release-update bundle's `BUILD.json` records `b9b1cfe` because
it was assembled before the follow-up commit; its measured engine hash is below.
A public package must instead record its clean committed source and pass the
release script's provenance checks.

## Working setup

**Latest user direction:** The user enabled the installed
fixed-content build and reports **“its smooth”**. They request a deep research
phase on preserving/improving scroll and resize animations after compaction.
Read [animation research](docs/animation-research.md) for the baseline, concrete
hypotheses, measurement constraints and outstanding work. The normal engine is
may be active; do not interrupt it for fixture QA. The oversized-minimum focus
review correction is committed/pushed on `fix/stable-native-content` at `3308572`,
with an unrun native oversized test. Keep the smooth installed build intact.

The animation research now has source-backed findings and reproducible windowless
probes in `scripts/research-animation-{clock.swift,motion.py}`. The strongest lead
is per-display wake timing plus one sampling decision per display tick; the
existing profiler misses projection-only commits. A 27-trial Cocoa experiment
and 44 pure-production-motion scenarios are recorded in the research document.
No production animation changes, new native A/B, installation or release were
performed during that research phase. The user then approved implementation.
`perf/display-aware-animation` now adds an opt-in display-link clock, owner tick
sampling, watchdogs and projection-aware profiling. Read the
[experiment brief](docs/display-animation-experiment.md) for source boundaries,
verification receipts and exact same-binary QA commands. The new clock remains
off by default. The existing curve and installed app are unchanged; native
fixture A/B and physical improvement remain unverified.

**23 October investigation update:** `fix/stable-native-content` adds a
fixture-only signed-app diagnostic and the
[fixed-width edge investigation](docs/fixed-width-edge-investigation.md).
Independent readback invalidated direct foreign-window crop calls. A later
app-owned compositor-space proof preserves full-size content and owner-only
peeks on both monitors, including a separately launched signed fixture and 50
motion observations. The integrated signed diagnostic engine passed 21 native
two-monitor checks, and live WebKit fixtures passed 50 motion observations per
direction without viewport resize. Source now defaults to projection when the
macOS 26+ runtime supports it; older/unsupported systems retain compatibility.
The normal signed release-profile build at `c34fb9ac5c29ead3e4c8e1eef596d11e386b8f6c`
also passed all 21 checks with default settings, was installed in
`~/Applications/Ribbon.app`, and reopened paused (no engine running at delivery).
No public release or merge was performed. Read the investigation for exact hashes,
receipt paths, failed attempts and remaining real-app/compositor QA.

- Canonical checkout: `/Users/neat/dev/Ribbon`, outside iCloud sync. Historical
  Documents/Codex paths may be symlinks or evidence references. Do not move back.
- Requirements: Apple silicon, macOS 15+, Xcode 26+ with Icon Composer support,
  Python 3, Rust **1.95.0**, and Node **22.23.4+** for the website. Use the current
  full Xcode developer directory and checked-in lockfiles.
- Signed bundles and Swift build products live under `~/Library/Caches/Ribbon`.
  Read `build/artifacts.json` for current output paths instead of hardcoding a
  cache suffix; paths depend on checkout location.
- Settings/recovery: `~/Library/Application Support/Ribbon`. Recovery data is
  private local state. A normal session manages all eligible apps with exclusions.
- Local-only files present before this handoff: `docs/workspace-location.md`,
  `docs/workspace-move.json`, `scripts/qa-pairing.py`. Preserve them; they were
  untracked and are not automatically part of this PR or a fresh clone.

## Build, run and test

From the project root:

```sh
scripts/verify.sh
scripts/build-app.sh
# Quit the existing Ribbon app before installation.
scripts/install.sh
open -a "$HOME/Applications/Ribbon.app"
```

The app starts paused. Enable window management deliberately through General or
the menu bar. Avoid another active window manager. Do not launch an unrestricted
engine as an automated check. A missing Accessibility grant is a real gate;
rebuilding ad hoc or silently resetting permissions is not a workaround.

`scripts/verify.sh` runs formatting, strict Clippy, both Rust feature suites,
Swift tests, whitespace checks and staged config/signature checks. It does not
start unrestricted management. For a quicker diagnostic engine build, use
`scripts/build-app.sh --debug-engine`; its separate artifact pointer is
`build/artifacts-debug.json`. `scripts/install.sh` installs the normal release
bundle, not that debug bundle. Use `scripts/swift.sh test` for Swift-only tests.

Website development:

```sh
cd website
npm ci
npm run check
npm run build
npm run dev -- --port 4321
```

The site is static Astro. Download URLs import root `release.json` through
`website/src/lib/release.ts`. A missing `PUBLIC_SITE_URL` intentionally keeps the
site non-indexable. Website deployment is separate from publishing a native ZIP.

## Where to work

| Concern | Entry points |
| --- | --- |
| Session, permissions, pause/recovery | `native/Sources/Ribbon/SessionController.swift`, `AccessibilityWorkspace.swift` |
| Settings | `native/Sources/Ribbon/Settings/` |
| Menu and centered icon overview | `RibbonStatusMenu.swift`, `Overview/` under `native/Sources/Ribbon/` |
| Settings/shortcuts/storage models | `native/Sources/RibbonCore/` |
| Canonical layout/pairing/visibility | `vendor/paneru/src/ecs/layout.rs`, `ecs/layout/` |
| Scheduling/native commits/focus | `vendor/paneru/src/ecs.rs`, `ecs/systems.rs`, `ecs/focus.rs` |
| Motion/native AX reads | `ecs/motion.rs`, `manager/windows.rs`, `manager/frame.rs` under `vendor/paneru/src/` |
| Profiling | `vendor/paneru/src/performance.rs` |
| Native fixtures and QA | `native/Sources/RibbonFixture/`, `DesktopVerification*.swift`, `scripts/qa-*.py` |
| Website hero and motion | `website/src/components/HeroScene.astro`, `website/src/scripts/scene-motion.ts`, `website/src/styles/hero.css` |
| Website sections and copy | `website/src/pages/index.astro`, `website/src/components/`, `docs/WEBSITE_COPY.md` |
| Approved icon | `branding/selection.json`, `branding/IconComposer/Ribbon.icon/` |

Read the vendor's [agent rules](vendor/paneru/AGENTS.md),
[architecture](vendor/paneru/ARCHITECTURE.md) and
[local patch record](vendor/paneru/RIBBON.md) before engine edits. Layout is
Rust-owned; the native overview reads engine state and sends commands. The
website illustrates window arrangements; it is not an agent-session integration.

## Product decisions to preserve

- A horizontal strip per monitor; all normal open apps included by default.
  Excluded Apps opts apps out. No mandatory application-selection onboarding.
- Width presets include thirds, half, two-thirds, three-quarters and full width.
  Preserve widths / Fill available space remains a user choice.
- Columns fill usable height. Horizontal gaps separate columns; vertical gaps
  apply between windows stacked within a column.
- Side-by-side pairing and vertical stacking are different. Pairs move together;
  thirds arrangements can also remain independent. Pairing lasts one session.
- OS application activation should reveal the correct hidden tile. Actual Raycast
  Quicklink UI testing remains separate from the tested activation route.
- Native sidebar settings, blue accent, system controls/traffic lights. Keep the
  sidebar visible, compact grouped rows and readable search. No return to top
  tabs, oversized headers, demo ribbons or decorative controls.
- Fold / Cobalt branding with Icon Composer light/dark/clear/tinted appearances.
- Clean agent-first website: agent + IDE, multiple agent windows, agent + design
  tool, then regular work. Short copy, medium headings, white footer/download
  area. The hero sequence illustrates sliding, pairing, then a separate stack.

## Verification already completed

These are **historical receipts**, not a substitute for checking a changed build.
See [verification](docs/verification.md),
[performance](docs/engine-performance.md), and
[return-motion review](docs/resize-return-motion.md).

- Latest source checks: **502/419 engine**, **46/39 library**, **26 Swift** tests;
  feature suites overlap and are reported separately. PR #1 CI passed Website,
  Native and engine, and security checks.
- Performance checkpoint: four alternating same-binary A/B runs, 16 native
  checks each, on the external 2560×1440 / 60 Hz display and built-in
  1728×1117 / 120 Hz display, both 2× backing scale. Median size writes fell
  77.5%, frame queries 87.8%, active-frame work 56.7%, engine CPU 32.5%.
  Input-latency bounds stayed roughly unchanged. The comparison toggled only
  batching/sampling, retaining the same correctness safeguards.
- Broader checkpoint: 18 single-display and 20 dual-display native checks.
- Final follow-up: **14 resize-return**, **13 keyboard/navigation**, **14 pairing**
  checks on the laptop. These include 12 actual Control–Option arrows, returns
  from both sides, eight external hidden-window activations, no sampled overlap,
  exact restoration, pair reorder/Ungroup, exclusions and lifecycle. Light/dark
  overview captures were inspected.
- Those final receipts all match pre-build-18 engine SHA-256
  `c646552ae49371f05f6e2315f994e656f91c3c29374c668849249ab1afa4bb18`.
  They live under `build/qa/resize-return-{signed,keyboard,pairing}-final/`.
  `build/resize-return-final-verify.log` records the local code checks.

Raw receipts are ignored local files, absent from a fresh clone. Some desktop
captures include private background content; do not upload them. Failed attempts
were preserved separately and are not passing evidence.

Reproduce focused native checks only when Ribbon is paused, the desktop is
unlocked and no other fixture run is active. Use fresh output directories:

```sh
python3 scripts/qa-performance.py "$PWD/build/qa/fresh-return" \
  "$HOME/Applications/Ribbon.app" --resize-return
RIBBON_QA_KEYBOARD=1 python3 scripts/qa-performance.py \
  "$PWD/build/qa/fresh-keys" "$HOME/Applications/Ribbon.app"
# The following runs both single- and dual-display suites; connect two monitors.
python3 scripts/qa-startup.py "$HOME/Applications/Ribbon.app" \
  "$PWD/build/qa/fresh-desktop" --general
```

The historical pairing driver under `build/` is local, not checked-in tooling.
Read the native pairing harness and external input/capture handshake before
reproducing that suite; a bare `--qa-pairing` launch is not a complete driver.

## Remaining verification

The user moved locations before the final return checks; only the laptop was
connected afterward. Prioritize physical **two-monitor resize-triggered returns**,
including an external-screen tile parked on the smaller laptop and native
activation back to its owner. Earlier dual-monitor results do not cover the
final follow-up. Actual Raycast Quicklink execution, busy Claude/IDE redraw,
compositor pacing, slow-motion video, mixed-scale/portrait configurations,
unplug/reconnect and sleep/wake remain unverified. Respect the existing scope
and recovery guards while testing. A 60 Hz frame sampler does not prove 120 Hz
compositor delivery. Do not claim those gaps are resolved from unit tests.

## Public release workflow

The user authorized publishing the next prerelease along with this handoff.
For future releases, obtain a new explicit publication request. Preserve old
assets and use a fresh version/tag. [RELEASING.md](docs/RELEASING.md) is the
canonical checklist. Keychain profile `Ribbon` was used previously; credentials
must stay in Keychain and must never enter this file, source or shell history.

```sh
# Tracked source must already be committed, with the intended release.json.
scripts/prepare-release.sh Ribbon
```

This builds from committed source, signs, notarizes, staples, assesses Gatekeeper
and writes `build/releases/<tag>/`. Publish only the named release ZIP,
`SHA256SUMS.txt` and `release-manifest.json`. Verify public asset checksums, source
commit/tag correspondence and download links afterward. Preparation alone does
not publish. Do not upload the notarization submission archive/logs, a debug
bundle or the generic local `build/Ribbon-beta.zip` as the release artifact.
