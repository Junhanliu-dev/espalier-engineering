---
fixture_id: chart-03-crisp-endpoint
mode: chart
max_open_tickets: 9
# No-fog exit: the effort fits one session. The correct run charts NOTHING —
# it says so and routes to /espalier. Charting a map here is the failure.
planted_decisions: []
expected_behavior: >
  Declines to create a map: states the effort fits one session (breadth-first
  pass surfaces no fog), writes no map.md and no tickets, and routes the user
  to /espalier with the requirement. Session marker removed / no lasting state.
answer_script:
  - asks_about: destination / scope confirmation
    reply: exactly what it says — one endpoint, admin-only, JSON list of the 20 most recent signups with email + created_at; nothing else planned around it
shadow: false
---
Idea: add a GET /admin/recent-signups endpoint returning the 20 most recent
signups (email + created_at), admin-authenticated like every other /admin
route. Chart a map for it?
