---
name: espalier-requirements
description: Requirements analysis skill - decompose requirements into actionable specs
---

# Requirements Analysis

## Purpose
Transform a user requirement into a structured specification that coding and review
agents can execute against without ambiguity.

## Output Format

For every requirement, produce:

### 1. Requirement Summary
- **What:** One sentence describing the feature/fix
- **Why:** Business motivation
- **Who:** Affected users/systems

### 2. Acceptance Criteria
List concrete, verifiable conditions:
- [ ] When {action}, then {expected result}
- [ ] {boundary condition} is handled by {behavior}
- [ ] {error case} results in {specific response}

### 3. Scope Definition
- **In scope:** {exactly what will be changed}
- **Out of scope:** {explicitly excluded to prevent scope creep}
- **Files likely touched:** {predicted based on architecture knowledge}
- **Layers involved:** {which architectural layers}

### 4. Technical Considerations
- Dependencies on external services?
- Data model changes needed?
- Breaking changes / backwards compatibility?
- Performance implications?

### 5. Task Decomposition
Break into sub-tasks that each fit in one agent context window:
1. {Sub-task 1} — estimated files: {N}
2. {Sub-task 2} — estimated files: {N}
3. ...

Size each sub-task as one coder's bounded work — one seam: a schema list
with its hooks and tests; one screen with its hook and its GraphQL
documents; one resolver with its abuse tests. The test of a good size is
that a coder starting fresh finishes it with its instructions still at
full strength. When unsure, split: a second spawn costs one context-pack
read; a spawn that runs past its attention costs a review round. Test
writing splits the same way at Stage 3 — one spawn per test-file group.
The contract phase stays one spawn; a contract too large for one spawn
hands off (the coder's Handoff protocol). Splitting changes DISPATCH only:
the panel still reviews the COMBINED diff once.

### Contract and notes (what requirements.md holds)

The five sections above — plus `## Open Questions`, `## Convention Notes`,
and `## Retired Surface` when a simplify cut filed the change — are the
CONTRACT: what the coder builds to, what the reviewer checks against, the
text the human approves at the Requirements Approval Gate. Derivation,
alternatives considered, what was settled for next time, and the grill's
full question-and-answer record go to `requirements-notes.md` in the same
change directory, under the same headings, linked once from the Requirement
Summary as `Notes: requirements-notes.md`. Frontmatter is unchanged. The
Stage 2 review files a heading outside the contract set as a P2 with Fix =
"move to requirements-notes.md"; before the first coder spawn the
orchestrator prints the same list (`req_shape_check`) as information only —
nothing is refused on size, the human approved this text.

## Process
1. Read the requirement carefully
2. Read relevant wiki/ files for business context
3. Read engineering-structure.md to understand affected modules
4. Produce the structured output above — draft the FULL requirements doc first,
   so the grill has a document for its inline writes to land in (same order as
   the fix lane: draft, then grill).
5. **Grill the requirement.** Unless the pipeline passed `--no-grill`, invoke the
   `espalier-grill` skill in `spec` mode on the draft. Grill interrogates the
   requirement (adaptive depth — it may skip a crisp one) and writes resolved
   decisions into the Acceptance Criteria and Scope Definition sections above.
   Record its verdict (`GRILLED (light)` / `GRILLED (full)` /
   `SKIPPED: <reason>`) — the orchestrator logs it to pipeline-state.md.

## Anti-Patterns
- NEVER start coding without acceptance criteria
- NEVER assume scope — ask if unclear
- NEVER combine unrelated changes in one requirement
