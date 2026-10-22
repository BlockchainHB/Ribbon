# Local beta verification — 21 October 2026

Ribbon 0.2.0 build 16 adds side-by-side window pairing, separate two-column
arrangements and group-aware focus/reorder/monitor transfer. Build 15's session
controls and build 14's motion improvements remain. The installed app is
`~/Applications/Ribbon.app`; the deliverable is `build/Ribbon-beta.zip`.
It is Developer ID signed and not notarized. Current hashes, receipts and
limitations are in [verification.json](verification.json).

## Measured engine performance — 22 October 2026

[Implementation and controlled results](engine-performance.md). The same signed
binary passed four alternating 16-check native runs on both connected monitors.
Optimized mode reduced median size writes 77.5%, frame queries 87.8%, active-frame
work 56.7% and engine CPU 32.5%; input-latency bounds stayed roughly the same.
The broader suite passed 18 single-display / 20 dual-display checks; pairing
passed 14 checks. Light/dark overview captures were inspected. All automated
window management remained restricted to disposable fixtures.

`scripts/verify.sh` passed 501/418 engine, 46/39 library and 26 Swift tests, plus
format, strict Clippy, generated configuration and signatures. Evidence:
`build/perf-final-verify.log`, `build/qa/performance-comparison.json`,
`build/qa/perf-desktop-verified/summary.json`, and
`build/qa/perf-pairing-verified/report.json`.
The installed engine SHA-256 is
`883411609ccf9b5b265fff13fc039504ae2000d088442127ce887d52a97150ea`.
Native samples establish geometry correctness, not compositor FPS or busy
third-party redraw cost. Normal Ribbon was reopened paused after installation.

## Pairing (build 16)

[Behavior and usage](pairing.md). `scripts/verify.sh` passed: 46+483 default Rust,
39+400 shipping Rust, and 26 Swift tests. Eleven pairing regressions cover join,
fit, focus, block reorder, stack leader removal, ungroup geometry, insertion,
accepted width readback, fill policy, viewport resize, and simulated transfers
between unequal monitors. Format, Clippy, generated configuration and signature
checks passed. The archive CRC and both archived executable bytes match the
installed app; its engine hash matches the native QA receipt.

[Native receipt](../build/qa/pairing/build16-release-2/report.json): **14 checks
passed** using only disposable managed fixtures and an excluded sentinel. Real
window measurements verify ½–½, ⅓–⅔ and ⅔–⅓, stationary internal focus, whole-pair
reordering, native activation of a hidden pair member, actual context-menu
Ungroup, independent arrangement, start/pause/restart and frame restoration.
The overview's [light](../build/qa/pairing/build16-release-2/pair-overview-light.png)
and [dark](../build/qa/pairing/build16-release-2/pair-overview-dark.png) native
captures were visually inspected. System appearance and privacy grants were not
changed. The first candidate's QA receipt cast failed after the native menu
clicked successfully; it is retained separately and not counted as passing.

Hardware: built-in Retina display, 1728×1117 logical points at 2× scale. The user
chose one-display verification. Physical dual-monitor pairing, mixed-scale
transfers, unplug/reconnect and second-monitor edge flashes remain unverified.
Actual Raycast Quicklink UI execution remains separate from the passed native
application-activation test. Pair membership is intentionally session-local.

## Session controls and menu bar (build 15)

The General switch previously disabled whenever `recoveryPending` was true,
which includes every active session. This made a responsive app appear frozen.
The switch and menu now share one availability rule: a running session can be
paused despite its recovery journal; starting/stopping and pending old recovery
still block conflicting operations. Permission remains checked by the start flow.

