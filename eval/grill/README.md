# Grill Eval Harness

Dev/QA infrastructure for the `espalier-grill` skill. NOT shipped to target projects
— it lives in the espalier-engineering repo and validates the skill before release.

It mitigates the two HIGH pre-mortem findings (`docs/grill-integration-plan.md` §13):
it catches whether grill actually surfaces ambiguity, and scores question quality.

## Layout

```
eval/grill/
├── README.md          this file
├── rubric.md          how a grill run is scored
├── run.sh             the runner (all + shadow + non-shadow catch-rate)
├── validate-judge.sh  judge-vs-human agreement harness (rubric.md "Judge validation")
├── judge-validation/  generated: transcripts + hand-score sheets (created on demand)
└── fixtures/          golden requirement/bug fixtures with planted ambiguities
```

## Run

```bash
bash eval/grill/run.sh
```

Per fixture the runner: (1) runs `espalier-grill` against the fixture via `claude`
headless, playing the fixture's `answer_script` as the simulated user; (2) scores
the transcript with an LLM judge against `rubric.md`; (3) aggregates. Exits non-zero
if the catch-rate is below the gate (0.80 — plan §9).

It reports three catch-rates: **all**, **shadow**, and **non-shadow**. The shadow
number is the trustworthy one (see "Shadow subset" below). When shadow fixtures exist
they must ALSO clear the gate — a high all-fixtures rate carried by author-written
non-shadow fixtures does not pass. When no shadow fixtures exist the gate is flagged
PROVISIONAL.

## Validate the judge first

```bash
bash eval/grill/validate-judge.sh generate   # grill+judge a 6-fixture subset
# ...read judge-validation/transcripts/*, then fill the two sheets (below)...
bash eval/grill/validate-judge.sh rollup      # average the per-question grid
bash eval/grill/validate-judge.sh compare     # agreement vs judge; gate >= 0.75
```

The catch-rate is only as trustworthy as the judge producing it. Run this before
trusting `run.sh`'s numbers, and re-run whenever `rubric.md` changes.

### Hand-scoring: two sheets, because the dimensions have two granularities

This is the part that trips people up. The four dimensions are not scored the same way.

| Sheet | Dimensions | Granularity |
|-------|-----------|-------------|
| `handscore.tsv` | `surfaced`, `depth_cal` | **one number per fixture** |
| `handscore-questions.tsv` | `non_obvious`, `discrimination` | **one 0/1/2 per question** |

You do not map a dimension onto a question. `surfaced` and `depth_cal` ignore
individual questions entirely; `non_obvious` and `discrimination` are scored per
question and then averaged into the fixture's row.

- `surfaced` — read the fixture's `planted_ambiguities`, count how many the questions
  forced the user to resolve. A count, not a rating.
- `depth_cal` — 2 if grill chose `expected_tier`, 1 if off by one, 0 if off by two.
- `non_obvious` / `discrimination` — score **each question row** 0/1/2 against the
  `rubric.md` anchors, then run `rollup`. It averages them and writes the derived
  value plus the contributing scores into `handscore.tsv`'s note column. Never average
  by hand — a hand-averaged cell can't be reproduced or audited, and integer scores
  over N questions can only land on multiples of 1/N.

`skip` fixtures ask zero questions, so they contribute no grid rows; `rollup` leaves
their `non_obvious` / `discrimination` cells alone (score them `0.0` — no questions,
no quality to rate). A fixture with some question rows left blank makes `rollup` warn
rather than quietly average over the subset.

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

- **Reach 20–30 fixtures.** Currently 19 (9 seed + 10 shadow). Add a handful more to
  clear the 20 floor — plan §6 Phase A2.
- **Shadow subset.** Roughly one third of fixtures should be `shadow: true` — authored
  from real tickets or by someone other than the grill-skill author, so the skill
  cannot be tuned to pass known fixtures. The 10 shadow fixtures were built from real
  internal-project commit history (two production apps): the raw
  commit subject is the ambiguous input, and the answer key is derived from what the
  commit's diff *actually* decided — so the key reflects real resolution, not the
  skill author's intuition. The 9 seed fixtures remain `shadow: false` (written
  alongside the skill). Shadow fraction is currently 53%.
- **Validate the judge** before trusting it — see `rubric.md` "Judge validation"
  (≥ 75% agreement with hand scores).
- **Regression gate.** Run `run.sh` on every `espalier-grill.md` edit; prompt edits
  cause silent regressions.
