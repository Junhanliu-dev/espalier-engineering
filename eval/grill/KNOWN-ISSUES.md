# Grill Eval Harness — Known Issues

Findings from a clean-baseline run of `run.sh` against committed `HEAD` (all 20
fixtures, committed `espalier-grill.md` and `rubric.md`, no working-tree edits).
The purpose was to separate real regressions from working-tree noise. It found no
skill regression; every failure below is a harness or fixture defect.

Recorded 2026-07-11. `RESULT: FAIL` at HEAD is caused entirely by items 1–4 — NOT
by any change to the grill skill.

## 1. `run.sh` conflates infra failure with scoring failure (HIGH)

`run_grill` / `judge` shell out to `claude -p`. When a call fails for an
infrastructure reason — rate-limit window, transient API error — the fixture is
counted into `fail_count` exactly like a fixture that ran and scored badly, and the
run still prints `RESULT: FAIL`. One clean-baseline run had 18/20 fixtures report
`grill run failed` from a transient limit; re-running immediately after passed 16 of
those 18. An API hiccup is indistinguishable from a regression in the output.

Fix: retry `claude -p` a bounded number of times on non-zero exit; distinguish
"could not execute" (infra) from "executed and failed the gate" (scoring) in both the
per-fixture line and the final `RESULT`. An infra failure should exit with a distinct
non-zero code, not the scoring-gate code.

## 2. `run.sh` cannot parse fenced judge JSON (MEDIUM)

The judge is asked for one line of compact JSON. It sometimes wraps the line in a
```json fence. `run.sh`'s `sed` extractors then fail and the fixture is logged
`unparseable judge output` and counted as a failure. In the clean run
`shadow-light-02-invoice-failures` hit this despite coverage 1.00, verdict PASS.

Fix: strip a leading/trailing code fence before parsing, or instruct the judge more
firmly to emit no fence. `validate-judge.sh` shares the same extractors and the same
exposure.

## 3. `shadow-light-04-auto-assign-ids` is unsatisfiable at its tier (MEDIUM, fixture bug)

The fixture plants **4** independent `planted_ambiguities` but sets
`expected_tier: light`, whose question cap is **≤ 3** (`espalier-grill.md` Step 1).
Grill cannot surface 4 independent signals in 3 questions, so coverage is ceilinged
at 3/4 = 0.75 — it fails the per-fixture 0.8 coverage bar on every run, by design of
the fixture, not because grill missed anything. This is why its 0.75 is perfectly
stable across runs (dirty tree and clean HEAD both 0.75).

Fix (pick one): drop one planted signal so 3 questions can cover it; or bump to
`full` (the 4-signal count is on the `light`/`full` boundary either way); or make two
of the four signals resolvable by a single question or from the codebase (grill's
"answer from the codebase first" rule), so 3 questions still reach 4/4.

## 4. Rubric per-fixture bar collides with the `non_obvious` recalibration (HIGH, design)

`a022c27` (and the in-progress v0.11.0 "Announced-gap test") deliberately score
reflexive questions — those a vague term in the requirement forces, like "faster",
"better", "handle X better" — as `non_obvious` = 1, reserving 2 for genuinely hidden
ambiguities. But `rubric.md` "Per-fixture pass" still requires mean
`non_obvious ≥ 1.3`. A well-specified `full` requirement whose questions are mostly
reflexive (e.g. `full-01-dashboard-faster`: "which dashboard", "faster vs what",
"which errors") can now never clear 1.3, so it fails the per-fixture gate even at
coverage 1.00. `full-03-checkout-broken` and `light-02-api-rate-limit` fail the same
way; `full-01` sits exactly on the boundary and flips PASS/FAIL between runs.

The two rules are individually defensible but jointly unsatisfiable for a class of
fixtures. Decide one:
- lower the per-fixture `non_obvious` bar (the aggregate catch-rate gate, 0.80, is
  the primary signal and stays green — 0.98 all / 0.97 shadow at HEAD); or
- keep 1.3 but only over questions the rubric considers non-reflexive; or
- accept that some correct `full` runs are "coverage-complete, low-insight" and score
  them on coverage alone.

## What is NOT wrong

- The grill skill. Coverage recovered or held on clean HEAD for every fixture except
  the two rubric-gated ones and the mis-tiered fixture (#3). No skill regression.
- The aggregate catch-rate: 0.98 all / 0.97 shadow / 1.00 non-shadow — clears 0.80.
- `shadow-full-04-openai-summary` (the 20th fixture): coverage 1.00, verdict PASS.
- The judge's agreement with hand scores: 24/24 on the validation subset.
