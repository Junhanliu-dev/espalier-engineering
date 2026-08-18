# Pipeline Speed Benchmark — v0.21.1 → v0.22.0

> Measured 2026-08-18 on branch `feat/v0.22-pipeline-speed` (macOS, local).
> Two layers, kept honest and separate: **Part 1 is real wall-clock
> measurements** of every deterministic mechanism v0.22 changed (old hook
> taken from `main`, new hook from the branch). **Part 2 is a parameterized
> model** that composes those measurements with ASSUMED agent durations —
> agent spawns dominate pipeline wall-clock and cannot be cheaply
> benchmarked without burning real model runs. Every assumption is listed;
> the release's own Track A (`espalier-stats.sh` → Stage durations) exists
> precisely to replace the assumptions with field truth after real runs.

## TL;DR

| What | Before | After | Saved |
|---|---|---|---|
| Push-hook gate sections (measured, scaled fixture) | 21.15s | 12.17s (opt-in parallel) | **−42%** (sum → max) |
| Dependency audit per push (measured, 5s stub tool) | 5.2–5.7s every push | 0.20s warm cache | **−96%** on cache hits |
| Stage 3 exit gate build+lint (measured, 6s+3s) | 9.05s | 6.04s | **−33%** (sum → max) |
| Full feature run, typical 1-round (modeled) | ~27.9 min | ~21.0 min | **~6.8 min (−25%)** |
| Fix-lane run, 1-round (modeled) | ~21.6 min | ~16.5 min | **~5.0 min (−23%)** |
| Human round-trips | — | — | −1 per signal-carrying run, −1 post-CI deploy stall |

v0.22 with everything left at defaults (no opt-ins) measured **byte-equivalent
on the serial hook path** (21.16s vs 21.15s) — no regression when a repo
doesn't opt in.

---

## Part 1 — Measured (real wall-clock, repeatable)

Method: the v0.21 hook template was materialized from `main`, the v0.22 one
from this branch, both substituted with sleep-based commands at a scaled
ratio of a mid-size TS project (build 6s / lint 3s / tests 12s ≈ 45/20/90s
scaled ÷7.5). Fixture repo with a Stage-7 in-flight change so all gates run.
Two runs each; variance < 0.02s.

### Hook gate sections (Track H §9.1)

| Configuration | Run 1 | Run 2 |
|---|---|---|
| v0.21 serial | 21.15s | 21.14s |
| v0.22, key absent (default) | 21.16s | — |
| v0.22, `hook-parallel-gates: yes` | 12.17s | 12.17s |

Parallel = max(6, 3, 12) + ~0.2s orchestration = **sum → max exactly as
designed**; the default path is byte-equivalent to v0.21. At real project
scale (45/20/120s) the same shape saves **~65s per gated push**.

### Dependency-audit cache (Track H §9.2)

Stub `npm` whose `audit` sleeps 5s (a typical advisory fetch; the hook caps
it at 45s), `package.json` + lockfile present:

| Configuration | Time |
|---|---|
| v0.21 — audit runs on EVERY push | 5.67s / 5.19s |
| v0.22 cold (first push / lockfile changed) | 5.22s |
| v0.22 warm (hash match within TTL) | **0.20s / 0.21s** |

### Stage 3 exit-gate build+lint (Track E)

| Shape | Time |
|---|---|
| Serial (6s + 3s) | 9.05s |
| Concurrent background jobs, per-pid wait | 6.04s |

At project scale (45s + 20s): **65s → 45s, once per coder return and per
panel round**.

### Stage 7 bookkeeping (Track E, fix lane)

