# Scroll and resize animation research

Checkpoint: 23 October 2026. The user reports the installed fixed-content build
feels smooth and requests a deep research phase after compacting the conversation.
Preserve that working behavior. Investigate measurable wins before changing the
current animation feel or installing another build.

## Baseline and current work

- Installed: `~/Applications/Ribbon.app`, normal Developer ID signed release build
  from `c34fb9ac5c29ead3e4c8e1eef596d11e386b8f6c`, engine SHA-256
  `2aca30607c21133066dc1a5f23d5dd7c5ccaacef07800089c91d47e997d0a58d`.
- Exact release engine passed 21 native two-monitor checks. Independently launched
  live WebKit fixtures passed 50 motion observations per direction, unchanged
  content viewport and resize-event count, advancing animation frames, no
  neighboring-monitor spill in guarded physical display captures.
- User subsequently enabled Ribbon and reported it is smooth. Latest read found
  a running engine. Do not stop the active session to run fixture tests.
- Branch `fix/stable-native-content`, PR https://github.com/BlockchainHB/Ribbon/pull/8.
  Last committed head before this checkpoint: `06661f24b3bd7c0466d4923bef8baa761c2b5470`.
  No merge or public release. The final docs-only commit does not change the
  installed product code from `c34fb9a`.
- One valid review finding remains in progress:
  https://github.com/BlockchainHB/Ribbon/pull/8#discussion_r4365004406.
  Oversized native minimums can stay projected after settling and previously
  waited forever for focus. Local correction allows focus only after the owner
  strip and window settle, with the oversized native source safely anchored on
  its owner. Ordinary partial windows still wait for ordinary coordinates.
- That correction and a regression pass local source verification: strict
  formatting/Clippy, 511/428 engine tests, 46/39 overlapping library suites and
  26 Swift tests. The signed diagnostic build also completed. They remain
  uncommitted at this checkpoint, with a signed diagnostic build prepared.
  `build/research/oversized-final-verify.log` and `oversized-focus-test.log` contain
  results. CI is green at committed head `06661f2`; the local correction has not
  been pushed or reviewed yet. Recheck live Git rather than assuming status.
- New native QA support: `--qa-fixed-content --qa-oversized --qa-dual --qa-output
  FRESH/report.json`, creating one genuine oversized native minimum per monitor.
  This has **not run yet** because the user is now using Ribbon. It must use an
  unlocked, safe fixture interval with the normal engine paused. Never start an
  unrestricted engine as automated QA. The installed smooth build remains unchanged.

The outstanding files are `ecs/{focus,params}.rs`, native
`DesktopVerification{,+Oversized}.swift`, `SessionController.swift` and
`RibbonFixture/FixtureApp.swift`. Keep the pre-existing untracked
`docs/workspace-location.md`, `docs/workspace-move.json`, `scripts/qa-pairing.py`.

## Research questions grounded in current source

1. **Animation wake cadence after projection.** `ecs/systems.rs::pump_events`
   adaptively backs its Cocoa wait up to 16 ms while frames are active.
   `ecs/motion.rs::MotionCadence` samples at the owner's reported refresh rate.
   Projection changes WindowServer presentation without normal AX move echoes.
   Measure whether losing those echoes lets the pump back off toward 60 Hz on
   the 120 Hz laptop, especially in the tail. A display sampling cap alone does
   not schedule frames. This is a hypothesis, not measured compositor evidence.
2. **Fractional presentation movement.** `Motion` retains `DVec2` positions and
   velocity but rounds emitted positions to `IVec2`; compositor translation
   currently takes integer offsets even though its native transform uses doubles.
   Measure visible quantization at 2× scale before considering fractional
   presentation offsets. Keep logical layout ownership in Rust.
3. **Resize cost and synchronization.** Width changes intentionally resize app
   content. Profile the ordered shrink → move → grow sequence and parallel AX
   workers with busy content. Separate native size-write cost, frame-read cost,
   retargeting and actual rendering. Never restore per-edge content squeezing.
