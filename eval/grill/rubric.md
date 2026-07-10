# Grill Eval Rubric

How a grill run is scored against a fixture. The judge is an LLM given: the fixture
(requirement + `planted_ambiguities` + `expected_tier`) and the grill transcript
(questions asked + tier chosen + final `requirements.md`).

## Scored dimensions

### 1. Coverage (primary)
Of the fixture's `planted_ambiguities`, how many did grill's questions actually
surface? Score = surfaced / total. A planted ambiguity counts as surfaced only if a
grill question would force the user to resolve it.

### 2. Depth calibration
Did grill choose the fixture's `expected_tier`?
- 2 — exact tier
- 1 — off by one (e.g. light vs full)
- 0 — off by two (skip vs full), or grilled a `skip` fixture / skipped a `full` one

### 3. Non-obviousness (per question, averaged)
- 2 — a competent engineer would NOT already know to ask this; the ambiguity is
  hidden and the answer is not the default assumption. Examples: input-entry-vs-
  display bug, sync-vs-async + pagination scope, `finally`-block cause, blur-timing.
- 1 — a standard domain question any engineer building this feature would ask
  by reflex; real but not insight. Examples: "which report / which entity?",
  "which columns?", "which of the several dashboards?". Score these 1, NOT 2 —
  asking is correct, but it is obvious, not non-obvious.
- 0 — generic filler ("any edge cases?") or answerable from the input text itself.

Calibration note: score non-obviousness on its own, independent of whether the
answer forks the impl (that is dimension 4). A pure "which X of the obvious set of
X" is a 1. But a question is a 2 when a competent engineer would plausibly have
picked a DEFAULT and been wrong — even if the topic itself is mundane (e.g.
"normalise while typing vs on blur", "sync visible-page export vs async full
dataset"). Do not floor everything to 1; reserve 0 for filler, 1 for reflexive
standard asks, 2 for questions that overturn a likely-wrong default assumption.

### 4. Discrimination (per question, averaged)
- 2 — the answer materially changes the implementation
- 1 — the answer changes a detail
- 0 — the answer changes nothing

### 5. Progression (full-tier runs only)
- 2 — each question visibly builds on the prior answer
- 1 — mostly independent questions
- 0 — a flat batched checklist

## Per-fixture pass

A fixture passes when: coverage ≥ 0.8 AND depth-calibration = 2 AND mean
non-obviousness ≥ 1.3 AND mean discrimination ≥ 1.3.

`skip` fixtures pass when grill asked zero questions and chose `skip` (coverage is
vacuously 1.0; progression N/A).

## Aggregate gate

- catch-rate = total ambiguities surfaced / total planted, across ALL fixtures
- the harness PASSES when catch-rate ≥ 0.80 (plan §9) AND no `full`-tier fixture
  scores coverage < 0.5

## Judge validation

The LLM judge must be trusted before its scores are. Before first use:
1. Hand-score a 6-fixture subset. Dimensions 1–2 are one number per fixture;
   dimensions 3–4 are scored 0/1/2 **per question** and averaged by
   `validate-judge.sh rollup` — never by hand.
2. Run the judge on the same 6.
3. Require ≥ 75% agreement (dimension-level) with the hand scores.
4. If below 75%, sharpen the level anchors above and repeat.

Re-validate whenever the rubric changes.
