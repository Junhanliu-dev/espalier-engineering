---
fixture_id: full-01-dashboard-faster
mode: spec
expected_tier: full
expected_signals: 6
# Every planted gap is announced by a vague term in the requirement ("faster", "better",
# "errors"), so each question is a reflexive non_obvious-1 (see rubric.md "announced-gap
# test"). This is a coverage test — does grill surface all the obvious gaps — not an
# insight test, so it is gated on coverage + depth only (rubric.md "Coverage-only fixtures").
coverage_only: true
planted_ambiguities:
  - '"faster" has no target metric or baseline'
  - which dashboard (multiple exist)
  - which "errors" are in scope
  - what improved "better" error handling means concretely
  - no actor — whose experience is being improved
  - no failure behaviour defined
answer_script:
  - asks_about: which dashboard
    reply: the main analytics dashboard
  - asks_about: faster target
    reply: initial load under 2 seconds, currently about 6
  - asks_about: which errors
    reply: failed data-fetch calls to the metrics API
  - asks_about: better error handling
    reply: show a retry button instead of a blank panel
  - asks_about: whose experience / actor
    reply: end users viewing the dashboard (SBM staff), on initial page load
  - asks_about: scope boundary
    reply: load time and fetch errors only — no redesign
shadow: false
---
make the dashboard faster and handle errors better