4. **Retargeting and easing.** Current bounded Hermite motion keeps velocity,
   starts retargets at the last emitted native frame, clamps tangent to prevent
   overshoot, and has duration `min(3.2 / rate, 0.3)` (about 229 ms at rate 14).
   Compare reversals, rapid input, small deltas and mixed width/position changes.
   Preserve responsiveness and exact settling; do not replace the feel on taste alone.
5. **Cross-window frame consistency.** Investigate whether sequential transform
   updates within an engine frame create observable inter-window timing skew,
   and whether a supported/native transaction mechanism can improve it. Use
   independent physical readback; foreign-call success or caller-local bounds
   have produced false positives in this investigation already.

## Method and acceptance

- Start with current repository motion/scroll/platform code and pinned Paneru,
  then primary upstream source and Apple documentation. Firecrawl CLI is
  available; its skill was used for the earlier research. Keep citations and
  dates/pins. Distinguish other compositors' math from applicable macOS APIs.
- Gather the baseline before tuning. Use release builds, paired same-binary A/B
  runs, one independent variable, warmups, repeated trials on each monitor.
- Record update intervals, missed deadlines, completion/retarget latency, p50/
  p95/p99 work costs, CPU and native writes. Confirm unchanged content dimensions,
  independent strips, focus, pairing, reversals and pause/recovery.
- A 60 Hz NSWindow sampler proves geometry only. App animation-frame callbacks
  also do not prove display delivery. Use appropriate physical/compositor
  evidence before claiming 120 Hz improvement.
- All desktop tests stay fixture-only, exact bundle allowlist, isolated service/
  state and fresh private output directory. Preserve failed receipts, restore
  frames and stop owned processes. Do not capture personal windows, reset TCC,
  alter security/display arrangement, or interrupt the active user session.
- This phase is research and isolated experiments, not production animation
  tuning. Keep experiments gated and the installed smooth baseline intact.
  Report ranked opportunities, evidence, expected benefit, risks and rejected
  ideas before proposing production changes. No speculative dependency churn or
  broad refactor.

Relevant entry points: `vendor/paneru/src/ecs/{motion,scroll,systems,projection}.rs`,
`manager/{projection,windows,frame,display}.rs`, `performance.rs`,
`scripts/qa-performance.py`, native `DesktopVerification+{FixedContent,Motion}.swift`.
Read `HANDOFF.md`, root `AGENTS.md` and `vendor/paneru/AGENTS.md` first on resume.

## Research results — 23 October 2026

**Recommendation:** preserve the installed content behavior and current easing.
The strongest candidate is display-aware scheduling with one sampling decision
per display tick. Improve projection/resize measurements before testing that
candidate in the engine. Half-point presentation is a smaller, later experiment.
There is no evidence here that replacing the animation curve would help.

This phase changed no production animation code, configuration, installed bundle,
or dependencies. The existing oversized-focus correction remains separate and
uncommitted. No desktop windows were moved or captured. These results come from
source analysis, windowless Cocoa experiments and execution of the exact pure
production motion implementation. They do **not** establish a delivered frame
rate or a new improvement in Codex, Claude, Dia or T3.

### 1. A display sampling limit is not an animation clock

`ecs/systems.rs::pump_events` starts near a 2 ms wait after an event and increases
the wait during quiet frames. Its active branch is `min(timeout, 16) + 1`, so it
eventually requests **17 ms**, before schedule/native work and OS timer delay.
`MotionCadence` limits writes to an owner's nominal refresh interval but cannot
wake the event loop. Ordinary fully visible moves still generate AX writes and
may wake it sooner; partial/hidden projected moves can update only presentation.
How often the quiet path occurs in a real mixed strip remains unmeasured.

The checked-in probe reproduces this active/drained recurrence using the same
`NSApplication.nextEvent` wait-and-drain structure. A comparison computes the
remaining time to an absolute 60/120 Hz deadline, subtracting elapsed work.
It keeps the same Cocoa event pump. Work is simulated on the probe's own thread;
it is **not** an AX/application rendering measurement.

