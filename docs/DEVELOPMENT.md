# Developing Ribbon

Ribbon is a SwiftUI/AppKit application controlling a pinned Rust engine based on Paneru. The engine owns window geometry, layout, focus, gestures, and managed-app policy. Swift owns configuration and engine lifecycle. Keep layout state in the engine.

## Build

Requires an Apple silicon Mac, macOS 15 or later, Xcode 26 or later with Icon Composer asset compilation, Python 3, and Rust 1.95.0. `rust-toolchain.toml` pins the Rust toolchain; Cargo and website dependencies are locked.

```sh
scripts/build-app.sh
scripts/install.sh
```

The build uses a unique installed Developer ID identity if available. Set `RIBBON_SIGNING_IDENTITY` to select one explicitly. Without a certificate, local builds use ad-hoc signing and may require renewing Accessibility permission after updates.

The staged signed bundle lives in Library/Caches and is recorded in `build/artifacts.json`. The local archive is `build/Ribbon-beta.zip`. Installation uses `~/Applications/Ribbon.app`; quit the existing app before replacing it.

For faster engine iteration:

```sh
scripts/build-app.sh --debug-engine
```

This creates a separate debug archive. It is not a distributable release. [Public release packaging](RELEASING.md) adds notarization and a stapled ticket.

## Source map

| Area | Ownership |
| --- | --- |
| `native/Sources/Ribbon/` | Settings, overview, menu bar, Accessibility bridge, and session lifecycle |
| `native/Sources/RibbonCore/` | Settings models, shortcuts, recovery storage, and command execution |
| `native/Sources/RibbonFixture/` | Disposable windows for isolated desktop QA |
| `vendor/paneru/` | Checked-in engine source; upstream commit and local changes in `RIBBON.md` |
| `branding/IconComposer/Ribbon.icon/` | Adaptive app icon source |
| `website/` | Static Astro marketing site |
| `release.json` | Version, build, tag, and release archive name |

## Verify

```sh
scripts/verify.sh
```

This runs Rust formatting, Clippy, default and shipping-feature tests, Swift formatting and tests, whitespace checks, and configuration/signature checks when a staged bundle exists. It does not start unrestricted window management.

Physical desktop verification is separate. Never run an unrestricted engine during automated QA. Use the app's explicit disposable-fixture allowlist and a fresh evidence directory. Quit existing Ribbon instances first; do not interrupt a user's active session.

The native `--qa-output` suite verifies disposable test windows and an excluded sentinel. `--qa-dual` requires two connected displays. Specialized suites cover pairing, application activation, overview, and parking. Follow the existing harness and report hardware checks separately from mocked engine tests.

Historical local results are recorded in [verification.md](verification.md); paths under `build/qa/` refer to local receipts, not public bundled artifacts. Earlier receipts do not establish compatibility for a newly built executable.

## Recovery

Settings and a private recovery journal live in `~/Library/Application Support/Ribbon`. Original frames are restored where applications allow it; new windows without a pre-session record are fitted onto a visible display. Missing windows are ignored and failed recovery stays available. Document titles and contents are not persisted.

Preserve upstream notices. Record engine integration changes in [vendor/paneru/RIBBON.md](../vendor/paneru/RIBBON.md). Do not commit signing keys, notarization credentials, local recovery journals, or personal desktop captures.
