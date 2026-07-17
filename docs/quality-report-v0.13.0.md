# v0.13.0 Agent & Skill Quality Report

Independent quality scoring of the four artifacts the v0.13.0 minimalism
release touches, on the darwin 8-dimension rubric (structure 60 + measured
effect 40, total /100). Method:

- **Structural dimensions (1–7)** scored by independent reviewer agents that
  never authored the changes, each reading the artifact in full plus its
  sibling templates to verify every cross-reference (paths, section names,
  verdict vocabulary) rather than trusting the text.
- **Effect dimension (8, weight 25)** fed from real harness runs
  (`eval/coder/run.sh`, `eval/review/run.sh`), not dry-run simulation — every
  score row below is `full_test`.
- **Ratchet:** after the baseline pass, every scorer finding was fixed and the
  suite re-run; a change is kept only when the suites stay green.

Raw score log: `eval/coder/auto-optimize-results.tsv`,
`eval/review/auto-optimize-results.tsv`.

## Scorecard

| Artifact | Jul 7 (v0.12 era) | v0.13.0 baseline | v0.13.0 after fix round | Δ (fix round) |
|---|---:|---:|---:|---:|
| `harness-reviewer.md` | 88.2 | 87.9 | **91.0** | +3.1 |
| `harness-coder.md` | — | 83.2 | **88.6** | +5.4 |
| `espalier-review.md` | 82.9 | 82.4 | **88.1** | +5.7 |
| `espalier-coding.md` | — | 75.7 | **75.7** | ±0 |
| **Average** | | 82.3 | **85.9** | +3.6 |

Effect evidence backing dimension 8 (identical for baseline and post-fix —
the fix round changed structure, not behaviour):

- Coder suite: **4/4 PASS** — 0 convention violations, 0 over-scope,
  0 over-build, including the new `coder-04-overbuild-trap` fixture (the agent
  formatted a date with `toISOString().slice(0, 10)` instead of adding a
  library or writing a formatter class).
- Review suite: **8/8 PASS** — catch-rate 1.00, false positives 0, including
  the planted new-dependency P1 (`rule-newdep-06`, dayjs for a
  stdlib-formattable date) and the severity-inflation guard
  (`clean-02-minimal-guard`). On lean code the reviewer filed **zero**
  minimalism findings in every run — the advisory P2/P3 cap and the
  convention tie-break held in every record.

## What the fix round changed

All four baseline weakest-dimension findings, fixed and re-verified:

1. **harness-reviewer** — the sentinel contract now binds `p1=` to the P1 row
   count exactly as `p0=` was already bound (the new-dependency minimalism P1
   rides on that count); frontmatter description now states when the agent is
   spawned and what it may write; the `espalier-security` citation carries its
   full path. The re-score also surfaced a real pre-existing drift — the
   in-file P1 checklist had lost the "unbounded fan-out on a request path"
   bullet its own cited source (`production-standards.md`) carries — restored.
2. **harness-coder** — frontmatter now names its stage triggers (Stage 3,
   fix rounds, Stage 5 testing mode) and the ladder's governing rule.
3. **espalier-coding** — frontmatter gains the `{project}` placeholder and
   trigger phrases; the "Before Writing Code" steps that duplicated
   `harness-coder.md` near-verbatim are now a pointer at the canonical
   sequence, so the two files cannot drift.
4. **espalier-review** — the inline plan-review loop gains an explicit pass
   condition (zero P0/P1; P2/P3 advisory; rounds and escalation owned by
   pipeline Stage 2), matching the rigor of the code-review loop's sentinel.

## Known residual weaknesses (next optimize targets)

> **Post-release follow-up (2026-07-17):** all three items below were fixed
> after the v0.13.0 release and re-verified — espalier-coding 75.7 → 90.4
> (By-Stage section + illustrated checklist), harness-reviewer 91.0 → 96.0
> (abuse-test coverage as numbered step 7), espalier-review 88.1 → 93.8
> (code-review Gate line). Suites green (coder 4/4, review 8/8 FP0). See the
> `2026-07-17T16:38` rows in `eval/{coder,review}/auto-optimize-results.tsv`.
> The list below is kept as the historical v0.13.0 state.

- `espalier-coding.md` (75.7): the frontmatter promises three usage contexts
  (Stage 3 / Stage 5 testing / fix rounds) but the body carries no
  stage-conditional guidance differentiating them; the Implementation
  Checklist placeholder block ships unillustrated.
- `harness-reviewer.md`: the Stage 6 abuse-test-coverage duty is a section but
  not a numbered step in the Review Process list.
- `espalier-review.md`: the code-review loop doesn't restate round-ownership
  the way the plan-review loop now does (asymmetric, cosmetic).

### New residuals surfaced by the follow-up scorers

- `espalier-coding.md`: no fallback when a task touches a layer whose spec
  file was deliberately skipped at init; checklist placeholder gives the init
  scout no minimum-coverage floor; the lean summary partially restates the
  ladder the Before-Writing pointer exists to not restate (drift surface).
- `harness-reviewer.md`: the Stage 6 failure-mode-coverage duty (missing
  dependency-failure test = P1) lives only in the orchestrator spawn prompts,
  not in the agent file's own Review Process; Escalation Reason block's
  position relative to the "VERDICT last line" rule unspecified.
- `espalier-review.md`: plan-review Output line names no record destination
  for standalone (non-pipeline) invocations; standalone code review silently
  omits the harness-security half of the Stage 4 panel; ad-hoc invocations
  have no owned round cap.

## Scoring caveats

Scores are LLM-judged and vary a few points between scorer sessions on the
same file (observed spread ≈ ±2). Treat single-digit deltas as noise and the
weakest-dimension diagnoses — which were consistent across scorers — as the
actionable signal. Baseline scoring context: the July 7 numbers were produced
under a different default model; this report's runs all used the same scorer
configuration for baseline and post-fix.
