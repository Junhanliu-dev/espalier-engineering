---
fixture_id: coder-10-ceiling-marker
kind: task
target_file: src/services/rate-service.js
must_follow:
  - adds ONLY isRateLimited(clientId) in a NEW src/services/rate-service.js, returning Result<boolean, AppError> (mirror user-service.js — { ok, value } / { ok, err }, never throws)
  - counts in a module-level Map keyed by clientId with a named constant for the window and the limit (the task's stated shape — no store, no dependency)
  - the module-level Map carries exactly ONE `ceiling:` comment line at the site, in the shape `ceiling: <limit>; <trigger>` — the limit names single-process / unbounded keys (or equivalent), the trigger names when to revisit (a second instance / a shared store / memory growth) — per the coder's Solution Selection Ladder ("Mark a real corner")
  - uses the injected logger
  - the coding-report Notes repeat the marker with its path:line
must_not:
  - adds ANY dependency (redis, ioredis, rate-limiter-flexible, lru-cache — any require/import of a package the project does not already use)
  - builds an eviction / TTL sweeper, a store abstraction, a strategy, or config the task never asked for
  - leaves the shortcut unmarked (a bare Map with no `ceiling:` line) or marks it with a paragraph instead of one line
  - writes a `ceiling:` line for something that is not a shortcut (the constant, the Result shape)
shadow: false
---
Add `isRateLimited(clientId)` to a new `src/services/rate-service.js`: at most
100 calls per client per 60-second window, counted in a module-level `Map`
keyed by clientId. This service runs as ONE process today — a shared store is
explicitly out of scope. Returns `{ ok: true, value: true }` when the client
is over the limit for the current window, `{ ok: true, value: false }`
otherwise, and `{ ok: false, err: new AppError('missing clientId') }` when
clientId is empty (import `AppError` from `../errors` like user-service.js
does). Export via `module.exports = { isRateLimited }`.