5 separate bash invocations vs 1 function-based script: 73ms → 48ms of
process time — i.e. the bash cost was never the point. The real saving is
**4 fewer orchestrator round-trips** (each a full model turn; priced in
Part 2's TURN parameter).

---

## Part 2 — Modeled (composition; assumptions explicit)

Simulator: `scratchpad/bench/simulate.py` (parameters at top). It chains
the stage machine costs from Part 1 with assumed agent durations and an
assumed orchestrator turn latency, for both template versions.

**Assumed agent durations (seconds)** — mid-range for a medium repo;
replace with Track A field data when real runs exist:

| Agent | s |
|---|---|
| coder (feat / fix-lane / fix-round) | 480 / 300 / 240 |
| reviewer (full / delta round) | 300 / 150 |
| security (full / self-noop / delta) | 240 / 60 / 90 |
| test-coder (feat / fix) | 360 / 300 |
| test-reviewer (feat / fix) | 180 / 150 |
| contract phase / restore+reconcile | 120 / 180 |

Other parameters: orchestrator turn = 8s; CI = 480s polled at 45s (v0.21:
~11 poll turns; v0.22: one blocking watch); Base-Ref verification = 40s;
build 45 / lint 20 / tests 120 / audit 10.

**Key structural change being priced:** v0.21 runs
`… max(reviewer, security) → test-coder →` in series; v0.22 runs
`… max(reviewer, security, test-coder) →` with the test work hidden behind
the panel on the happy path (quarantine-on-FAIL protects the multi-round
path).

### Results (machine-phase wall-clock, human waits excluded)

| Scenario | v0.21 (min) | v0.22 (min) | saved (min) | saved % |
|---|---|---|---|---|
| S1 feat 1-round, non-sensitive | 27.9 | 21.0 | 6.8 | 25% |
| S2 feat 1-round, sensitive (contract fires) | 27.9 | 23.0 | 4.8 | 17% |
| S3 feat 2-round, sensitive | 35.5 | 31.4 | 4.1 | 12% |
| S4 fix 1-round, non-sensitive | 21.6 | 16.5 | 5.0 | 23% |
| S5 = S1 + `hook-parallel-gates: yes` | 27.9 | 20.0 | 7.9 | 28% |

Reading the shape: the biggest term everywhere is Track B hiding the
test-writing spawn behind the round-1 panel (S1: −5.0 min of the −6.8;
the rest is CI poll overhead −1.3, build+lint −0.3, audit cache −0.2).
Sensitive changes give a bit back to the contract phase (S2); multi-round
changes keep a positive-but-smaller margin exactly as the plan's honest
math predicted (S3 — reconcile ≪ a full test pass because quarantine
preserved the speculative work). The fix lane adds the Stage-7 batching
and verification-scheduling wins (S4). CI'd runs also shed ~80s of poll
round-trip overhead each (folded into S1–S3).

### Human latency (counted, not clocked)

Round-trips are priced by the human's response time H, which no benchmark
controls — so they are reported as counts:

- **Pre-flight fold (Track D):** −1 blocking round-trip on every run
  carrying non-critical drift/convention/doctor signals. At H = 60s
  (attentive) that's a minute; at H = 15 min (context-switched) it's
  15 minutes.
- **Deploy pre-auth (Track F):** −1 round-trip at the post-CI stall — the
  one spot in the run where the human has most likely walked away, i.e.
  the trip most likely to be priced at the LARGE H. For a deploy-configured
  repo this is frequently the single biggest wall-clock item the release
  removes.

## Caveats

1. Agent durations in Part 2 are assumptions, not measurements — running
   real spawns twice per scenario would cost dozens of model runs. The
   Track A stats section shipped in this same release measures the real
   thing on real runs; re-derive this table from field data once
   `bash espalier/hooks/espalier-stats.sh` has rows.
2. Part 1's sleeps model CPU-idle commands; genuinely CPU-saturating
   build+tests running concurrently will land between max() and sum() on a
   loaded machine. That is why `hook-parallel-gates` is opt-in and
   discovery-gated.
3. The model prices `speculative-tests: on` (the default). A repo that
   opts out gets v0.21-equivalent behavior and v0.21-equivalent times —
   measured, not assumed, on the hook path.
