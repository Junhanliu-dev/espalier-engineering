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
