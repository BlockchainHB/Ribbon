# Display-aware animation experiment

23 October 2026. The user approved implementing the strongest candidate from
[animation research](animation-research.md). The smooth installed fixed-content
build stays intact while a separate signed candidate is prepared for comparison.

## Behavior and scope

The engine accepts `RIBBON_ANIMATION_CLOCK=display-link` as an opt-in experiment.
Unset, `legacy`, or unrecognized values keep the existing animation timing.
This is not a saved preference or a settings control. The existing bounded
Hermite curve, duration, velocity handling, integer geometry, full native content
size, ordered commits and focus/recovery rules are preserved.

- `platform/animation.rs` owns main-thread `NSScreen` display links. It requests
  the owner's cached mode cadence within the screen's maximum rate, registers
  on the runloop the existing Cocoa pump uses, coalesces callback signals and
  wakes that pump through the existing app-local `EventLoopWaker`.
- The ECS derives moving displays from canonical strip membership and motion
  markers. No layout, widths or order are copied into the platform clock.
  Links are invalidated when motion stops, displays disappear/change rate, or
  the platform object is destroyed. Native resources remain on the main thread.
- Each frame consumes a set of owner ticks. Motion emits intermediate geometry
  only for its owner's tick, avoiding the second elapsed-time sampling cap.
  New intent and exact endpoints still bypass sampling. Gesture input keeps its
  existing immediate processing and native modifier-scroll momentum handling.
- A link's missing-callback watchdog expires after two owner periods. If a
  screen cannot be matched, an absolute owner-period deadline provides timer
  fallback. Missed periods are skipped; there is no catch-up write burst. The
  fallback does not establish display synchronization or a delivery guarantee.
- Idle event backoff, flash-message and projection-attachment handling retain
  their existing behavior when no geometry motion needs a clock.

Neither dependencies nor the upstream pin changed. Fractional presentation,
new easing, app-specific policies, snapshot animation and atomic space
transactions are outside this experiment.

## Projection-aware profiling

`RIBBON_PERF_OUTPUT=/absolute/path.json` remains opt-in. Report version 2 adds:

- Actual projection transform, clip and visibility call counts and durations,
  including their contribution to first-geometry-call latency. The return from
  a native call is not proof that pixels have been presented.
- Cocoa wait duration and active frame intervals, alongside existing frame work
  which excludes the Cocoa wait. Consecutive active frame starts are measured;
  the first interval after idle is excluded.
- Full native resize round trips and enhanced-UI acquire/restore spans. Spans
  overlap and must not be summed.
- Per-display callback and consumed-tick interval histograms. Histograms retain
  counts/costs but reset their last timestamp when the display clock stops, so
  time spent idle does not contaminate animation intervals. At most 32 distinct
  display IDs are retained per process. First ticks have no invented interval.
- `animation_clock` identifies the selected experiment mode. It is independent
  of the older `RIBBON_PERF_BASELINE` batching comparison; do not combine those
  switches for a pacing A/B.

Counters include startup and restoration. Frame intervals and callback timestamps
are engine-side measurements, not compositor frame times. No titles, content,
per-frame files or persisted clock state are introduced. Disabled profiling adds
no measurement clock reads, display-sample allocation or report I/O.

## Verification and candidate

The actual Rust display-link module, existing `EventLoopWaker`, and existing
Cocoa pump were exercised together in a windowless standalone process, using
the pinned release dependencies. Three rounds delivered callbacks and consumed
ticks on both connected 60/120 Hz displays. Each round then removed every clock
and confirmed **zero callbacks after idle**. This uses no engine, windows,
Accessibility, screen capture or system input. It validates the native callback
signature, runloop wake integration, coalescing and cleanup, not live app smoothness.

Final native receipt: `build/research/animation-20261023/native-clock-b/`, including
the generated exact-source probe, report and source hashes. After subsequent
source changes, use a fresh directory and retain the matching receipt. The final
receipt hashes match the current platform and native clock source. The earlier
`native-clock-a` receipt is retained.

`CARGO_INCREMENTAL=0 scripts/verify.sh` passed for the candidate product source:
formatting, strict Clippy, **516/433 engine**, **46/39 library** feature suites
(overlapping), **26 Swift** tests, config/signature and whitespace checks. Log:
`build/research/animation-20261023/verify-candidate.log`. Added coverage exercises
owner-only sampling, immediate intent/endpoints, missing ticks, long stalls and
full-schedule resize/stack/reorder separation. Replaying the production curve
also passes all 44 research scenarios in `motion-candidate/`.

```sh
python3 scripts/research-animation-native.py build/research/animation-FRESH-native
scripts/verify.sh
scripts/build-app.sh
```

