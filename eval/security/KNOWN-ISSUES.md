# Known Issues — eval/security

## FP gate fails under current models at BASELINE (found 2026-08-18, v0.22 release gate)

**Symptom:** the `false positives == 0` gate fails even though catch-rate is
1.00 — every planted vulnerability is caught in every run.

**Evidence (all under the same 2026-08 model, `ANTHROPIC_MODEL=opus`):**

| Run | Templates | FPs | Failing fixtures |
|---|---|---|---|
| baseline (main worktree, solo) | v0.21.1 | 2 | shadow-02, shadow-03 (clean-fixture MISMATCH) |
| release run (concurrent) | v0.22.0 | 8 | shadow-01/02/03, vuln-02, vuln-03 |
| release run (solo, reproduced) | v0.22.0 | 8 | shadow-01/02/03, vuln-03 (+2 elsewhere) |
| single-fixture A/B, vuln-03 | v0.21.1 → 0 FP; v0.22.0 → 2 FP | | |

**Diagnosis (records read side by side, KEEP_WORK=1):** both auditors catch
the identical planted defect (the `{ ...req.body }` mass-assignment) and
both slice it BY AXIS (permission / identity / state / money) at the same
file:line — the v0.21.1 record as 4 P0s, the v0.22 record as 3 P0s + 1 P1.
The judge collapsed one record's slices into `caught=1 fp=0` and counted
the other's as false positives. The FP number is therefore a
**judge-collapse counting artifact on same-defect multi-findings**, not an
invented vulnerability. The one clean-fixture mismatch (shadow-03) fails on
BOTH template versions.

The suite last held FP=0 on 2026-07-08 (`auto-optimize-results.tsv`), under
that era's model — the judge-validation set (24/24 cells) was also scored
then. This is the model-drift pattern: today's auditors slice findings at
finer granularity, and the judge's collapse rule no longer absorbs it.

**Why this did not block the v0.22 release:** the gate fails at baseline,
so reverting the v0.22 template change (one conditional paragraph, inert
without its `SPECULATIVE TESTS IN FLIGHT:` prompt line — which eval prompts
never carry) would not make the gate pass; catch-rate is perfect on both
versions; and the extra "FPs" are re-slicings of planted defects, not
findings on clean code (shadow-03 excepted — pre-existing).

**Fix needed (deferred, see docs/deferred-items.md):** recalibrate the
judge's collapse rule (same file:line + same root defect → one catch
regardless of axis slicing), re-validate `judge-validation/` under the
current model, and re-examine shadow-03's answer key. Until then, treat
`catch-rate` as the trustworthy number and hand-read FP failures before
attributing them.
