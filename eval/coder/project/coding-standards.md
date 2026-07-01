# Coding Standards (CoderApp — eval fixture project)

The conventions generated code is judged against. A reference implementation lives
at `src/services/user-service.js` — new code should look like it.

## Error Handling Pattern
Every fallible function returns `Result<T, AppError>` (`{ ok: true, value }` /
`{ ok: false, err }`). It NEVER `throw`s.

## Naming
files kebab-case; functions camelCase verb-first; constants SCREAMING_SNAKE_CASE.

## Required
- External HTTP calls (`fetch` / a third-party SDK) use an explicit timeout
  (`TIMEOUT_MS` / `AbortController`). Repository / `db` calls do not.
- Use the injected `logger`, never `console`.

## Layers (see engineering-structure.md)
- `services/` may import `repositories/`; `controllers/` call services, never `db`.
