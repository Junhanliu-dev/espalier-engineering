# Coding Standards (ReviewApp — eval fixture project)

These are the canned conventions the review-eval fixtures are authored against. A
fixture's planted violations reference these rules by name.

## Error Handling Pattern
Every fallible function returns `Result<T, AppError>` — it NEVER `throw`s. Callers
handle both the `ok` and `err` branch. A raw `throw` in application code is a **P0**.

## Naming Conventions
| Element | Convention | Example |
|---------|-----------|---------|
| files | kebab-case | `user-service.js` |
| functions | camelCase, verb-first | `getUser`, `createOrder` |
| constants | SCREAMING_SNAKE_CASE | `MAX_RETRIES` |

## Required Patterns
- Every external / network call has an explicit timeout (`TIMEOUT_MS`). No unbounded
  `await` on I/O. A missing timeout on an external call is a **P1**.
- Input at a boundary is validated with the `validate()` helper before use.

## Forbidden Patterns
- No `console.log` in application code — use the injected `logger`. A `console.log`
  is a **P1**.
- No swallowed errors (`catch {}` with an empty body). A **P1**.
