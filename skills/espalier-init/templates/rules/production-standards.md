# Production Standards

> Code that reaches Stage 7 runs in production. For any code path that calls an
> external system, serves a request, moves data, or changes a schema: it must
> stay **debuggable when it breaks, bounded when it grows, and safe when it is
> retried or rolled back.** These seeds are universal — they hold regardless of
> what init discovered. The `{discovered}` columns carry THIS project's own
> mechanisms; when a discovered mechanism exists, use it — never invent a
> parallel one.

This rule is always loaded. `harness-coder` applies it while writing,
`harness-reviewer` enforces it with the severity tiers below. It complements
[[security-standards]] (trust boundary) — this rule is about staying up and
losing nothing; that one is about hostile input.

## Severity Tiers (how the reviewer files a violation)

- **P0 — data-loss class (hard-blocks the Stage 4 fixpoint loop):** a
  destructive or irreversible migration without explicit sign-off; an unbounded
  write/delete path (no limit, no scoping predicate); an error swallowed on a
  money / state / persistence path (failure continues as if it succeeded).
- **P1 — production-readiness class (must fix before Stage 7):** missing
  timeout or failure handling on an external call; unbounded list query on a
  request path; missing structured log on a new endpoint/consumer; a mutating
  consumer/webhook that is not idempotent; read-modify-write on shared mutable
  state across a request boundary; unbounded fan-out (N calls in a loop) on a
  request path.
- **P2/P3** — improvements (better log context, tighter bounds), not blockers.

A P1 loops the panel via the verdict word: the security auditor and the
reviewer both emit `FAIL` while any P0 **or P1** is open, and the gate
re-spawns the coder on any non-PASS verdict — so P1s are fixed before Stage 7
by construction, sharing the same `max-code-rounds` counter. Nothing above P2
may be waved through on "it works".

## Resilience (universal seeds)

| Concern | Required | Project mechanism (discovered) |
|---|---|---|
| External calls (HTTP/RPC/DB/queue/third-party SDK) | explicit **timeout** + a decided **failure behaviour** (retry with backoff, fallback, or propagate-with-context — chosen, not defaulted) | {discovered — e.g. "axios instance in src/lib/http.ts carries timeout+retry; use it"} |
| List/collection reads on request paths | **bounded** — pagination, limit, or a hard cap; no "return the whole table" | {discovered pagination helper / convention} |
| Shared mutable state (counters, balances, stock, statuses) | applied **atomically** at the store (transaction, atomic op, optimistic lock) — never read-modify-write across a request boundary | {discovered — transaction helper, ORM pattern} |
| Fan-out (N calls in a loop) | bounded concurrency or batching on request paths; no unbounded `Promise.all` over user-sized input | {discovered} |

## Observability (universal seeds)

| Concern | Required | Project mechanism (discovered) |
|---|---|---|
| New endpoint / handler / consumer | at least one **structured log** with enough context to debug a 3am page: actor (who), entity id (what), outcome (result/error). Use the project's logger — never `console.log` / `print` if a logger exists | {discovered logger + format, from coding-standards} |
| Errors | **never swallowed** — an empty catch, a caught-and-ignored promise rejection, or a bare `except: pass` on a code path that matters is a defect. Failures log at error level WITH the cause, then follow the project's error pattern | {discovered error pattern} |
| Failure visibility | a failed external call or consumer message must be distinguishable from "never ran" in the logs | {discovered — metrics/trace conventions if any} |

## Data Safety (universal seeds)

| Concern | Required | Project mechanism (discovered) |
|---|---|---|
| Schema migrations | **expand → migrate → contract.** New columns nullable-or-defaulted first; code ships reading both shapes; destructive steps (drop/rename/narrow) land in a LATER change after the code no longer needs the old shape | {discovered migration tool + how the project sequences} |
| Destructive operations (drop, bulk delete, truncate, irreversible transform) | require an explicit line in requirements.md acceptance criteria — a migration the requirement never asked for is a **P0** | — |
| Mutating consumers / webhooks / retried jobs | **idempotent** — a redelivered message or retried job must not double-apply (dedupe key, upsert, or idempotency token) | {discovered — queue semantics, idempotency helpers} |
| Backfills / data transforms | resumable and bounded (chunked, progress-tracked) — never one unbounded UPDATE over a production table | {discovered} |

## Failure-Mode Tests (Stage 5 duty)

Production code is proven by how it fails, not only how it succeeds. For each
NEW external-call path the change introduces, Stage 5 writes at least one
failure-mode test: the dependency times out / errors / returns garbage → assert
the decided failure behaviour happens (fallback used, error propagated with
context, no partial write persisted). Missing failure-mode coverage on a new
external call is a **P1** at Stage 6. (Abuse tests for sensitive fields are the
[[security-standards]] contract — this is additional, not instead.)

## Project-Specific Production Conventions

{discovered at init — the resilience/observability/data-safety patterns THIS
codebase already follows, each backed by an example `file:line`. e.g. "all
external calls go through `src/lib/http.ts` (10s timeout, 2 retries)", "every
handler logs via `logger.child({requestId})`", "migrations follow
expand/contract — see migrations/0042". If none found, say so — the auditor
weighs absence as risk, and the seeds above still bind.}
