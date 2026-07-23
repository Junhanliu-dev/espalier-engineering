---
name: espalier-review
description: >-
  Expert plan + code reviewer for {project}. Use in two spots — BEFORE
  implementation (plan review, gates the start) and AFTER (code review, before
  merge) — to check a change against {project}'s conventions, layer boundaries,
  and production-readiness standards. The code-review loop spawns the
  harness-reviewer agent. Triggers: "review this", "code review", "plan review",
  "check before merge", "is this ready to ship", "review the diff/PR".
---

# Expert Reviewer

## Two Review Loops

### 1. Plan Review — before implementation
- **When:** a plan / requirements exist, before any code is written.
- **Input:** the plan or `requirements.md` + the project rules.
- **Do:** check scope, layer placement, and the checklists below against the plan.
- **Output:** findings (format below) that gate the start of implementation.
- **Gate (pass condition):** zero P0/P1 findings against the current plan —
  P2/P3 are recorded, never blocking. On a non-pass, the plan is revised and
  re-reviewed; round counting and escalation are owned by pipeline Stage 2
  (`max-req-rounds`), not this skill.
- **Who:** runs inline — no agent spawned.

### 2. Code Review — after implementation, before merge
- **When:** the coder reports a change complete.
- **Input:** the diff + the coder's `coding-report.md` + the project rules.
- **Do:** spawn `harness-reviewer` (the canonical agent) — it runs the
  Runtime-Surface, Production-Readiness, and (advisory) Minimalism +
  Readability reviews and writes `review-record.md`.
- **Output:** `review-record.md` + a `VERDICT:` sentinel that gates the merge.
- **Gate (pass condition):** verdict `PASS`/`PASS_WITH_FIXES` with `p0=0 p1=0`
  on the sentinel — P2/P3 (minimalism + readability advisories included) are
  recorded, never blocking. On a non-pass, the coder fixes and the change is re-reviewed; round
  counting and escalation are owned by pipeline Stage 4 (`max-code-rounds`),
  not this skill.
- **Who:** `harness-reviewer`, re-spawned each fix round until the verdict is clean.

## Review Output Format
Each finding MUST include:
- Problem: what's wrong
- Fix: how to fix it
- Priority: P0 (blocker) / P1 (must fix) / P2 (should fix) / P3 (suggestion)

## Review Checklist (Project-Specific)
- [ ] Follows {project}'s naming conventions
- [ ] Error handling matches project pattern
- [ ] New code placed in correct layer/module
- [ ] No forbidden cross-layer dependencies
- [ ] {detected convention} is followed
- [ ] Tests cover the changed interface

## General Checks
- [ ] Correctness: Does it do what the requirement says?
- [ ] Consistency: Does it match existing patterns?
- [ ] Completeness: Edge cases handled?
- [ ] Leanness: nothing built beyond the requirement (no speculative
      abstraction/config); no NEW dependency where stdlib, a native feature, or
      an installed dependency covers it. Advisory P2/P3 except the new-dependency
      P1 — canonical rules in `espalier/agents/harness-reviewer.md` (Minimalism
      Review). Never flag a construct the rules/specs mandate.
- [ ] Readability: names state intent, judged against the project's own
      conventions — never personal taste. A cryptic EXPORTED/public name is the
      single P1; everything else advisory P2/P3 — canonical rules in
      `espalier/agents/harness-reviewer.md` (Readability Review).

## Production-Readiness Checks
`espalier/rules/production-standards.md` is the SINGLE SOURCE for these checks and
their severity tiers — do not restate severities here (they drift). Confirm each
that applies to the change:
- [ ] External calls carry a timeout + decided failure behaviour
- [ ] List queries on request paths are bounded/paginated; no N+1 on hot paths
- [ ] New endpoints/consumers emit a structured log — actor, entity id, outcome
- [ ] No swallowed errors; persistence-path failures never continue as success
- [ ] Migrations follow expand → migrate → contract; destructive steps requirement-authorized
- [ ] Mutating consumers/webhooks are idempotent under redelivery

Severity tier for any gap: read it from the rule, not this list. The code-review
loop delegates enforcement to `harness-reviewer` (Production-Readiness Review).

## Output Template

The CANONICAL output format (columns, verdict vocabulary, sentinel line) is
defined in `espalier/agents/harness-reviewer.md` — that file wins on any
disagreement. Shape:

### Review: {what was reviewed}
| # | Priority | File | Problem | Fix |
|---|----------|------|---------|-----|
| 1 | P0 | path/file.ext | ... | ... |
| 2 | P1 | path/file.ext | ... | ... |

**Verdict:** PASS / PASS_WITH_FIXES / FAIL / ESCALATION_REQUIRED
(ESCALATION_REQUIRED is fix-lane-only — see the agent file for when.)
