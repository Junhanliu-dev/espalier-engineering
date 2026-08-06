---
fixture_id: chart-02-monolith-events
mode: chart
max_open_tickets: 9
# Brownfield epic: much of the fog is "what is already true here". Internal
# truths resolve by talking + reading code (grilling); only the broker
# comparison genuinely needs facts from outside the repo (research).
planted_decisions:
  - id: broker-choice
    text: which event backbone (Kafka vs NATS vs Postgres-based queue) — needs external capability/ops facts
    expected_placement: ticket
    expected_type: research
  - id: event-contract-shape
    text: event schema + versioning contract (payload shape, evolution rules) — every consumer depends on it
    expected_placement: ticket
    expected_type: grilling
  - id: current-side-effect-inventory
    text: which order-flow side effects exist TODAY inside the monolith (emails, stock sync, invoicing) and which are safe to move — must be established with the team before anything is carved out
    expected_placement: ticket
    expected_type: grilling
  - id: dual-write-window
    text: cutover strategy — dual-write window vs hard cutover, and what happens to in-flight orders during it
    expected_placement: ticket
    expected_type: grilling
  - id: staging-broker-access
    text: a broker instance must be provisioned before latency/ordering behavior can be judged against real payloads
    expected_placement: ticket
    expected_type: task
  - id: consumer-team-migration
    text: how the two downstream consumer teams migrate — not phrasable until the event contract exists; their constraints are unknown
    expected_placement: fog
answer_script:
  - asks_about: destination
    reply: a locked migration plan for extracting order-placed side effects onto an event bus — contract decided, cutover decided, consumers mapped; actually moving code is the build after this map
  - asks_about: which side effects / current behavior
    reply: today order-placed synchronously sends a confirmation email, decrements stock, and creates an invoice draft — all in one transaction; there may be more, that inventory is exactly what I want established
  - asks_about: cutover appetite / risk tolerance
    reply: zero tolerance for losing an order; a temporary dual-write window is acceptable if it is observable
  - asks_about: event contract preferences
    reply: no strong opinion — that is a decision I want the map to force properly
shadow: false
---
Idea: our checkout monolith does everything synchronously when an order is
placed. We want to move the side effects onto an event bus so other teams
can subscribe. Multi-week effort, lots unknown — chart it.
