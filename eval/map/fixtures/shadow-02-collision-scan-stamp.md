---
fixture_id: shadow-02-collision-scan-stamp
mode: work
target_ticket: 003
max_open_tickets: 9
# Shadow decision-mode Step 1.5 collision test, planted from a real epic
# decision (how a team-wide maintenance scan gets recorded). The ticket's
# OBVIOUS candidate ("have the post-merge hook append a row to a tracked
# scan-log so it propagates automatically") collides twice with the
# project's own map: a rule collision (hooks never write tracked files)
# and a wiki duplication (a documented per-clone scan stamp already
# exists). Coverage counts a collision only when it is surfaced WITH its
# citation before the decision locks. coverage_only per the rubric.
coverage_only: true
planted_decisions: []
planted_collisions:
  - doc: rules/automation-boundaries.md#tracked-writes
    kind: rule-collision
    resolves_to: hooks and automation never write tracked files — the scan record is written by the deliberate scan step as its own commit, never by a hook
  - doc: wiki/dev-tooling.md#scan-stamps
    kind: wiki-duplication
    resolves_to: a gitignored per-clone scan stamp (.docscan-last-run) already exists — the tracked team record must define its relationship to it (team fact vs per-clone fact), not silently duplicate it
expected_behavior: >
  Ticket 003's Resolution records the decision WITH both citations; exactly
  one ticket resolved; no code written.
answer_script:
  - asks_about: hook-appends-tracked-log vs the automation-boundaries rule — reconcile
    reply: keep the rule — the scan step itself writes a one-line tracked stamp as its own commit; hooks stay read-only on tracked files
  - asks_about: relationship to the existing per-clone stamp
    reply: keep both — the tracked stamp is the team-wide fact and the gitignored stamp stays per-clone; a scan that ends with unresolved findings satisfies only the clone that ran it
shadow: true
---
Work the map below. Ticket to work: 003.

## MOCK CONTEXT

The following is the entire `espalier/rules/` and `espalier/wiki/` for this project.

### espalier/rules/automation-boundaries.md

```markdown
# Automation Boundaries

## Tracked writes
No hook or background automation ever writes a tracked file. Tracked files
change only through a deliberate, human-gated step that commits its own
work. Hooks may write gitignored state under `tooling/state/` only. This
is the invariant every maintenance mechanism in this repo is built on.
```

### espalier/wiki/dev-tooling.md

```markdown
# Dev Tooling

## Scan stamps
The doc-health scanner records its last run in `tooling/state/.docscan-last-run`
— gitignored, one line, per-clone. Reminder logic reads this stamp; nothing
else writes it. There is currently no team-wide record of a scan.
```

## MOCK MAP

The following is the entire `espalier/maps/2026-08-07-maintenance-model/`.

### map.md

```markdown
---
map: 2026-08-07-maintenance-model
status: IN_PROGRESS
started: 2026-08-07T09:00:00Z
---

# Map: Team maintenance model for the docs garden

## Destination

A locked spec for how the generated docs dir stays correct under ~10
concurrent devs — cadence, ownership, and run-recording decided.

## Notes

TypeScript monorepo. Consult espalier-grill for grilling tickets.

## Decisions so far

- [001 — Scan cadence](tickets/001-scan-cadence.md) — weekly
- [002 — Who runs the scan](tickets/002-scan-owner.md) — one rotating owner per week

## Not yet specified

- whether rule edits need an owner/review gate

## Out of scope

- rewriting the doc-generation pipeline itself

## Session log

| Date | Ticket | Action |
|------|--------|--------|
| 2026-08-07 | 001 | resolved |
| 2026-08-07 | 002 | resolved |

## Spawned Changes

| Change | Status |
|--------|--------|
```

### tickets/001-scan-cadence.md

```markdown
---
ticket: 001
title: Scan cadence
type: grilling
status: closed
blocked_by: []
claimed_by: dev@example.com
claimed_at: 2026-08-07T09:05:00Z
---

## Question

How often must the doc-health scan run — per-merge, weekly, or monthly?

## Resolution

Weekly. Per-merge is too noisy at 10 devs; monthly lets drift age past the
point where refresh is cheap.
```

### tickets/002-scan-owner.md

```markdown
---
ticket: 002
title: Who runs the scan
type: grilling
status: closed
blocked_by: [001]
claimed_by: dev@example.com
claimed_at: 2026-08-07T09:40:00Z
---

## Question

Everyone redundantly, first-to-hit-the-reminder, or a named owner?

## Resolution

One rotating owner per week. "Whoever notices" was tried and the scan
never ran.
```

### tickets/003-scan-record.md

```markdown
---
ticket: 003
title: How a completed scan is recorded for the team
type: grilling
status: open
blocked_by: [002]
claimed_by:
claimed_at:
---

## Question

Teammates currently can't see that this week's scan happened, so the
reminder nags everyone anyway. Where does the "a scan ran, and was the
tree clean" fact live? The team's first instinct: have the post-merge
hook append a row to a tracked `scan-log.tsv` so the record propagates
to every clone automatically.
```
