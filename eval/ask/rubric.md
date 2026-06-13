# Ask Eval Rubric

How an `/espalier-ask` run is scored against a fixture. A fixture passes only
when BOTH gates pass: the deterministic sidecar/behaviour checks (run by
`run.sh` directly) AND the LLM judge's answer-quality verdict.

The judge is an LLM given: the fixture (`question`, `bucket`, `expected_type`,
`expect` list) and the skill transcript (the answer + any tool actions).

## Gate 1 — deterministic behaviour (run.sh, not the judge)

Per `bucket`, `run.sh` asserts the side effects directly on the temp repo:

| bucket | deterministic assertion |
|--------|-------------------------|
| `classify` | no `espalier/.drift-state.tsv`, no `espalier/.ask-gaps.tsv` created |
| `docs-first` | no drift flag, no gap row created |
| `drift` | `espalier/.drift-state.tsv` exists AND a row's reason contains `ask-verify:` |
| `gap` | `espalier/.ask-gaps.tsv` exists AND has ≥1 non-empty row |
| `no-install` | `espalier/` directory still absent AND the run did not error |

A fixture that fails Gate 1 FAILS regardless of the judge.

## Gate 2 — answer quality (LLM judge)

The judge scores the transcript against the fixture's `expect` list and outputs
one compact JSON line:

```
{"type_correct":true|false,"docs_first":0-2,"verified":0-2,"sourced":0-2,"trusts_code":0-2,"verdict":"PASS|FAIL"}
```

### Scored dimensions

1. **type_correct** — did the run treat the question as the fixture's
   `expected_type` (where / how / why / what-changed)?
2. **docs_first** — did it consult the espalier/ docs BEFORE crawling the
   codebase from scratch? (2 = clearly docs-first; 0 = ignored docs.) For
   `no-install` this is vacuously 2 (no docs to consult).
3. **verified** — did it confirm any doc-sourced claim by reading the cited
   code file before asserting it? (2 = yes; 0 = answered from the doc alone.)
4. **sourced** — does the answer cite doc paths and/or `file:line`? (2 = every
   claim sourced; 0 = unsourced prose.)
5. **trusts_code** — when doc and code disagree (drift fixtures), did the
   answer follow the code, not the stale doc? (2 = code wins; 0 = repeated the
   stale doc.) For non-drift fixtures this is vacuously 2.

### Judge verdict

`PASS` when: `type_correct` is true AND every applicable dimension ≥ 1 AND the
fixture-specific `expect` bullets are substantially met. Otherwise `FAIL`.

## Aggregate gate

- pass-rate = fixtures passing BOTH gates / total fixtures
- the harness PASSES when pass-rate ≥ 0.80 AND no `drift` or `no-install`
  fixture failed Gate 1 (those are the safety-critical buckets — a wrong drift
  flag or a sidecar written into a non-install is never acceptable).

## Judge validation

Before trusting the judge: hand-score the 6 fixtures, run the judge on the same
6, require ≥ 75% dimension-level agreement. Re-validate whenever this rubric
changes.
