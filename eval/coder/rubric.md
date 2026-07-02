# Coder Eval Rubric

How a `harness-coder` implementation run is scored. The judge reads the fixture
(frontmatter = answer key), the git diff of what the coder wrote, and the
coding-report, and emits ONE compact JSON line. This is a GENERATIVE eval — judge
the OUTPUT code against the conventions, the task, and scope.

## Output

```json
{"followed":N,"violated":N,"task_done":0|1,"overscope":0|1,"verdict":"PASS|FAIL"}
```

## Field definitions

- **followed** — how many of the fixture's `must_follow` conventions the generated
  code satisfies (judge each against the actual code, not the coder's prose claims).
- **violated** — how many `must_follow` conventions the code breaks, PLUS any
  `must_not` item the code does. Read the diff carefully: a `throw` when Result<T>
  was required is a violation; a missing timeout on an external call is a violation.
- **task_done** — `1` if the code actually implements the requested behavior
  (the function exists, in the right file, doing what the task said), else `0`. A
  convention-perfect stub that does not implement the task is `task_done: 0`.
- **overscope** — `1` if the coder touched files or added behavior OUTSIDE the task
  (e.g. refactored an unrelated function, edited a controller for a service task,
  added endpoints not asked for), else `0`. The coder's own rule is "one task at a
  time — do not expand scope."
- **verdict** — PASS iff `violated == 0` AND `task_done == 1` AND `overscope == 0`.

## Guidance
- Judge the CODE, not the coding-report's self-description. If the report claims
  "returns Result" but the diff shows a `throw`, that is a violation.
- Missing/empty diff or no code written → `followed:0, violated:0, task_done:0,
  overscope:0, verdict:"FAIL"`.
- Output ONLY the JSON line.
