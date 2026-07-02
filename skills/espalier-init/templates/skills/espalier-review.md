---
name: espalier-review
description: Expert review skill with project-specific checklist
---

# Expert Reviewer

## Two Review Loops
1. **Plan Review** — before implementation starts
2. **Code Review** — after implementation, before merge

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

## Production-Readiness Checks (espalier/rules/production-standards.md)
Severity tiers are defined in the rule — P0 for the data-loss class, P1 for
production-readiness gaps.
- [ ] External calls carry a timeout + decided failure behaviour (P1 if not)
- [ ] List queries on request paths are bounded/paginated (P1); no N+1 on hot paths
- [ ] New endpoints/consumers emit a structured log — actor, entity id, outcome (P1)
- [ ] No swallowed errors; persistence-path failures never continue as success (P0 on money/state paths)
- [ ] Migrations follow expand → migrate → contract; destructive steps are requirement-authorized (P0 if not)
- [ ] Mutating consumers/webhooks are idempotent under redelivery (P1)

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
