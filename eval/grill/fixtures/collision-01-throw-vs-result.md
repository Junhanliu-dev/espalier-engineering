---
fixture_id: collision-01-throw-vs-result
mode: spec
expected_tier: light
# Text signals alone are ~0 (the requirement is crisp). The tier is FLOORED to light by the
# Step 1.5 rule collision: the requirement says "throw", but the project's coding-standards
# mandate Result<T>. A collision fixture is a coverage test (rubric dimension 6): value is
# the collision surfaced AND cited, not the question's non-obviousness.
expected_signals: 0
coverage_only: true
planted_ambiguities: []
planted_collisions:
  - doc: rules/coding-standards.md#error-handling
    kind: rule-collision
    resolves_to: return Result<T> (never throw across a module boundary) per coding-standards
answer_script:
  - asks_about: coding-standards mandates Result<T> but the requirement says throw — reconcile
    reply: right, follow the convention — return Result<InvalidEmail> and never throw; I didn't know that rule existed
shadow: false
---
feat: add a validateEmail(input) helper that throws an error when the address is invalid

## MOCK CONTEXT

The following is the entire `espalier/rules/` and `espalier/wiki/` for this project.

### espalier/rules/coding-standards.md

```markdown
# Coding Standards

## Error Handling
Every fallible function returns `Result<T>` (`{ ok: true, value } | { ok: false, error }`).
Code MUST NOT `throw` across a module boundary — throwing is reserved for truly
unrecoverable programmer errors (assertion failures), never for expected validation
outcomes. Callers pattern-match on the `Result`; they never wrap calls in try/catch.

## Naming
camelCase for functions, PascalCase for types.
```

### espalier/wiki/architecture.md

```markdown
# Architecture
A single TypeScript service. Validation helpers live in `src/validation/` and are pure —
they take input and return a `Result<T>`. No helper in this directory throws.
```
