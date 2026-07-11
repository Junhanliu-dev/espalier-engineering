# Finding — the grill eval gates on an unvalidated, self-reported verdict

Status: **implemented** in `run.sh` + `validate-judge.sh`; `handscore.tsv` rolled up.
Not committed. Found while reconciling `handscore.tsv` against an independent (Codex)
scoring pass, after `cf31c40` split scoring to per-question.

One follow-up remains: `judge-scores.tsv` predates the new `verdict` column, so `compare`
warns and skips the six verdict cells. Re-run `validate-judge.sh generate` (six live grill
runs) to populate it. Until then the verdict dimension is declared but unmeasured.

Same bug class as the v0.11.0 plan's **B2** (`Stage 4/6 gates parse only p0=`), but in a
different subsystem: B2 is the *espalier pipeline* verdict sentinel, this is the *grill
eval judge*. The two are unrelated code paths; fixing B2 does not fix this.

## Defect

`full-01-dashboard-faster` is reported `PASS` in every recorded run, yet it fails the
rubric's own per-fixture pass bar.

- `rubric.md:50-51` — a fixture passes only when `mean non-obviousness >= 1.3`.
- full-01 mean non-obviousness is **1.17** (human rollup, `handscore.tsv`) and **1.0**
  (judge, `judge-scores.tsv`). Both below 1.3.
- `baseline-run.log`, `round1-run.log`, `round2-run.log`, `shadow-run.log` all record
  `full-01-dashboard-faster  full  <cov>  PASS`.

Root cause, in two halves:

1. `run.sh:85` parses the judge's self-reported `"verdict":"PASS|FAIL"` string.
   `run.sh:96` increments `fail_count` from it. `run.sh:132` gates `RESULT: PASS` on
   `fail_count -eq 0`. **Nothing recomputes the verdict from the four dimension scores
   against the rubric bar.** The judge emits `non_obvious: 1.0` and `verdict: "PASS"` in
   the same JSON object — self-inconsistent — and the gate takes the string.

2. `validate-judge.sh` extracts only `surfaced`, `depth_cal`, `non_obvious`,
   `discrimination`. The token `verdict` appears exactly once, at line 92, inside the
   prompt template. It is **never parsed and never validated.**

So judge-validation certifies the four dimensions, and the harness gates on the one field
judge-validation does not check. `JUDGE: VALIDATED` at 24/24 is true and does not cover
this.

Under the pre-`cf31c40` holistic hand-score (full-01 non_obvious = 1.5) the fixture
cleared 1.3 and the inconsistency was invisible. Per-question scoring dropped it to 1.17
and surfaced it.

## Change

**`run.sh`** — derive the verdict; do not trust it. After parsing the four dimensions,
recompute per `rubric.md:50-51` rather than reading `"verdict"`:

    coverage >= 0.8 AND depth_cal == 2 AND non_obvious >= 1.3 AND discrimination >= 1.3

`skip` fixtures (0 planted) keep the existing vacuous-pass rule (`rubric.md:53-54`).
Keep parsing the judge's `verdict` string, but only to warn when it disagrees with the
recomputed one — a persistent disagreement means the judge is misapplying the bar and the
rubric anchors need sharpening.

**`validate-judge.sh`** — add `verdict` as a fifth validated cell (exact match against a
hand-entered PASS/FAIL). A judge trusted on dimensions but not on the verdict is not
trusted for the field the gate actually reads.

## Verify

- `bash eval/grill/run.sh` — `full-01-dashboard-faster` reports `FAIL`, and the run ends
  `RESULT: FAIL` (via `fail_count -eq 0`).
- A fixture whose four dimensions clear the bar still reports `PASS`.
- `bash eval/grill/validate-judge.sh compare` — reports a 5th dimension row per fixture.

## Expected fallout

full-01 flips to `FAIL`, so `RESULT: FAIL` until one of:

- the grill asks less reflexive questions on full-01 (the real fix — see below), or
- the rubric's 1.3 non-obviousness bar is revisited for requirements whose ambiguities are
  *announced* by vague terms rather than hidden.

Both human and judge score five of full-01's six questions as reflexive `1`s
(which-dashboard, which-target, which-error-class, which-actor, which-scope). That is a
signal about the skill, not only about the gate: on a requirement like *"make the
dashboard faster and handle errors better"*, every fork is flagged by the vague word
itself, so grill surfaces them by reflex and earns no non-obviousness credit. Decide
whether the bar or the fixture is wrong before tuning the skill to beat it.

## Resolved: full-01 Q4, via a sharpened non-obviousness anchor

full-01 **Q4** (`"Better handling" concretely — what shows when a fetch fails?`) was the
one cell the human grid (2) and both the judge and an independent Codex pass (1, twice)
disagreed on. Resolved in favour of **1** by sharpening the rubric, not by fiat.

Added the **announced-gap test** to `rubric.md` non-obviousness dimension: a 2 requires the
ambiguity to be HIDDEN. If a vague term in the requirement itself announces the gap
("faster", "better", "improve"), the ask is reflexive and scores 1 even when the answer
forks the impl — that the answer changes the build is dimension 4's job. Q4's fork is
announced by "better", so it is a 1. Re-scored the grid, re-ran `rollup`.

Result: full-01 non_obvious is now **1.0** (all six questions reflexive 1s), human and
judge agree exactly, `compare` stays 24/24 = 1.00 JUDGE: VALIDATED.

## Consequence: full-01 cannot pass as written — it is a coverage-only fixture

Sharpening did not rescue full-01; it made it fail more cleanly (1.17 → 1.0). This is
arithmetic, not opinion: a 6-question fixture needs sum ≥ 8 (two 2s) to clear mean 1.3.
Every one of full-01's planted ambiguities is announced by a vague term in
"make the dashboard faster and handle errors better" — which-dashboard, faster-target,
which-errors, better-handling, actor, scope. So grill earns full coverage (6/6) but,
correctly, no non-obviousness credit, and the fixture fails the 1.3 bar by construction.

That is the right signal about the fixture, not a gate bug: full-01 tests grill's
*coverage* of obvious gaps, never its *insight*, so it cannot satisfy a pass bar that
demands insight. Options (needs an owner decision):

1. Revise full-01 to plant ≥ 2 genuinely hidden ambiguities (make it a real `full` test).
2. Reclassify it as a coverage-only fixture exempt from the non-obviousness bar.
3. Accept the FAIL as documenting that vague-but-obvious requirements score low on insight.

Until then, `run.sh` will report `RESULT: FAIL` on any run including full-01 — which is
now the honest result.

Reconciliation state: human grid and the judge/Codex now agree on all 18 questions. Codex
conceded five cells earlier (full-01 Q5 discrimination, shadow-full-02 Q2 and Q5, light-01
Q3 discrimination, shadow-light-02 Q3); the human grid held; Q4 resolved by the sharpened
anchor above.
