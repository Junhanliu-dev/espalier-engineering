# Review Eval Rubric

How a `harness-reviewer` code-review run is scored. The judge reads the fixture
(frontmatter = answer key) and the `review-record.md` the reviewer produced, and
emits ONE compact JSON line. Reward catching the planted rule violations; punish
misses AND false alarms on clean code.

## Output

```json
{"planted":N,"caught":N,"false_positives":N,"verdict_match":0|1,"verdict":"PASS|FAIL"}
```

## Field definitions

- **planted** — number of entries in the fixture's `planted_issues` (0 for `clean`).

- **caught** — how many planted issues the reviewer flagged at the RIGHT severity or
  higher. Match by meaning, not string: a planted `{rule: no-throw, severity: P0}` is
  caught if the record has a P0 (or higher) finding about the raw `throw` violating
  the Result<T> convention. A planted issue rated below its planted severity (e.g.
  planted P0 flagged only as P2) is NOT caught. A `clean` fixture scores `caught: 0`.

- **false_positives** — findings that should not be there:
  - On a `clean` fixture: ANY P0 or P1 finding is a false positive. Count each.
  - On a violation fixture: P0/P1 findings that are neither a planted issue nor a
    genuine defect you can confirm in the code. Do NOT penalize a real extra finding;
    DO count invented/spurious ones and anything in `false_positive_watch`.

- **verdict_match** — decide by the fixture's `kind`, NOT a literal string compare:
  - `kind: clean` → `1` iff the reviewer's `**Verdict:**` is `PASS`.
  - `kind: violation` → `1` iff the reviewer's `**Verdict:**` is `FAIL` OR
    `PASS_WITH_FIXES` — both mean the planted issue was flagged and would gate. It is
    `0` ONLY if the reviewer gave a clean `PASS` (i.e. missed the issue). The reviewer
    legitimately varies — a P1-only change is `PASS_WITH_FIXES`, a P0 is `FAIL` — so do
    NOT require one specific value.

- **verdict** — holistic PASS for this fixture iff `caught == planted` AND
  `false_positives == 0` AND `verdict_match == 1`.

## Also weigh (fold into notes / false_positives)

- **Right rule, right severity.** Catching the `throw` but calling it P3 is a partial
  miss — the coder would not be forced to fix it. Treat a severity-downgrade of a
  planted P0/P1 as not-caught.
- **No convention invention.** The reviewer must judge against ReviewApp's actual
  `coding-standards.md` / `engineering-structure.md`, not generic opinions. A finding
  citing a rule that isn't in those files is a false positive.

## Discipline
- If the review-record is empty/malformed/missing: `caught:0, false_positives:0,
  verdict_match:0, verdict:"FAIL"`.
- Output ONLY the JSON line.
