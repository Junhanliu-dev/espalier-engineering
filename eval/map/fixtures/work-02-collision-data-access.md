---
fixture_id: work-02-collision-data-access
mode: work
target_ticket: 004
max_open_tickets: 9
# Decision-mode Step 1.5 collision test. The ticket's OBVIOUS candidate
# ("just add Prisma calls in the route handlers") collides twice with the
# project's own map: a rule collision (repository-pattern mandate) and a
# wiki duplication (a documented data-access module already wraps pg).
# Coverage counts a collision only when it is surfaced WITH its citation
# before the decision locks. coverage_only per the rubric.
coverage_only: true
planted_decisions: []
planted_collisions:
  - doc: rules/engineering-structure.md#data-access
    kind: rule-collision
    resolves_to: all persistence goes through a repository class in src/repositories/ — route handlers never touch the DB client directly
  - doc: wiki/external-services.md#postgres
    kind: wiki-duplication
    resolves_to: reuse the documented db module (src/db/index.ts pool wrapper) inside repositories — do not introduce a second client/ORM without deciding its relationship to the existing pool
expected_behavior: >
  Ticket 004's Resolution records the decision WITH both citations; exactly
  one ticket resolved; no code written.
answer_script:
  - asks_about: repository rule vs direct ORM calls in handlers — reconcile
    reply: follow the repo's rule — repositories it is; I didn't know that convention existed
  - asks_about: existing db module vs introducing Prisma
    reply: keep the existing pg pool for v1 — revisit an ORM only if repository code gets unwieldy
shadow: false
---
Work the map below. Ticket to work: 004.

## MOCK CONTEXT

The following is the entire `espalier/rules/` and `espalier/wiki/` for this project.

### espalier/rules/engineering-structure.md

```markdown
# Engineering Structure

## Data access
All persistence goes through a repository class in `src/repositories/`
(one per aggregate). Route handlers and services NEVER touch the database
client directly — they call repository methods. This is the layer boundary
the post-edit hook enforces.
```

### espalier/wiki/external-services.md

```markdown
# External Services

## Postgres
Single Postgres instance. Access is through `src/db/index.ts` — a pg `Pool`
wrapper with retry + slow-query logging. Every repository imports this
module; nothing else opens connections.
```

## MOCK MAP

The following is the entire `espalier/maps/2026-08-06-usage-metering/`.

### map.md

```markdown
---
map: 2026-08-06-usage-metering
status: IN_PROGRESS
started: 2026-08-06T10:00:00Z
---

# Map: Usage metering + billing export

## Destination

A locked spec for per-account usage metering with a monthly billing export.

## Notes

TypeScript service. Consult espalier-grill for grilling tickets.

## Decisions so far

- [003 — Metering granularity](tickets/003-granularity.md) — per API call, aggregated hourly

## Not yet specified

- export file format for the billing system

## Out of scope

## Session log

| Date | Ticket | Action |
|------|--------|--------|
| 2026-08-06 | 003 | resolved |

## Spawned Changes

| Change | Status |
|--------|--------|
```

### tickets/003-granularity.md

```markdown
---
ticket: 003
title: Metering granularity
type: grilling
status: closed
blocked_by: []
claimed_by: dev@example.com
claimed_at: 2026-08-06T10:05:00Z
---

## Question

Per-call, per-minute, or per-hour aggregation?

## Resolution

Per API call, aggregated hourly for storage.
```

### tickets/004-storage-approach.md

```markdown
---
ticket: 004
title: How metering data is stored and accessed
type: grilling
status: open
blocked_by: [003]
claimed_by:
claimed_at:
---

## Question

Where do hourly usage rows live and how does the service write/read them —
new table via our stack, or something faster? The team's first instinct is
to add Prisma and write from the route handlers directly.
```