Ribbon explicitly sets its own status item's public `isVisible` property and
supplies a symbol fallback if its branded image cannot load. The native menu is
populated before the first click; waiting for `menuWillOpen` left it empty and
inert. Global engine chords are cleared while the menu is closed.
Apple documents visibility persistence via `autosaveName` in
[NSStatusItem.isVisible](https://developer.apple.com/documentation/appkit/nsstatusitem/isvisible).
No Control Center preference database, other app setting, or privacy grant was edited.

`scripts/verify.sh` passed: 46+472 default Rust, 39+389 shipping Rust, and 25 Swift
tests. Three added UI component tests cover running/recovery availability,
transition/start guards, and initial native menu contents.
Log: `/tmp/ribbon-controls-verify-installed.log`.

`build/qa/controls/build15-release-5/report.json` records 16 passing native checks.
Actual mouse clicks performed on -> off -> on -> off through the General switch,
including an active recovery journal. An external native Accessibility press opened
the actual Control Center-hosted icon; its menu had nonzero rendered dimensions
and a Settings row, and Escape closed it. The external driver is retained as
`build/qa/controls/build15-release-5/driver.py`. Earlier failed candidates remain
in that directory's siblings. AppKit proxy status-item coordinates proved unsuitable
for that check; acceptance uses the external native accessibility tree.

The fixture scope and excluded sentinel remained enforced. Existing movement,
resizing, hidden-tile focus and drag checks also passed: 314 native frame samples,
77 moving samples, and 12 pt moving/settled gaps. Only one physical display was
connected. Normal Ribbon was reopened paused after QA.

## Continuous motion (build 14)

`scripts/verify.sh` passed: 46 library + 472 binary Rust tests with default
features, 39 library + 389 binary tests with shipping features, and 22 Swift tests.
Formatting, Clippy, generated configuration and bundle signatures passed.
Log: `/tmp/ribbon-motion-verify-installed.log`.

`build/qa/motion/build14-release-5/report.json` records 14 passing native checks,
using disposable fixtures only. Native modifier-scroll input moved the strip.
Repeated commands interrupted movement and resizing before completion and settled.
The fixture recorded 308 native geometry samples, including 76 moving samples;
minimum moving gap and settled gap were both 12 pt. No overlapping visible tiles
were observed. No neighbor spill was observed, but only one physical display was
connected, so this is not dual-monitor proof. Native icon drag, arrow/Return
navigation, hidden-tile focus, full height, stack gaps, excluded sentinel,
restore and restart all passed. The engine hash matches the installed signed app.
After fixture QA completed, the normal app was reopened and its previous running
user session resumed. No automated frame checks ran against personal apps.

Actual light/dark native captures were inspected at
`build/qa/motion/build14-release-5/overview-light.png` and `overview-dark.png`.
Capture used the external, user-authorized macOS screenshot tool; Ribbon did not
receive a new Screen Recording grant. The repeated generic icons belong to the
fixture application. The engine remains the sole owner of layout geometry/order.
See [motion audit](motion-audit.md) for findings, timing and unperformed checks.

Earlier candidates are retained. Release-1 hit LaunchServices -600 before testing.
Release-2/3 failed a final gap assertion with a single full-width visible tile;
recorded native motion itself retained 12 pt separation. Release-4 passed 14
interaction checks, but screenshot commands produced no files; it is not used as
visual acceptance. Release-5 requires actual image files and captures externally.
A physical second monitor, real finger swipe feel, slowed screen-video review,
and changing the OS Reduce Motion preference were not verified. The instant
engine path and UI Reduce Motion branches were inspected/tested in software.

## Icon overview and vertical spacing (build 13)

`scripts/verify.sh` passed: 46 library + 468 binary Rust tests with default
features, 39 library + 385 binary tests with shipping features, and 22 Swift tests.
Formatting, Clippy, generated engine configuration and bundle signatures passed.
Current log: `/tmp/ribbon-overview-verify.log`.

`build/qa/overview/release-9/report.json` records 11 passing native checks using
only disposable fixtures and an excluded sentinel. A native injected Control–Option–Tab
opened the overview; a native mouse drag inserted the column; arrow/Return
navigation and clicking a genuinely offscreen tile restored focus. The sentinel
never moved, pause restored original frames, and restart/recovery passed.

On the built-in 1728 × 1117 display, the full-width native frame was x=12, y=33,
width=1704, height=1084: it reaches the usable bottom at 1117. Two stacked windows
ran from y=33 to 569 and y=581 to 1117, preserving exactly 12 pt internally and
zero outer vertical margin. These are native frame observations, not mocked proof.
Only the built-in display was connected. Build 13 has not passed physical
second-monitor checks; the engine tests cover independent strips and rejected
cross-display drops. Older dual-display receipts remain historical.

Actual native light/dark captures were inspected at
`build/qa/overview/release-9/overview-light.png` and `overview-dark.png`.
The overview is centered, sized to its contents and uses 80 pt app icons with a
single title. The repeated generic icons in these captures belong to the disposable
fixture app; normal use resolves each application's installed icon. The normal
app was reopened paused after QA; no unrestricted engine was launched by testing.
Earlier failed candidates were retained in `build/qa/overview/`. In particular,
`diagnostic-3` included a CLI intervention and is not an acceptance receipt.

## Width preset (build 12)

Width cycling now uses 33%, 50%, 67%, 75%, 100%. The installed build’s generated
configuration includes the new preset and passes engine config validation.
`scripts/verify.sh` passed (`/tmp/ribbon-width-step-verify.log`). Installation
retains build 11’s certificate-backed signing requirement; the reopened GUI
shows Accessibility Allowed. Window management was left paused. No new physical
width-cycle test was run, and no unrestricted engine was launched by QA.

## Permission onboarding (build 11 history; resolved in build 12)

Installed build 11 uses the existing Developer ID identity instead of an ad-hoc
code hash. The native app and engine have identical certificate-backed designated
requirements. The build script selects a unique Developer ID identity or accepts
RIBBON_SIGNING_IDENTITY; debug builds stay ad hoc by default. No signing identity,
private-key ACL or OS privacy grant was created or modified by QA.

The General switch remains enabled while permission is missing and opens the
permission flow. A native help line explains the gate. Cooperative activation
brought System Settings forward immediately when the actual button was pressed.
Permission refreshes on app activation and while the active window awaits approval.
The native and engine permission checks remain enforced.

The build passed scripts/verify.sh, signature validation and archive/hash checks.
GUI AX verified the switch is enabled. The user subsequently reported that approval
still loops. Read-only TCC logs from the LaunchServices-launched GUI and its child
confirm `Failed to match existing code requirement` for `dev.ribbon.app` and
`kTCCServiceAccessibility` (OSStatus -67050). The saved requirement is the old
`cdhash e463b18de8bdb06671037130e348fa887fd7fb6e`; the current native and engine
requirements are certificate-backed. Enabling the existing row did not replace
that requirement. After explicit user authorization, quit Ribbon and ran only
`tccutil reset Accessibility dev.ribbon.app`; the tool reported success. Reopened
the installed signed app and used its General permission button. System Settings
is frontmost; native AX confirms Ribbon has a fresh unchecked row (AXValue=0).
Other apps’ grants were not changed. The user then enabled the new row. The real GUI reported Allowed after
installing build 12, confirming that approval survived the signed update.
See `../build/qa/permission-identity/diagnosis.json` for bounded evidence.
Build 10 layout receipts below are not claimed as build 11 hardware QA.

Sources: [Apple code identity](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)
and [cooperative activation](https://developer.apple.com/documentation/appkit/passing-control-from-one-app-to-another-with-cooperative-activation).

## Automated checks

`scripts/verify.sh` passed: 46 Rust library + 472 binary tests with default
features, 39 library + 389 binary tests with shipping features, and 25 Swift
core/component tests. Formatting, Clippy with warnings denied, generated config
and staged bundle signature passed. Feature suites overlap and are counted
separately. Native component tests do not establish physical desktop behavior.

Tests cover scope enforcement, automatic-policy migration, exclusions, recovery,
shortcut persistence/conflicts, compact parking geometry, simulated native size
clamping, external focus reveal, and native Space activation without logical
display migration. Missing/invalid engine policy fails closed. QA always uses
an explicit disposable-fixture allowlist.

## Width-policy checks (build 10)

Layout → Column widths offers Preserve widths (default) and Fill available space.
Fill expands columns proportionally only while the entire strip fits its own
usable monitor width. Overflow restores preferred widths and scrolls. Switching
back restores preferences rather than retaining the automatic expansion. Width
presets, full-width toggles and transfers use preferred widths in fill mode.

Eight engine regression tests cover proportional rounding, overflow, opening and
closing windows, explicit resizing, centering, independent displays and six
cross-display moves. Swift tests cover defaults, old-settings migration,
persistence, generated configuration and rejecting an unknown policy.

The debug engine passed eight native checks, including two live policy round
trips on both physical monitors. Four 300-point fixture windows expanded to
625 points on the external display and 417 on the laptop, keeping native 12-point
gaps and edges. Returning to Preserve restored all eight to 300 points.
Receipt and native screenshots: `build/qa/width-policy/debug-2`.
The first failed setup receipt is retained as `build/qa/width-policy/debug`.

The native picker was inspected in light and dark appearances; selecting Fill
persisted when reopening Settings. Captures: `build/qa/width-policy/settings-light`
and `settings-dark`. These GUI checks used the debug-engine bundle with the same
native settings views and did not enable unrestricted window management.

The optimized installed release also passed all eight focused native checks.
Receipt: `build/qa/width-policy/release-2/report.json`; its native screenshots
show both screens filled. The first direct launch restored no settings window,
so the task never started; that timeout is retained under `release`. Opening
through LaunchServices resolved the test-startup condition. Signatures, archive
CRC, executable hashes and SDK 27 linkage were verified after installation.

## Physical parking checks (build 9)

Build 9 passed 14 single-strip and 14 dual-monitor checks, plus
parent-watchdog cleanup (371 ms observed). Receipt:
`build/qa/offscreen-parking/release-build9-2/summary.json`.

Coverage includes exact scope, new-app admission, launcher-style activation,
compact parking and external reveal on each monitor, monitor isolation, six
width-preserving display transfers, opening another window, excluded-sentinel
protection, original-frame restoration, and restart lifecycle.

Across 672 native NSWindow frame samples, neighboring-monitor body-spill samples
were zero. The minimum observed moving gap was 11 pt; settled gaps were 12 pt.
These are nominal 60 Hz geometry samples, not continuous compositor proof or
input-to-photon timing. Parking residuals are excluded from content-gap checks
but separately measured on every physical display.

Hardware: macOS 27.0.1, Apple silicon, 2560 × 1440 Kuycon G32P beside a
1728 × 1117 built-in display, both at 2× scale. The laptop sits to the right
with its top offset 323 pt. Alternative topologies have deterministic coverage,
not physical acceptance.

### Parking behavior and limits

Ribbon parks at a stable free outer right corner, preferring the owning monitor
when safe. At shared monitor seams it parks before a partial tile body spills
onto the neighbor. Native presentation may fit the parking host before moving;
the logical size and original strip owner remain unchanged. Reveal restores
intended native dimensions before focus reconciliation. Native Space activation
does not migrate a parked tile into the neighbor's strip.

The fixture acceptance budget permits a residual edge at most 1 logical point
wide and 32 points tall. This is not universal zero-pixel invisibility across
all apps or shadows. No automatic Dock minimization, app hiding, covering overlay
or privileged opacity is used. Original requested/actual native probes are in
`build/qa/offscreen-parking/probe` and `probe-full`. Failed candidate runs
`dual-1` through `dual-8` are retained. `dual-9` is a passing debug-engine receipt;
`release-build9-2` is the optimized installed release.

### Actual Raycast Quicklink

Separate physical integration receipt pending. Launcher-style activation in the
release suite is passed; it is not represented as an actual Raycast pass.

## Native settings review

All four panes were captured and visually inspected in light and dark appearance:
`build/qa/offscreen-parking/settings-build9-light` and `settings-build9-dark`.
The views use a native NavigationSplitView sidebar, grouped forms, blue accent,
SDK 27 glass controls, standard traffic lights and no sidebar-toggle button.
Modifier and trackpad values align at the trailing edge.

The search placeholder is Search. Native field glass has clearance above the
list, avoiding the clipping in the user's screenshot; semantic text colors adapt
to both appearances. Real typing filtered shortcuts, and the native clear button
restored the rows. Shortcut editing opened and cancelled in the light appearance.
Applications is now Excluded Apps: all normal open apps are managed automatically,
and a switch opts its app out. Raw stored pane identifiers are retained.

These screenshots predate only QA-harness focus synchronization changes, with
identical settings views. No user acceptance is claimed. System appearance was
not changed; the app-only QA appearance override was used. GUI permission
onboarding remains separate from inherited CLI Accessibility trust.

## Unverified

Physical unplug/reconnect, sleep/wake, clamshell, portrait and mixed-refresh
setups, trackpad feel, alternate keyboard layouts, full keyboard traversal,
VoiceOver, increased-contrast settings, final remapped global-key dispatch and
fresh GUI Accessibility onboarding remain unverified. The recorder's final full
save/reset/alternate interaction matrix is not re-certified by the sheet check.
Live adaptive Dock appearances remain unverified.

Historical toolbar/column-form screenshots and prior build hashes are before
states, not current visual evidence. The user's System Settings/sidebar direction
supersedes the earlier toolbar study. The scoped audit is in [ui-audit.md](ui-audit.md).

## Reproduce

    scripts/build-app.sh
    scripts/install.sh
    scripts/verify.sh
    python3 scripts/desktop-qa.py "$HOME/Applications/Ribbon.app" "$PWD/build/qa/fresh-run"

Use a fresh output directory, exactly two displays, and no running Ribbon
instance. The runner restores and closes only its disposable test windows.
No unrestricted engine is used during automated QA.


## Maximized startup visibility regression — 22 October 2026

A native maximized window is wider than Ribbon's padded tile viewport. On adjacent
monitors, compact-parking seam protection could classify even the focused window
as crossing into its neighbor and move it to the outer parking corner. Activating
that window again repeated the same decision. Claude and Codex were still running.

The engine now fits an oversized column to its own monitor's usable width when
adopting it. If an app refuses to fit because of its minimum size, a visible focused
oversized column stays reachable. Genuinely hidden windows still park, and the
pre-session recovery journal retains their original native frames.

A focused regression failed before the fix and passed afterward. Coverage includes
maximized startup on differently sized adjacent monitors, external focus, and
returning to an explicitly oversized column. The upstream non-compact behavior is
preserved. Logs: `build/startup-regression-before.log`,
`build/startup-regression-after.log`, and `build/startup-fix-verification.log`.

The isolated hardware runner is `scripts/qa-startup.py`; it launches only the
fixture allowlist using fresh QA storage, leaving personal application windows
outside the engine scope. Its maximized fixtures exercise startup, external reveal,
pause/recovery, and restart. Hardware results are recorded separately below.


Final optimized, certificate-signed hardware run:
`build/qa/startup-fix-20261022-8/summary.json` — **passed**, with nine native checks
in the single-strip run and nine in the dual-monitor run. Four maximized fixture
windows were revealed individually in the first run, and all eight across the
2560 × 1440 external monitor and 1728 × 1117 built-in display in the second.
The excluded sentinel stayed unchanged; pause restored original frames; restart
and a second pause completed without retained recovery data. Menu opening and
the real settings switch were exercised through external native automation.
Earlier failed receipts remain in runs 1–7; they stopped at automation setup or
switch activation before testing the geometry. The final driver reads the actual
switch's external AX bounds and clicks its center from a separate process.

`scripts/verify.sh` passed: formatting, Clippy, 485 default-feature engine tests,
402 no-default-feature engine tests, library tests, and 26 Swift tests. Build and
signature verification passed. The hardware-tested engine SHA-256
`ebcccd2e4f7f434e2f525e27f877c6ac6c47fea67688eefc3075e348600e197d`
matches the installed `/Users/neat/Applications/Ribbon.app` executable. The app is
left paused; no unrestricted engine was started for QA and no personal Claude or
Codex session was rearranged as a test. Public GitHub release assets were not
replaced.

Reproduce the isolated startup checks, with two displays and Ribbon quit:

    python3 scripts/qa-startup.py "$HOME/Applications/Ribbon.app" "$PWD/build/qa/fresh-startup-run"

## Directional fill and dual-display motion — 2026-10-22

See [navigation-motion.md](navigation-motion.md) for the seam/presentation fix,
native focus scheduling, geometry echo suppression, final exit restoration,
design review and timing limits. `scripts/verify.sh` passed: 490/407 engine tests,
46/39 library tests, 26 Swift tests, formatting, strict Clippy and package checks.
The installed signed engine is
`b338c886569f347da02a5713bdd69bc11e88e413b2d996792d3056d5e7ae7c80`.
Physical native navigation checks pass on both connected displays, including
24 Control–Option arrow changes, external activation of eight parked tiles,
visible neighbors after centering, seam containment in 60 Hz native-frame
samples, and immediate-stop restoration. The full settings/menu/lifecycle suite
passes nine checks each in `build/qa/navigation-startup-delivery/summary.json`.
Personal applications remain outside the automated engine allowlist. Raw samples
and screenshots are local ignored artifacts, not public repository assets.
