# Wiki Templates

Wiki is **on-demand context** — agent queries it when needed, not loaded by default.
Populate from what's discoverable in code.

## wiki/architecture.md
- High-level system diagram (text-based)
- How requests flow through the system
- Key patterns (e.g., event-driven? request-response? CQRS?)

## wiki/data-models.md
- Core entities and their relationships
- Where schemas are defined
- Migration patterns

## wiki/critical-paths.md
- The most important business flows
- Which files/modules they touch
- Common modification points

## wiki/external-services.md
- All external dependencies (databases, APIs, queues, caches)
- How they're configured
- Timeout/retry/fallback patterns in use

---

## Greenfield-only wiki files

Written during Phase 2 ONLY when the project came through the greenfield
flow (`references/greenfield.md`). Both participate in drift detection
like any other wiki artifact.

## wiki/product-brief.md
- What the product does, for whom (Round 1 answers, in full sentences)
- Audience + expected scale
- Auth / realtime / payments / integration needs and their status
- Seeds future `/espalier` Stage 1 grills — keep it current via
  `/espalier-prune` as the product pivots

## wiki/stack-decisions.md
- One entry per decision: **what** was chosen, **why** (tied to brief),
  **alternatives rejected** and why not, **decided-by** (user · express
  default · research), **verified** (date + source for scaffolder syntax)
- Deploy target + first-deploy record (URL, date) when guided deploy ran
- BYO-stack research findings land here too (cheaper next run)
