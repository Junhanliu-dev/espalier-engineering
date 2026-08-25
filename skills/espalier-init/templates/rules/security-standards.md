# Security Standards

> **The frontend is untrusted input. The backend is the trust boundary.** For any
> value that affects money, identity, permission, data ownership, or a persistent
> write: never trust what the client sent. Re-derive it from the session,
> re-authorize it against the actor, and recompute it from the source of truth
> before it is used in a decision or written to any persistent store. A value that
> arrived in a request is a *claim*, not a *fact*.

This rule is always loaded. `harness-coder` reads it before writing code,
`harness-security` audits against it, and `harness-reviewer` honors it. See
[[espalier-security]] for the audit checklist and abuse-test recipe.

## The Trust Boundary (this project)

{discovered at init — fill from the security scout; treat CURRENT CODE as ground truth}

- **Entry points** (where client data enters): {controllers / REST handlers / GraphQL resolvers / RPC / server actions / queue consumers — the surfaces this project actually uses}
- **Caller identity** (how the backend knows *who* is calling): {session / JWT / auth middleware — pattern + `file:line`}
- **Ownership enforcement** (how the backend proves the actor may touch an object): {pattern + example `file:line`, or "NONE FOUND — treat as a gap"}
- **Request validation** (where/what library validates input at the edge): {library + layer}

## Sensitive Field Taxonomy

A field is **sensitive** if it lands on any of these five risk axes. Sensitive
fields must never be trusted as sent by the client. The seed patterns are
universal; the discovered column is this project's own names.

| Risk axis | What it governs | Seed patterns (always sensitive) | Project-specific (discovered) |
|---|---|---|---|
| **money** | value / quantity that moves money or inventory | `price`, `amount`, `total`, `cost`, `fee`, `discount`, `balance`, `stock`, `quantity` | {discovered} |
| **identity** | who the actor *is* | `userId`, `accountId`, `customerId`, `sub`, actor `email` | {discovered} |
| **permission** | what the actor *may do* | `role`, `isAdmin`, `scope`, `permission`, `grants`, `plan`, `tier` | {discovered} |
| **owner** | which object the actor may touch | `orderId`, `cartId`, `ownerId`, `tenantId`, `projectId`, any resource id in path/body | {discovered} |
| **state** | server-controlled lifecycle | `status`, `state`, `approved`, `paid`, `verified`, `published` | {discovered} |

## Required Controls (per axis)

- **identity → re-derive from the session; never accept from the request.**
  `userId` / `accountId` / `sub` that identify the *actor* come from the
  authenticated session only — never from the request body or path. Do not merely
  "check" a client-supplied actor id (an attacker can send their own correct id and
  pass); refuse to accept it from the client at all.
- **owner → object-level authorization (defeats BOLA / IDOR).** Before reading or
  writing an *object* addressed by a client-supplied resource id, assert the session
  actor *owns* it or holds a role that permits it. A client-supplied id is a
  **lookup key, never an authorization**. Prefer a query scoped by owner
  (`find_where(id, ownerId=session.actor)`) so "not yours" and "not found" return
  the same 404 — no existence oracle. *(User 1's request carrying `cartId=2` must not
  return cart 2.)*
- **money → recompute from the source of truth.** Never persist a `price` / `amount`
  / `total` the client sent. Look the authoritative value up server-side (catalog,
  ledger, pricing service) and compute from that. A client-sent monetary value is
  display-only. *(A tampered `price=0.01` must be ignored, not charged.)*
- **permission → decide server-side; never bind from the body.** `role` / `isAdmin`
  / `scope` come from the session or an authorization store. Never mass-assign them
  from the request body. *(`isAdmin=true` in a profile update must not stick.)*
- **state → enforce the server-side state machine.** Validate both that the
  transition is legal *and* that this actor may perform it. A client cannot set
  `status=paid` / `approved` / `published` directly.
- **stock / balance → validate ranges and apply atomically.** Reject negative or
  over-limit quantities; check-and-decrement against the source of truth atomically
  — no read-then-write race that lets a value go negative.

## Mass Assignment

Never spread a raw request body into a persistence call
(`update(req.body)` / `Model(**request)` / `{...req.body}`). Bind an **explicit
allow-list** of client-settable fields. No field from the taxonomy above is ever
on that allow-list.

## Abuse Tests (required for every sensitive field a change touches)

A control is not trusted until a test proves it holds. For each sensitive field a
change reads or writes, there MUST be a negative test that:

1. **tampers** the value (foreign id, `$0.01` price, `isAdmin=true`, illegal status),
2. asserts the request is **rejected** (the project's convention — `403` / `404` /
   `422`), and
3. asserts the **persistent store is unchanged**.

The `harness-security` audit emits the exact list of fields requiring such a
test; the post-panel contract phase writes them and the contract delta
review blocks if any is missing (serial test-mode: Stage 5 writes, Stage 6
blocks).

## Project-Specific Security Conventions

{discovered at init — the security-relevant patterns THIS codebase already follows,
each backed by an example `file:line`. e.g. "every controller calls
`requireOwner(ctx, id)` before load", "prices come from `PriceService.quote()`",
"edge validation via zod schemas". If none found, say so — absence is itself a
finding the auditor should weigh.}
