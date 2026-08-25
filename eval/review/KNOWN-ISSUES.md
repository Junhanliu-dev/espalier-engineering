# eval/review — Known Issues

Status 2026-08-25 (v0.23.0 fix round): the full 10-fixture suite is GREEN —
catch-rate 1.00, 0 false positives, 0 fixture failures
(`ANTHROPIC_MODEL=claude-sonnet-5`). The three issues found on the v0.23.0
first run are FIXED; the history below stays as the diagnostic record.

## FIXED: judge output-parse strictness

One fixture per full run used to fail when the judge emitted prose before
its JSON (run A: rule-console-02; baseline run B: rule-datasafety-05).
Every eval runner now extracts the LAST `{…}` line from the judge reply
before parsing (`run.sh`, and the same guard in the other six suites).
Verified: the green full run had zero parse failures.

## FIXED: missing-test P1s had no judge rule (v0.23 folded reviewer)

The folded reviewer files test-coverage findings at Stage 4; on code-only
fixtures the judge scored them as FP or legitimate at random. `rubric.md`
now rules them genuine harness-world observations (never FPs, not catches,
ignored for clean-fixture `verdict_match`), and fixtures that DO ship test
files score test findings normally.

## FIXED: no combined code+tests fixture

`combined-08-code-and-tests.md` (multi-file `=== FILE: ===` body — run.sh
gained the materializer) plants a cap-enforcement bug plus the tautological
test that certifies it; the folded reviewer must catch both with the code
in view. Green in-suite (2/2, 0 FP). Design note from its first draft: a
combined fixture's code defect must be a PLANTED issue, not a
`false_positive_watch` exclusion — a reviewer honestly flags real code
bugs, and a fixture that forbids that fights itself.

## History: FP-gate flakiness at baseline (attribution record)

First-run A/B, same model, same day — kept because it is the attribution
method for any future FP-gate failure:

| Run | Templates | Catch | FPs | FP fixtures |
|-----|-----------|-------|-----|-------------|
| A | v0.23.0 (folded) | 1.00 | 2 | clean-01, rule-timeout-04 |
| B | v0.22.1 baseline (`628bcf0`) | 1.00 | 1 | rule-readability-07 |
| C | re-run of A's two FP fixtures | 1.00 | 0 | — |
| D | full suite after the fixes above | 1.00 | 0 | — |

Different fixtures FP'd per run and none reproduced — judge variance, the
same class `eval/security/KNOWN-ISSUES.md` records. Discipline stands: a
review-suite FP failure is attributed to a template change ONLY after a
baseline A/B under the same model and a re-run of the failing fixtures.
