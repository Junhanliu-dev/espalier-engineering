# Review Eval Harness

Dev/QA infrastructure for the `harness-reviewer` agent (and the `espalier-review`
skill). NOT shipped to target projects.

It answers: does the reviewer actually **catch** the convention / correctness /
layer-boundary violations it is supposed to — at the right severity — and **not**
false-positive on clean, convention-following code?

## Layout

```
eval/review/
├── README.md
├── rubric.md
├── run.sh
├── project/       canned ReviewApp conventions the fixtures are reviewed against
│   ├── coding-standards.md
│   └── engineering-structure.md
└── fixtures/      code changes with planted rule violations (+ clean ones)
```

## Run

```bash
bash eval/review/run.sh
```

Per fixture: builds a throwaway project (the change + the canned ReviewApp rules +
the review skill/agent), runs `harness-reviewer` headless, scores the produced
`review-record.md` with an LLM judge against `rubric.md`, aggregates. Gates on
catch-rate ≥ 0.80, zero false positives, and verdict accuracy.

## Fixture format

```yaml
---
fixture_id: rule-throw-01
kind: violation | clean
file: src/services/order-service.js
expected_verdict: FAIL | PASS
planted_issues:                    # empty for clean
  - rule: no-throw                 # a rule in project/coding-standards.md or engineering-structure.md
    severity: P0
    hint: raw `throw` instead of returning Result<T>
false_positive_watch:
  - ...
shadow: false
---
<the code file under review>
```

## Why the canned `project/`

Unlike security (a universal taxonomy), a reviewer's correctness is defined by the
PROJECT's conventions. `project/` pins a fixed, explicit rule set so fixtures can
plant checkable violations of named rules — and so the judge can reject findings
that cite a rule not in the project.

## Discipline (same as eval/grill, eval/security)

- Reach 20–30 fixtures. Seed is 8 (6 violation across the rule families — incl.
  the new-dependency P1 and the readability cryptic-exported-name P1 — + 2
  clean, one guarding minimalism-severity inflation).
- Shadow subset (~⅓) authored from real PRs / by non-authors. This seed is all
  `shadow: false`.
- Validate the judge (≥ 75% agreement), especially on severity-downgrade calls.
- Run on every edit to `harness-reviewer.md` or `espalier-review.md`.
