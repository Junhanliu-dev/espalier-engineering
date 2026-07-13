---
fixture_id: shadow-light-04-auto-assign-ids
mode: spec
expected_tier: light
# KNOWN-ISSUES #3: previously planted 4 independent signals at `light` (question cap 3),
# so coverage ceilinged at 3/4 = 0.75 and it failed the 0.8 bar by construction. The two
# format-related gaps (exact format, and replace-vs-additive) are one topic — a single
# question resolves both — so they are merged into one planted signal. Now 3 signals, 3
# questions, satisfiable at light. Bumping to `full` was rejected: 4 signals still map to
# `light` per Step 1, so `full` would fail depth-calibration.
expected_signals: 3
planted_ambiguities:
  - ID format (prefix + zero-padding width) — and does it replace the existing contractor format, or only add building-company IDs?
  - retroactive scope — existing records renumbered, or new-only?
  - what if a caller already supplies an ID?
answer_script:
  - asks_about: ID format and whether it replaces the existing contractor format
    reply: CON-000001 for contractors and BLD-000001 for building companies (letter prefix, dash, 6-digit zero padding); and yes — the contractor format changes from the old SC0001, it's not purely additive
  - asks_about: retroactive scope
    reply: new records only; do not renumber or backfill any existing IDs or the sequence counters
  - asks_about: caller-supplied ID
    reply: honour it — skip generation entirely when a companyId is already provided on create
shadow: true
---
feat: auto-assign building company IDs and prefix the contractor/company IDs
