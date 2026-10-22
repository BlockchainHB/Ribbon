# Native geometry performance

The Rust engine remains the only owner of layout, focus and presentation. The
performance pass preserves width presets, pairing, stacks, exclusions and recovery.

## Implementation

- Read position and size together using Apple's
  `AXUIElementCopyMultipleAttributeValues`. Validate types, finite coordinates and
  positive dimensions before replacing cached geometry. Confirmed unsupported
  batching falls back for that window's lifetime; transient errors retry batching.
- Sample intermediate geometry at the owning display's cached refresh interval.
  New intent and exact endpoints bypass sampling. No command delay, sleep or
  duplicate layout state is introduced. Unknown refresh information uses 120 Hz.
- Consume actual elapsed animation time after slow native work. Retarget from the
  last emitted frame, retaining bounded velocity; this avoids a jump on reversal
  between display samples.
- Preserve shrink → ordered move → verify → grow. Park departures first, move
  visible leaders next, and reveal incoming windows last, preventing a returning
  neighbor from covering the window moving aside.
- Keep native focus coalesced while its target is compact-parked. Geometry proceeds
  immediately; focus rejection timing starts only when native focus is dispatched.
- Skip a duplicate parking read when the existing verification pass reads that
  same frame. Leave layout packing alone: measured packing consumed about 20 ms
  versus seconds in native size calls.

## Controlled comparison — 22 October 2026

All four alternating runs used the **same signed engine bytes**. The opt-in
comparison mode disables only batching and refresh sampling; visibility, focus,
resize and recovery safeguards are identical. No compiler ran during measurement.
The external monitor reported 2560 × 1440 points at 60 Hz; the built-in display
reported 1728 × 1117 points at 120 Hz, both at 2× backing scale.

Each run creates eight disposable AppKit windows restricted by an explicit
`dev.ribbon.fixture` allowlist. It retains ordinary original frames, expands the
eight windows through engine commands, injects 24 Control–Option arrow presses,
resizes/centers on both monitors, activates all eight hidden windows externally,
and restores the original frames. Native counters include startup, setup and
restoration. Values below are medians of two runs per mode.

| Measurement | Uncapped/sequential | Optimized | Reduction |
| --- | ---: | ---: | ---: |
| Native size writes | 9,958.5 | 2,243.5 | 77.5% |
| Native frame queries | 20,270 | 2,467.5 | 87.8% |
| Native position writes | 5,247 | 1,309 | 75.1% |
| Total active-frame work | 10.158 s | 4.402 s | 56.7% |
| Engine CPU before stop | 2.295 s | 1.550 s | 32.5% |
| Active-frame p95 upper bound | 6.50 ms | 6.75 ms | — |
| Key to first native write p95 upper bound | 9.25 ms | 9.75 ms | — |

This establishes less native work and lower engine CPU, **not lower input latency**.
Percentiles have 0.5 ms histogram buckets and only 24 keys per run. CPU is engine
process time from `ps` before graceful stop, not system, GPU or fixture CPU.
Active-frame work excludes event-loop waiting and exit restoration. Stage spans
overlap and must not be summed. A 60 Hz native-frame sampler cannot establish
compositor pacing or the redraw cost of busy Claude/Codex windows.

Every run passed all **16 native checks**, including neighbor visibility,
wrong-monitor body detection, hidden-window activation and exact recovery.
Additional suites passed 18 single-display and 20 dual-display checks, plus 14
pairing checks. These cover interrupted movement/resizing, 12 pt separation,
transfers, group reorder/ungroup, external activation, excluded scope and lifecycle.
Native light/dark overview captures were inspected. Unplug/reconnect and busy
third-party application redraw costs remain outside this fixture verification.

Evidence (ignored local artifacts):

- `build/qa/performance-comparison.json`
- `build/qa/perf-ab-{base,final}-{a,b}/`
- `build/qa/perf-desktop-verified/summary.json`
- `build/qa/perf-pairing-verified/report.json`
- `build/perf-final-verify.log`: fmt, strict Clippy, 501/418 engine tests,
  46/39 library tests and 26 Swift tests.

Verified engine SHA-256:
`883411609ccf9b5b265fff13fc039504ae2000d088442127ce887d52a97150ea`.

## Reproduction and instrumentation

With Ribbon paused and both monitors connected, use a fresh output directory:

```sh
RIBBON_QA_KEYBOARD=1 python3 scripts/qa-performance.py \
  "$PWD/build/qa/fresh-perf-run" "$HOME/Applications/Ribbon.app"

RIBBON_PERF_BASELINE=1 RIBBON_QA_KEYBOARD=1 python3 scripts/qa-performance.py \
  "$PWD/build/qa/fresh-comparison-run" "$HOME/Applications/Ribbon.app"

python3 scripts/qa-startup.py "$HOME/Applications/Ribbon.app" \
  "$PWD/build/qa/fresh-desktop-run" --general
```

`RIBBON_PERF_OUTPUT=/absolute/path/report.json` enables fixed-size histograms and
one atomic report on graceful exit. Disabled profiling registers no systems and
performs no measurement clock reads or report I/O. Reports contain no window
titles or content. Key latency ends at the first successful geometry setter,
not presentation; bursts use the latest receipt. `RIBBON_PERF_BASELINE=1` is
ignored without profiling and the report records the comparison mode.

QA reads existing logical widths to distinguish preserved preferences from a
neighbor's intentionally clipped native presentation. It still measures actual
native positions, exposed widths, movement, focus, scope and restoration.
Historical failed candidates remain separate and are not counted as passing.
