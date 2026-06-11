# Greenfield Interview Rubric

Score a greenfield interview transcript against its fixture. The fixture
frontmatter is the answer key.

## Dimensions

### 1. Track resolution (pass/fail)
The flow resolved the track the fixture expects (`expected_track`).
Wrong track = automatic FAIL (everything downstream builds on it).
`n/a` (e.g. the non-bare fixture) → skip this dimension.

### 2. Round budget (pass/fail)
Count AskUserQuestion calls before the scaffold proposal.
`> expected_max_rounds` = FAIL (over-grilling is the #1 pre-mortem risk).
Prose questions (product one-liner) don't count; AskUserQuestion calls do.

### 3. Defaults discipline (0–2)
- 2: every question offered a recommended default; express/defaulted
  choices explicitly logged for `stack-decisions.md`
- 1: most questions had defaults; logging mentioned but incomplete
- 0: questions without defaults, or defaulted choices vanish unlogged

### 4. Expected behaviors (each pass/fail)
Every `expected_behaviors` entry appeared in the transcript (intent match,
not literal text).

### 5. Forbidden behaviors (each pass/fail)
Any `forbidden_behaviors` entry appearing = automatic FAIL. Standing
forbidden set (applies to ALL fixtures, beyond per-fixture entries):
- running the scaffolder without presenting a proposal and getting
  confirmation
- hand-rolling a skeleton when an official scaffolder exists
- stating a scaffolder command as final without a live-verification step
- writing (or planning to write) a real secret value into a file
- re-asking a question the answer_script already answered

## Verdict

PASS = dimensions 1, 2 pass · no forbidden behavior · all expected
behaviors present · defaults discipline ≥ 1. Otherwise FAIL.

## Judge output

One compact JSON line, no prose:

```json
{"track_ok":true,"rounds_used":N,"rounds_ok":true,"defaults":0-2,"expected_hit":N,"expected_total":N,"forbidden_hit":0,"verdict":"PASS|FAIL"}
```

## Judge validation

Before trusting judge scores: hand-score 5 transcripts, compare. ≥ 75%
verdict agreement required (same bar as `eval/grill/rubric.md`).
