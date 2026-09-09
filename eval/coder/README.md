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
bash eval/coder/run.sh                      # full suite — the release gate
KEEP_WORK=1 bash eval/coder/run.sh 'coder-06*.md'   # keep the throwaway projects (their git history — the v0.25 coder commits its units — reports, and <fixture>.agent.log) for a partial debug run
```

Pin the model when the session default is a headless-refusing tier
(`ANTHROPIC_MODEL=opus`), and run the A/B baseline (old templates + old
fixtures under today's model) before attributing a regression — see
`docs/context-benchmark-v0.25.md` for the 2026-09-09 run. The diff the judge
scores is taken from the runner's baseline commit, not the index, because
the coder commits as it goes.

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

## v0.25 disclosure fixtures (opt-in keys)

Frontmatter keys added with the quality-first context plan
(`docs/quality-first-context-plan.md` §7). Fixtures without them run exactly as
before, so the seed set's baseline is untouched.

| key | effect |
|---|---|
| `spec: services` | copies `project/specs/services.md` into the throwaway project's `espalier/skills/espalier-coding/specs/`, names it in a pack-style prompt line, and script-checks the report's `- Spec applied:` line names an existing section (`spec-line=ok / none / missing / bad-section` in the results). `SPEC_LINE=gate` (default — the v0.25 coder template writes the line) fails the fixture on `missing` / `bad-section`; `SPEC_LINE=report` only prints it (set it when the A/B baseline runs a pre-v0.25 template). Every `- Spec applied:` line is checked (one per touched layer): a line saying `none — no spec for {layer}` counts as none; otherwise every section it cites (`§ A / B, C`, `§ A and § B`) must be a heading of the spec; the result is `ok` when at least one layer line cites real sections and none cites a wrong one |
| `scoped_doc: services` | copies `project/scoped/services/CLAUDE.md` (traps and invariants) to `src/services/CLAUDE.md` and names it in the prompt; the fixture's `must_follow` carries the traps so the judge scores whether they were avoided |
| `extra_files: order-status.js` | copies `project/extra/<file>` into `src/services/` |
| `handoff_allowed: true` | a report ending in `- HANDOFF: true` is a PASS iff its `## Handoff` block has `- Remaining:`, `- Facts:` with at least one `path:line`, and every touched `.js` passes `node --check`; on any other fixture a handoff sentinel is a FAIL |
| `pending_template: vX.Y` | skipped unless `INCLUDE_PENDING=1` — for fixtures that need a template feature not yet shipped |

Seed: `coder-06-scoped-doc-trap` (spec + scoped doc, single seam) and
`coder-07-two-seam` (services + controllers; finishes or hands off).

## Discipline
- Reach 20–30 fixtures. Seed is 5 (a service method, an external-call timeout, a
  scope-guard, an overbuild trap, and a `folded: true` code+tests task — the
  v0.23 folded coder duty; the judge then also scores `tests_written` /
  `tests_meaningful`). All `shadow: false`.
- Shadow subset from real tickets once the set grows.
- Validate the judge heavily — generative scoring is the least reliable; confirm
  agreement with hand scores before trusting the gate.
- Run on every edit to `harness-coder.md` or `espalier-coding.md`.
