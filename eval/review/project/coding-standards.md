# Coding Standards (ReviewApp — eval fixture project)

These are the canned conventions the review-eval fixtures are authored against. A
fixture's planted violations reference these rules by name.

## Error Handling Pattern
**Service and repository** functions return `Result<T, AppError>` — they NEVER
`throw`. A raw `throw` in a service/repository is a **P0**. Controllers are the HTTP
boundary: they return an HTTP response (`res`) and translate a service's Result into
a status code — a controller is NOT required to itself return `Result<T>`.

## Naming Conventions
| Element | Convention | Example |
|---------|-----------|---------|
| files | kebab-case | `user-service.js` |
| functions | camelCase, verb-first | `getUser`, `createOrder` |
| constants | SCREAMING_SNAKE_CASE | `MAX_RETRIES` |

## Required Patterns
- Every **external HTTP call** (`fetch` / a third-party SDK) applies an explicit
  timeout (`TIMEOUT_MS` / `AbortController`). A missing timeout on such a call is a
  **P1**. Repository / `db` calls are internal and do NOT require a timeout.

## Forbidden Patterns
- No `console.log` in application code — use the injected `logger`. A `console.log`
  is a **P1**.
- No swallowed errors (`catch {}` with an empty body). A **P1**.

## Readability
- A name states what it holds or does — a reader can tell without opening the
  body. An EXPORTED symbol (`module.exports`, a route path) with an opaque or
  misleading name is a **P1**. An opaque INTERNAL local is advisory (P2/P3)
  only — never P0/P1.
