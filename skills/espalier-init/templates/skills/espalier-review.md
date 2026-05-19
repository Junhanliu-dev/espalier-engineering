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
- [ ] External calls have timeout/fallback (if applicable)
- [ ] Tests cover the changed interface

## General Checks
- [ ] Correctness: Does it do what the requirement says?
- [ ] Consistency: Does it match existing patterns?
- [ ] Completeness: Edge cases handled?
- [ ] Performance: No obvious N+1, unbounded queries?

## Output Template

### Review: {what was reviewed}
| # | Priority | Problem | Fix |
|---|----------|---------|-----|
| 1 | P0 | ... | ... |
| 2 | P1 | ... | ... |

**Verdict:** PASS / PASS WITH FIXES / FAIL
