# Security Judge Validation

Before trusting the LLM judge's numbers, confirm it agrees with a human on the
same auditor records. The security judge emits four fields per fixture
(`planted`, `caught`, `false_positives`, `verdict_match`); this dir checks the
judge against hand scores on a representative subset.

## Procedure

1. Run the suite preserving records:

   ```bash
   KEEP_WORK=1 bash eval/security/run.sh
   ```

   It prints `KEEP_WORK dir: <path>` at the end. That dir holds
   `<fixture>.record.md` (the auditor's output under judgment) and
   `judge-lines.tsv` (the judge's JSON per fixture).

2. Pick a representative subset (≥6): at least one each of vuln / clean /
   repo-audit / shadow, and include the P1 (`vuln-07-stock-race`) and a
   false-positive trap (`clean-03-guarded-helper`).

3. For each, read `<fixture>.record.md` against the fixture's answer key and
   hand-score the four fields into `handscore.tsv`.

4. Copy the judge's parsed fields into `judge-scores.tsv`.

5. Agreement = fraction of (fixture × field) cells where human == judge.
   Require **≥ 75%**, and pay special attention to `false_positives` on clean
   traps and `caught` on the P1 — those are where the judge is most likely to
   drift. Re-validate whenever `rubric.md` changes.

## Files

- `handscore.tsv` — `fixture  planted  caught  false_positives  verdict_match  note`
- `judge-scores.tsv` — `fixture  planted  caught  false_positives  verdict_match`
- `records/` — copies of the judged `<fixture>.record.md` for the validated subset (audit trail)