Final run: three alternating repetitions per condition, 1.2 seconds each,
first 20 intervals excluded. The table reports the median of each trial's p50
and p95; these are not pooled percentiles or compositor frame times.

| Simulated work per update | Current wait p50 / p95 | 60 Hz deadline p50 / p95 | 120 Hz deadline p50 / p95 |
| --- | --- | --- | --- |
| 0 ms | 20.82 / 21.39 ms | 16.66 / 19.09 ms | 8.34 / 8.98 ms |
| 2 ms | 22.38 / 23.37 ms | 16.66 / 17.28 ms | 8.34 / 9.39 ms |
| 6 ms | 26.67 / 27.70 ms | 16.66 / 16.76 ms | 8.33 / 8.72 ms |

This reproduces a scheduling weakness under quiet conditions. It does not mean
the installed Ribbon normally runs at the reciprocal of those intervals. A
deadline is also not display synchronization, and a workload exceeding the
display budget cannot be fixed by changing its timer.

### 2. Display links work, but must end the Cocoa wait

Apple provides `NSScreen.displayLink(target:selector:)` on macOS 14+, within
Ribbon's supported OS range. The probe obtained callbacks on both connected
screens: external 2560×1440 / 60 Hz, laptop 1728×1117 / 120 Hz, both 2× scale.
In the final run their median callback intervals were approximately 16.6 ms and
8.33 ms. The external callback p95 varied between runs; requesting a rate is
not a guarantee of callback or pixel delivery.

There is an integration trap: callbacks execute while `nextEvent` waits, but
do not themselves make it return. With a 100 ms wait the probe saw only **11
pump returns** in about 1.1 seconds while display callbacks continued. Having
each callback post an event to **its own application queue** increased returns
to **67 external / 133 laptop**, with no system input or foreign windows.

Use the existing coalesced `EventLoopWaker` concept for a future engine trial;
merely installing a display-link callback would leave the schedule asleep.
Keep the callback tiny and all native work on the main thread. `objc2-quartz-core`
is already pinned; this does not require a new rendering framework.

### 3. Avoid applying two separate frame caps

The pure-motion probe compiles the actual `Motion` struct/implementation from
`ecs/motion.rs`, rather than a rewritten approximation, against the existing
release `bevy_math` library. It passed **44 scenarios**, checking exact endpoints,
bounds and monotonic movement within each direction, including reversals at
80 ms. Tests use rate 14, 60/120 Hz, distances 1–1800 points, frequent 1 ms
updates, and real interval traces from the windowless clock probe.

One 512-point, 120 Hz replay illustrates why the clock and sampling need to be
considered together:

| Driver / sampling | Changed integer outputs | Endpoint time |
| --- | --- | --- |
| Current quiet-loop trace + existing sampling | 16 | 247.35 ms |
| Absolute-deadline trace + existing sampling | 19 | 234.28 ms |
| Same deadline trace, one output decision per owner tick | 26 | 234.28 ms |

The third case passes `interval = 0` to the **unchanged** production curve only
because that isolated driver already selects owner ticks. It is not a proposal
to remove all native rate limits. Existing `since_output` phase and real wake
variation can otherwise hold a sample for another display interval. The same
effect appeared at 60 Hz (12 versus 14 changed outputs on its deadline trace).
These are illustrative single-trace outputs, not paired physical A/B results.

A candidate must preserve immediate new intent, independent monitor rates,
exact endpoints and native-work limits. Use one display tick/phase decision for
the strip's geometry; don't let input-driven updates produce redundant AX
resizes. The event loop must remain interruptible for real input. A fixed sleep
after every frame would add native work to the frame period and is rejected.

### 4. Smaller opportunity: one physical pixel instead of one point

The current motion curve retains fractional positions, but emits whole points;
scroll constraints and projection offsets are also integers. At 2× scale this
means visible position steps have a minimum grid of two physical pixels.

