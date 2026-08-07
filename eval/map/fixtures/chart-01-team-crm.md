---
fixture_id: chart-01-team-crm
mode: chart
max_open_tickets: 9
planted_decisions:
  - id: tenancy-model
    text: single-tenant-per-deploy vs shared-schema multi-tenant — forks the whole data layer
    expected_placement: ticket
    expected_type: grilling
  - id: auth-provider
    text: which auth approach (roll-own sessions vs Auth0/Clerk-class provider) — needs capability/pricing facts from outside the repo
    expected_placement: ticket
    expected_type: research
  - id: email-sending-account
    text: a transactional-email account must exist before deliverability options can even be judged
    expected_placement: ticket
    expected_type: task
  - id: pipeline-stages-shape
    text: what the sales-pipeline stages ARE (fixed set vs user-defined) — decides the core model
    expected_placement: ticket
    expected_type: grilling
  - id: reporting-scope
    text: "reporting" is wanted but nobody can yet say which reports, for whom, over what period — not phrasable sharply until the pipeline model lands
    expected_placement: fog
answer_script:
  - asks_about: destination / what DONE looks like for this map
    reply: a locked spec for CRM v1 — contacts, one sales pipeline, and email logging — ready to slice into implementation changes; dashboards and mobile are explicitly later
  - asks_about: tenancy
    reply: shared-schema multi-tenant; we sell to small teams and can't run a deploy per customer
  - asks_about: pipeline stages fixed or user-defined
    reply: user-defined per team, with a sensible default set
  - asks_about: who the users are / team size
    reply: sales teams of 3-15 people; admin + member roles are enough for v1
shadow: false
---
Idea: we want to build a lightweight CRM for small sales teams — contacts,
a pipeline view, email logging, some reporting eventually. Too big to just
start coding; chart it.
