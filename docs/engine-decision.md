# Engine decision — 20 October 2026

Use the pinned Paneru 0.5.2 source as the first beta engine. The narrower
scrolling model, MIT source and existing column/gesture/session tests fit this
product better than adopting Rift's multiple layout engines and larger UI.
Rift remains the alternative if physical desktop validation exposes a blocking
Paneru limitation.

Before local modifications, both snapshots built and passed their deterministic
tests on this Apple silicon Mac running macOS 27.0.1:

| Source snapshot | Result |
| --- | --- |
| Paneru 12c58b2225a4 | 46 library tests + 439 binary tests passed |
| Rift f5717097a217 | 869 library tests passed |

These are build/test results, not comparative runtime benchmarks. No general
latency superiority is established. The local Paneru fork adds exact application
scoping, parent lifetime handling and restoration of original frames. Its
verification is recorded separately from the upstream baseline.

The GUI does not contain layout geometry. Engine configuration is generated from
validated native settings, and scope is independently enforced inside the engine.
The fixture and excluded-sentinel apps exercise real native windows while
leaving other applications outside the tested scope.