Source checks and native receipts must be matched to the actual final candidate
before claiming a passed result. Read `build/artifacts.json` for the signed
candidate path; it is not automatically installed or a notarized public release.

## Controlled native comparison

The signed app understands QA-only `--qa-profile` and `--qa-display-clock` flags.
Only the existing isolated `--qa-output` session accepts those choices. It always
uses the fixture allowlist/service/state and explicitly selects legacy timing
unless `--qa-display-clock` is supplied. Normal settings are not modified.

With Ribbon paused, two monitors connected, and a safely idle unlocked desktop,
use the same signed app bytes for both cases and a fresh directory each time:

```sh
mkdir -p build/qa/animation-legacy-FRESH
open -n -a "$CANDIDATE_APP" --args \
  -ApplePersistenceIgnoreState YES \
  --qa-fixed-content --qa-dual --qa-profile \
  --qa-output "$PWD/build/qa/animation-legacy-FRESH/report.json"
open -a "$CANDIDATE_APP"

mkdir -p build/qa/animation-clock-FRESH
open -n -a "$CANDIDATE_APP" --args \
  -ApplePersistenceIgnoreState YES \
  --qa-fixed-content --qa-dual --qa-profile --qa-display-clock \
  --qa-output "$PWD/build/qa/animation-clock-FRESH/report.json"
open -a "$CANDIDATE_APP"
```

Run cases sequentially, finish cleanup and quit only the owned QA app between
cases. Set `CANDIDATE_APP` from `build/artifacts.json`. Add `--qa-pairing` for
pairing gates and run the prepared `--qa-oversized` case separately. The normal
user session must not be interrupted to run these commands.

Profiling uses warning-level logging in both cases. Each engine launch writes
its own `session/performance-N.json`, preserving the main run when lifecycle QA
restarts the engine. Report JSON records the engine SHA-256, display topology,
checks and chosen clock. Keep all raw desktop evidence local.

Alternate A/B/B/A, keep one variable and compare translation and deliberate
resize costs separately. Required gates include stable native content dimensions,
independent ownership, no neighbor spill, interrupted resize/reversals, focus,
pairing, exclusions, restoration and idle cleanup. Inspect latency and gap tails
as well as CPU/native call counts. Existing 60 Hz native frame samples prove
geometry only; 120 Hz delivery needs separate compositor/physical evidence.
Do not enable the experiment by default or replace the user's smooth installed
build based solely on source tests or callback frequency.

## Native comparison results — 23 October 2026

**Keep legacy timing as the default.** The display-link candidate passes the
normal content/focus/pairing gates, but this workload shows a resize-cost tradeoff
large enough to withhold promotion. No installed build was replaced.

All measured cases used the exact same certificate-signed release-profile engine
from `e4bff50bfda374d78c44376b33d272390a4f1513`, SHA-256
`d1350081aa20178b4e0bf1d30e66fe2f73989710c9fe8ddf0a7956bce2d005f0`.
The external monitor was 2560×1440 / 60 Hz; laptop 1728×1117 / 120 Hz; both 2×.
The user explicitly authorized the paused, unlocked two-monitor interval.

- A/B/B/A: `legacy-a`, `clock-a`, `clock-b`, `legacy-b`. Each passed all **11
  native checks**, in approximately 20.5–20.7 seconds. These repeated checks
  cover fixed native content dimensions, native anchor ownership, independent
  public WindowServer geometry, visible focus, interrupted width changes,
  exclusions, restoration and start/pause/start. They are not 44 unique checks.
- Separate `clock-pairing`: all **21 checks** passed, including pair ratios,
  reordering, hidden activation and ungrouping. It is excluded from performance
  comparisons because its workload differs.
- Separate `clock-oversized`: failed the **fixture setup precondition** before
  oversized focus was exercised. It is not a focus pass or an engine-regression
  result. The fixture reported zero native minimum widths, including windows
  intended to exceed their monitor's width.
- All owned engine, QA app, fixture and sentinel processes stopped after the
  runs. The installed engine remains
  `2aca30607c21133066dc1a5f23d5dd7c5ccaacef07800089c91d47e997d0a58d`.

Median of two runs per mode, using each main session's `performance-1.json`:

| Engine-side measure | Legacy | Display-link | Change |
| --- | ---: | ---: | ---: |
| Active engine frames | 1,247 | 892.5 | −28.4% |
| Total active-frame work | 966.9 ms | 1,166.2 ms | +20.6% |
| Per-run p95 active-work upper bound | 3.75 ms | 6.25 ms | +66.7% |
| Per-run p99 active-interval upper bound | 18.75 ms | 17.00 ms | −9.3% |
| Native size calls | 187 | 195 | +4.3% |
| Total native resize round trips | 542.3 ms | 803.2 ms | +48.1% |
| Projection transform calls | 1,022.5 | 1,090.5 | +6.7% |

