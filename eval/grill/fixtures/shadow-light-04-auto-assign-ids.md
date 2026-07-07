---
fixture_id: shadow-light-04-auto-assign-ids
mode: spec
expected_tier: light
expected_signals: 4
planted_ambiguities:
  - ID format unspecified — prefix and zero-padding width?
  - does this change the existing contractor ID format, or only add building-company IDs?
  - retroactive scope — existing records renumbered, or new-only?
  - what if a caller already supplies an ID?
answer_script:
  - asks_about: ID format
    reply: CON-000001 for contractors and BLD-000001 for building companies — a letter prefix, a dash, then 6-digit zero padding
  - asks_about: existing contractor format
    reply: yes, the contractor format changes from the old SC0001 to CON-000001 — it's not purely additive
  - asks_about: retroactive scope
    reply: new records only; do not renumber or backfill any existing IDs or the sequence counters
  - asks_about: caller-supplied ID
    reply: honour it — skip generation entirely when a companyId is already provided on create
shadow: true
---
feat: auto-assign building company IDs and prefix the contractor/company IDs
