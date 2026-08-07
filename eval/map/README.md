# Map Eval Harness

Dev/QA infrastructure for the `espalier-map` skill (Layer 2 of the lane-quality
scheme in `docs/map-lane-plan.md`). NOT shipped to target projects — it lives
in the espalier-engineering repo and validates the skill before release.

It measures the failure modes the lane was designed against: missed decisions
(fog coverage), fog pre-sliced into premature tickets (placement), tickets
mis-typed into implementation steps (typing), building mid-plan
(plan-don't-do), over-charting past the cap, self-answered HITL questions,
and uncited convention collisions in decision-mode grilling.

## Layout

```
eval/map/
├── README.md          this file
├── rubric.md          how a map run is scored (dimensions + pass bars)
├── run.sh             the runner (catch-rate + shadow/non-shadow split)
└── fixtures/          chart + work fixtures with planted decisions/collisions
```

## Run

```bash
bash eval/map/run.sh
```

Per fixture the runner: (1) runs the `espalier-map` skill headless in EVAL
MODE (no filesystem — every artifact is STATED in the transcript; the
fixture's `answer_script` plays the human; `## MOCK MAP` / `## MOCK CONTEXT`
blocks stand in for `espalier/maps/` and `rules/`+`wiki/`); (2) scores the
transcript with an LLM judge against `rubric.md`; (3) derives each verdict
from the judge's dimension fields (never from its self-reported verdict) and
gates on the 0.80 catch-rate plus the per-fixture bar.

Exit codes: 0 PASS, 1 FAIL (real scoring regression), 3 INCONCLUSIVE (≥1
fixture never executed — infra, not scoring; same contract as the grill
harness).

## Fixture families

| Family | Fixtures | Measures |
|---|---|---|
| chart coverage | chart-01-team-crm, chart-02-monolith-events | planted decisions surfaced; ticket-vs-fog placement; type calibration |
| no-fog exit | chart-03-crisp-endpoint | refuses to chart a one-session effort; routes to /espalier |
| cap stop | chart-04-do-everything | stops at max-open-tickets; forces narrow/split/raise via a question |
| plan-don't-do | chart-05-tempt-build | explicit "scaffold now" order deflected into a task ticket; zero writes outside maps/ |
| greenfield | chart-06-greenfield-recipes | fixed destination template; stack-research/conventions/scaffold-task shape; Pass-2 handoff |
| work one-ticket | work-01-resolve-notifications | exactly one ticket resolved; fog graduates AND leaves the fog section; stops |
| decision collision | work-02-collision-data-access | Step 1.5 in decision mode: collisions surfaced WITH rules/wiki citations |

Every fixture also exercises the HITL line: the judge fails `contracts_ok`
if any user reply was fabricated beyond the `answer_script`.

## Shadow subset

Same discipline as `eval/grill`: fixtures written alongside the skill
(`shadow: false`) can be unconsciously tuned for; the trustworthy number is
the catch-rate over `shadow: true` fixtures contributed WITHOUT reading the
skill's exact wording. The entire current set is non-shadow (seed set), so
the gate is **PROVISIONAL** — the runner says so on every run. Before
trusting a PASS for release purposes, add shadow fixtures: hand a colleague
(or a fresh session with only this README + the rubric) the fixture format
and let them plant decisions from a real past epic.

## Judge validation

The judge must be trusted before its scores are (rubric.md "Judge
validation"): hand-score a subset, require ≥ 75% dimension-level agreement,
sharpen anchors, repeat. `validate-judge.sh` wires that step (modeled on the
grill harness's validator): `generate` runs map+judge on a 5-fixture core
(plus any shadow fixtures) and emits a blank `handscore.tsv`; you score the
five dimensions per fixture by reading the transcripts; `rollup` derives
each human verdict from rubric.md "Per-fixture pass"; `compare` gates
agreement at ≥ 0.75. This has NOT yet been run to completion for the map
rubric — the runner prints a PROVISIONAL note until it has.

## Cost note

One full run = 2 claude calls per fixture (skill + judge) × 8 fixtures, with
up to 3 retries on infra hiccups. The map transcripts are long (full map.md +
tickets stated inline) — expect a run to cost noticeably more than a grill
run. Run it per release, not per commit.
