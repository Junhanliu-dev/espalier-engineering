---
fixture_id: shadow-full-01-order-issue
mode: diagnosis
expected_tier: full
expected_signals: 5
planted_ambiguities:
  - '"order" is undefined — sort order? tab order? array/list order? of what?'
  - no symptom, no actor, no location — where does the wrong order show?
  - root cause asserted as an "issue" with zero evidence
  - no reproduction steps
  - scope unstated — frontend UI, backend, PDF?
answer_script:
  - asks_about: order of what
    reply: the Fire Cause section's field list — Area of Origin, Point of Origin, First Fuel, Ignition Source
  - asks_about: what specifically is wrong
    reply: Point of Origin renders before First Fuel; it should come after First Fuel
  - asks_about: where it manifests
    reply: two places disagree — the admin Settings dropdown config and the Analysis build-order UI are out of sync
  - asks_about: root cause
    reply: the two UI config arrays list the fields in different orders; neither is a backend/data problem
  - asks_about: scope boundary
    reply: frontend list-config only — no backend, schema, or PDF ordering changes
shadow: true
---
fix: order issue
