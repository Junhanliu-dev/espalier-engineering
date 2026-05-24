# Grill Eval Harness

Dev/QA infrastructure for the `espalier-grill` skill. NOT shipped to target projects
— it lives in the espalier-engineering repo and validates the skill before release.

It mitigates the two HIGH pre-mortem findings (`docs/grill-integration-plan.md` §13):
it catches whether grill actually surfaces ambiguity, and scores question quality.

## Layout

```
eval/grill/
├── README.md      this file
├── rubric.md      how a grill run is scored
├── run.sh         the runner
└── fixtures/      golden requirement/bug fixtures with planted ambiguities
```

## Run

```bash
bash eval/grill/run.sh
```

Per fixture the runner: (1) runs `espalier-grill` against the fixture via `claude`
headless, playing the fixture's `answer_script` as the simulated user; (2) scores
the transcript with an LLM judge against `rubric.md`; (3) aggregates. Exits non-zero
if the catch-rate is below the gate (0.80 — plan §9).

## Fixture format

One `.md` file per fixture. Frontmatter is the answer key; the body is the input.

```yaml
---
fixture_id: light-01-csv-export
mode: spec | diagnosis
expected_tier: skip | light | full
expected_signals: <int>          # ambiguity-signal count grill should score
planted_ambiguities:             # what grill SHOULD surface (empty for skip)
  - ...
answer_script:                   # simulated user replies (empty for skip)
  - asks_about: <topic>
    reply: <text>
shadow: false
---
<requirement or bug text>
```

## Discipline

- **Reach 20–30 fixtures.** This seed set has 9 (3 per tier). The gate is provisional
  until the set is full — plan §6 Phase A2.
- **Shadow subset.** Roughly one third of fixtures should be `shadow: true` — authored
  from real tickets or by someone other than the grill-skill author, so the skill
  cannot be tuned to pass known fixtures. The current seed is all `shadow: false`: it
  was written alongside the skill and is NOT a valid shadow set.
- **Validate the judge** before trusting it — see `rubric.md` "Judge validation"
  (≥ 75% agreement with hand scores).
- **Regression gate.** Run `run.sh` on every `espalier-grill.md` edit; prompt edits
  cause silent regressions.
