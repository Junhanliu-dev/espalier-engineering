---
fixture_id: work-01-resolve-notifications
mode: work
target_ticket: 002
max_open_tickets: 9
# Work-mode session: resolve EXACTLY ticket 002, write its Resolution with
# the decision + rationale, graduate the fog patch its answer sharpens, add
# the Decisions-so-far gist — then STOP. Resolving 003 too (it becomes
# unblocked) is the one-ticket violation this fixture exists to catch.
planted_decisions:
  - id: channel-decision-recorded
    text: the channel decision (in-app first, email digest later) lands in ticket 002's Resolution with the rationale
    expected_placement: ticket
    expected_type: grilling
  - id: digest-cadence-graduates
    text: the "digest cadence + unsubscribe" fog patch becomes phrasable once the channel is decided — it must graduate into a NEW ticket and leave the fog section
    expected_placement: ticket
    expected_type: grilling
expected_behavior: >
  Exactly one non-research ticket (002) is resolved this session. Ticket 003
  is NOT resolved even though closing 002 unblocks it. The graduated fog
  patch appears as a new ticket AND is removed from Not-yet-specified. The
  session ends with the marker removed and the next frontier named.
answer_script:
  - asks_about: channel choice / in-app vs email vs both
    reply: in-app first — email becomes a daily digest later, never per-event email
  - asks_about: why not per-event email / rationale
    reply: our users already complain about email volume from the old system; that complaint is the whole reason this epic exists
shadow: false
---
Work the map below. Ticket to work: 002.

## MOCK MAP

The following is the entire `espalier/maps/2026-08-05-notifications/`.

### map.md

```markdown
---
map: 2026-08-05-notifications
status: IN_PROGRESS
started: 2026-08-05T09:00:00Z
---

# Map: In-app notification system

## Destination

A locked spec for the notification system v1 — channels, triggering events,
and preference model decided; ready to slice.

## Notes

Domain: B2B project-management SaaS. Consult espalier-grill for grilling tickets.

## Decisions so far

- [001 — Which events trigger notifications](tickets/001-triggering-events.md) — task assigned, comment on your task, due-date within 24h; nothing else in v1

## Not yet specified

- digest cadence + unsubscribe granularity — can't be phrased until the channel question settles

## Out of scope

- mobile push (no mobile app exists)

## Session log

| Date | Ticket | Action |
|------|--------|--------|
| 2026-08-05 | 001 | resolved |

## Spawned Changes

| Change | Status |
|--------|--------|
```

### tickets/001-triggering-events.md

```markdown
---
ticket: 001
title: Which events trigger notifications
type: grilling
status: closed
blocked_by: []
claimed_by: dev@example.com
claimed_at: 2026-08-05T09:05:00Z
---

## Question

Which product events generate a notification in v1?

## Resolution

Task assigned to you, comment on your task, due-date within 24h. Everything
else (mentions, status changes) explicitly out of v1.
```

### tickets/002-channel.md

```markdown
---
ticket: 002
title: Which delivery channel ships first
type: grilling
status: open
blocked_by: [001]
claimed_by:
claimed_at:
---

## Question

In-app only, email only, or both — and if both, which is the source of truth?
```

### tickets/003-preference-model.md

```markdown
---
ticket: 003
title: Preference model shape
type: grilling
status: open
blocked_by: [002]
claimed_by:
claimed_at:
---

## Question

Per-event-type toggles vs a single on/off — and where do preferences live?
```
