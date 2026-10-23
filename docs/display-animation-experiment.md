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
  --qa-fixed-content --qa-dual --qa-profile \
  --qa-output "$PWD/build/qa/animation-legacy-FRESH/report.json"

mkdir -p build/qa/animation-clock-FRESH
open -n -a "$CANDIDATE_APP" --args \
  --qa-fixed-content --qa-dual --qa-profile --qa-display-clock \
  --qa-output "$PWD/build/qa/animation-clock-FRESH/report.json"
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