Fewer engine frames do not establish lower work or CPU. Active-work spans include
native waiting; they exclude the event-pump wait. Resize, guard and frame spans
overlap. Native counts include startup, setup and restoration, so this does not
isolate the deliberate-resize phase or establish why its aggregate cost rose.
The table's percentile entries are medians of **per-run histogram upper bounds**,
not pooled exact percentiles. Buckets are 0.5 ms and only two repetitions were run.

Laptop callback and consumed-tick p50/p95 upper bounds were 8.5 ms in both clock
runs. External p50/p95 upper bounds were 17 ms. Individual callbacks still stalled
during native work. These timestamps do not prove physical 120 Hz delivery.
This IPC-driven workload generated **zero key-receipt latency samples**, so no
input-latency improvement is claimed. The external CPU sampler missed the first
baseline session and records only last-observed pre-exit CPU; it is insufficient
for a controlled CPU conclusion. Busy third-party app rendering remains untested.

Receipts, all local and excluded from source control:

- `build/qa/animation-ab-20261023-b/{legacy-a,clock-a,clock-b,legacy-b}/`
- `build/qa/animation-ab-20261023-b/clock-pairing/`
- `build/qa/animation-ab-20261023-b/clock-oversized/` (failed precondition)
- `build/qa/animation-ab-20261023-b/comparison.json` (aggregated values/limits)
- `build/research/animation-20261023/comparison-b.log`, `cpu-samples-b.json`
- `build/qa/animation-ab-20261023-a/` and `qa-launch-sample.txt`: preserved initial
  launch timeout, no fixture engine started. The QA window's task did not run;
  using process-local ignored restoration state plus an explicit reopen made
  subsequent launches enter the harness. This is not a performance sample.

The most useful follow-up experiment would separate pure projection movement
from native AX resize pacing and record phase-specific geometry/latency before
changing either. The current evidence supports neither default enablement nor
removing resize correctness guards.

### Oversized fixture correction and focus retest

A hidden, never-ordered-front AppKit probe reproduced the failure: with empty
`NSHostingView.sizingOptions`, deferred layout changed a manually assigned
2,760-point minimum to zero. The corrected fixture supplies the oversized
SwiftUI minimum and uses `.minSize` sizing for that opt-in case, starting with
an oversized frame. The hidden probe retains the minimum through deferred layout;
ordinary fixture sizing options remain unchanged.

Proofs: `hidden-minimum-deferred-proof.json` and `hidden-minimum-fixed-proof.json`
under `build/research/animation-20261023/`. This verifies the fixture setup
mechanism without showing a window or interrupting normal use. The A/B and pairing
passes above belong to the signed `e4bff50` bundle, before this fixture correction.

The user then explicitly requested the full focus retest. The corrected fixture
on `66608f7` passed native focus on **both monitors**, but its legacy-mode run
failed during pause/recovery. Independent fixture readback showed that the engine
had already restored both oversized frames exactly (2,760 points on the external
display, 1,928 on the laptop). Swift recovery nevertheless requested smaller
display-fitted widths, then retained its journal when native minimums refused.
Failed receipt: `build/qa/animation-focus-20261023-a/legacy-focus/`.

`74fef1f` fixes that false recovery debt: accept a matching saved oversized frame
whose center is on a connected display. Normal, unrestored, new and disconnected
windows retain the existing fit policy. Four Swift regressions cover these
boundaries. `oversized-recovery-final-verify.log` records passing formatting,
strict Clippy, 516/433 engine, 46/39 library and **30 Swift** tests. The signed
release-profile candidate's source, signature and engine hash were checked.

Final desktop retest: **legacy and display-link modes each passed all 9 checks**,
including genuine oversized native minimums receiving stable native focus on
each owner monitor, unchanged content size during focus, exclusions, exact frame
restoration, cleared recovery journal and start/pause/start. Each run took about
6.3–6.5 seconds. Both used source
`74fef1fb5519ffe884ade98444fa18775bc54c5c`, signed engine SHA-256
`4f809d9fa98e48413ce5e4baf5fd610f3777e267621214f61fe0ebae83a0cf51`.

Final receipts: `build/qa/animation-focus-20261023-b/{legacy-focus,clock-focus}/`;
runner log `build/research/animation-20261023/focus-retest-b.log`; signed build
receipt `signed-oversized-recovery-candidate.json` in that research directory.
All owned test processes stopped, and the installed app remains unchanged.
These are native geometry/focus/lifecycle results, not new performance or
compositor-delivery evidence. The experimental clock remains off by default.