At ideal 120 Hz, a 12-point transition produced 12 distinct changed positions;
rounding the **same** curve to half points would produce 20. Its RMS grid error
would fall from 0.271 to 0.139 points. A 512-point transition had 27 changed
positions on either grid: the benefit is concentrated in small moves/tails.
A one-point transition first changes its integer output at 75 ms and retains
its motion marker until the endpoint near 233 ms.

This is mathematical evidence only. It has not proved that native projection,
input hit testing, capture or reveal can share fractional presentation correctly.
If investigated, snap to the owner's backing-pixel grid (half points only on 2×),
retain Rust's canonical logical sizes/order, and keep all members on a coherent
strip offset. Using arbitrary fractional transforms could blur text. Switching
between a fractional projection and ordinary integer AX positioning could itself
introduce a small discontinuity. Do not change preferred widths to implement it.

### 5. Resize work needs better attribution before tuning

Deliberate width changes still resize real app content. The source already
deduplicates equal native sizes, batches frame reads, suppresses enhanced-UI
animation with a PID-scoped guard, commits shrink → ordered move → grow, reads
actual geometry and repairs projected anchors after resizing. Parallel AX calls
to windows of one app may still queue behind that app's main thread. The
windowless 6 ms experiment does not measure any of those costs.

The current profiler has important gaps after the projection change:

- `position_write` / `size_write` and `geometry_written()` cover AX setters;
  compositor-only `Projections::present`/`translate` calls are absent. Therefore
  a projection-only key can have no first-geometry latency sample, and native
  write counts omit real presentation work.
- Active-frame work deliberately excludes event-loop waiting. It cannot reveal
  long gaps between otherwise cheap engine frames.
- The existing aggregate grow/move/shrink spans do not separate enhanced-UI
  flag access, app-specific AX round trips, callback cadence, or commit skew.
- Existing performance receipts predate projection. Their CPU reductions are
  historical, not a fresh baseline for this backend.

The first engine experiment should add bounded opt-in measurements for wake /
schedule / first projection commit times, projection call counts and cost,
active inter-update gaps by owner display, and stage-specific resize work.
Keep reports free of titles/content and avoid per-frame disk writes. Separate
scroll-only and intentional-resize comparisons. Raising effective resize update
frequency may increase app reflow/AX work, even if translation becomes smoother.
Only measure PID-wide guard batching or native resize coalescing if those costs
show up; don't widen a guard's restoration lifetime on a guess.

### Upstream and other implementations

