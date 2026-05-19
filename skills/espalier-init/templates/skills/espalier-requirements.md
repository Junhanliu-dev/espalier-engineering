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

Rule: Each sub-task should touch ≤ 5 files. If more, decompose further.

## Process
1. Read the requirement carefully
2. Read relevant wiki/ files for business context
3. Read engineering-structure.md to understand affected modules
4. Ask clarifying questions if acceptance criteria are ambiguous
5. Produce the structured output above

## Anti-Patterns
- NEVER start coding without acceptance criteria
- NEVER assume scope — ask if unclear
- NEVER combine unrelated changes in one requirement
