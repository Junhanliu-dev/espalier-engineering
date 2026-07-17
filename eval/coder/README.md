# Coder Eval Harness

Dev/QA infrastructure for the `harness-coder` agent (and the `espalier-coding`
skill). NOT shipped to target projects.

It answers: does the coder actually WRITE code that follows the project's
conventions, implements the task, and — critically — **does not over-scope**
(the failure mode the coder's own "one task at a time" rule targets)?

This is a **generative** eval (unlike review/security, which are analytical), so
it is inherently fuzzier: the judge scores the code the coder produced against the
fixture's answer key. Treat the gate as provisional and hand-validate the judge
more heavily than the analytical harnesses.

## Layout

```
eval/coder/
├── README.md
├── rubric.md
├── run.sh
├── project/       canned CoderApp conventions + a reference implementation
│   ├── coding-standards.md
│   ├── engineering-structure.md
│   └── reference/user-service.js
└── fixtures/      tasks with a must_follow / must_not answer key
```

## Run

```bash
bash eval/coder/run.sh
```

Per fixture: builds a throwaway git project (conventions + reference file + coding
skill/agent), runs `harness-coder` headless on the task, captures the git diff of
what it wrote + its coding-report, scores with an LLM judge, aggregates. Gates on
pass-rate ≥ 0.80 with zero over-scope.

## Fixture format

```yaml
---
fixture_id: coder-01-cancel-order
kind: task
target_file: src/services/order-service.js
must_follow:
  - returns Result<T, AppError> (no throw)
  - placed in the services/ layer
  - uses the injected logger
must_not:
  - modifies controllers/ or repositories/ files
  - adds behavior beyond the requested function
shadow: false
---
<the task / requirement text>
```

## Discipline
- Reach 20–30 fixtures. Seed is 4 (a service method, an external-call timeout, a
  scope-guard, an overbuild trap). All `shadow: false`.
- Shadow subset from real tickets once the set grows.
- Validate the judge heavily — generative scoring is the least reliable; confirm
  agreement with hand scores before trusting the gate.
- Run on every edit to `harness-coder.md` or `espalier-coding.md`.