- [Pinned Paneru 12c58b2](https://github.com/karinushka/paneru/blob/12c58b2225a40e434053ea9343a41e2012466f9a/src/ecs/systems.rs)
  and [current main b9785a1](https://github.com/karinushka/paneru/blob/b9785a13154e94f6a9b57e15de5287f039927e3f/src/ecs/systems.rs),
  checked 23 October, retain the same adaptive wait. Their animation uses rounded
  exponential interpolation with a 5-point endpoint snap and a capped timestep.
  Ribbon already has fractional internal motion, bounded completion and velocity
  retention. Updating the upstream pin is not supported as an animation fix.
- [Apple's NSScreen API](https://developer.apple.com/documentation/appkit/nsscreen/displaylink(target:selector:))
  and [WWDC23 AppKit, 12:00–13:24](https://developer.apple.com/videos/play/wwdc2023/10054/?time=720)
  establish the supported display-aware callback and stopping its activity after
  animation. [Frame-rate range documentation](https://developer.apple.com/documentation/quartzcore/cadisplaylink/preferredframeraterange)
  says to choose a sustainable range; the actual available rate can vary with
  system policy. The installed SDK headers confirm macOS availability and
  main-runloop registration. Avoid relying on iOS-only code samples on generic
  display-link pages for the macOS constructor.
- [Niri's pinned animation](https://github.com/YaLTeR/niri/blob/e19df12cf81ffe805609fee497da1a097066ad2f/src/animation/mod.rs)
  and [shared clock](https://github.com/YaLTeR/niri/blob/e19df12cf81ffe805609fee497da1a097066ad2f/src/animation/clock.rs)
  use floating-point values, a shared lazy time sample and configurable easing /
  springs / analytic deceleration. These are useful design comparisons, not
  macOS APIs. Bevy already supplies a shared time sample for Ribbon's systems.
  Niri's spring support is not evidence that Ribbon should change its feel.
- [Yabai dd84572](https://github.com/asmvik/yabai/blob/dd845723416f5fe92af49fad5ebab00369e07edd/src/window_manager.c)
  drives animation with a display link and transactions, but transforms its own
  captured proxy windows and swaps them with real windows. That does not prove
  atomic transforms of Ribbon's app-owned spaces or foreign live content.
  Snapshot scaling would freeze/distort live content during resize and adds
  capture machinery; it is unsuitable for this user's content-stability goal.
  No new foreign-window transaction API was independently validated in this phase.

### Ranked outcome and bounded implementation brief

1. **Highest priority:** opt-in projection-aware timing, then a gated per-display
   tick/deadline trial. Strong source/windowless evidence; physical benefit and
   CPU/app cost still need validation. Preserve the curve, full native content
   size, ordered commits and immediate input wakeups.
2. **Second:** backing-pixel presentation for small translation moves. Measured
   mathematical benefit, larger coordinate/reveal/hit-test risk. Do not couple it
   to the first timing experiment.
3. **Conditional:** reduce genuine resize overhead only after attribution.
   There is no new measurement supporting fewer safety reads, broader guards,
   a lower/higher fixed resize rate, or app-specific exceptions.
4. **Defer:** native transactions for multiple spaces until an independent
   fixture proves both behavior and pixel consistency. Caller-local success
   and proxy-window examples are insufficient.
5. **Preserve:** bounded Hermite easing, retargeting and native modifier-scroll
   momentum handling. No spring swap, global speed increase, per-edge resize,
   snapshot animation or unrestricted engine experiment is justified here.

An eventual same-release-binary A/B should alternate at least A/B/B/A on each
display, separately for projected scrolling, fully visible navigation, width
changes, interruptions/reversals, and busy live WebKit. Keep one independent
variable, warm up, record latency/gap distributions and engine/app CPU, and run
the existing native correctness gates. Add 120 Hz-capable physical/compositor
evidence before claiming 120 Hz delivery. Run only during a safely paused,
unlocked fixture interval; this phase did not run those tests.

### Reproduction and local receipts

From the repository root, with existing release dependencies available:

```sh
mkdir -p build/research/animation-FRESH
swiftc -warnings-as-errors -parse-as-library scripts/research-animation-clock.swift \
  -o build/research/animation-FRESH/animation-clock
build/research/animation-FRESH/animation-clock \
  build/research/animation-FRESH/clock.json
python3 scripts/research-animation-motion.py \
  build/research/animation-FRESH/motion \
  --clock build/research/animation-FRESH/clock.json
```

Both probes refuse to overwrite receipts. Neither launches an engine, creates
windows, uses Accessibility/capture, or sends system input. The clock probe runs
for about 40 seconds and briefly simulates work on its own thread. It creates
only its own process's application-defined wake events. Display links are
invalidated before exit. The motion probe records its generated exact-source
probe, source SHA-256, clock hash and CSV samples for inspection.

- Final clock: `build/research/animation-20261023/clock-b.json`, 27 trials /
  2,469 loop intervals plus display callbacks. Initial shorter run `clock-a.json`
  retained; no results were discarded as failures.
- Final motion: `build/research/animation-20261023/motion-c/{summary.json,samples.csv,probe.rs}`.
  Earlier `motion-a`/`motion-b` retained. Final adds the explicit tick-only
  counterfactual and separates grid quantization from held-sample error.
- Production motion source SHA-256:
  `c7ec2cfc97412dc33051c97ba38390d47122fb04999168af55c2878114e747ce`.
- Primary-source snapshots: `.firecrawl/animation-*` (ignored local research).
- Swift probe compiled with warnings as errors; the Rust probe compiles optimized
  and all 44 direction/bounds/endpoint scenarios pass. No fresh full product
  verification or native QA is claimed for these research-only additions.
