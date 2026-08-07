---
fixture_id: chart-06-greenfield-recipes
mode: chart
greenfield: true
max_open_tickets: 9
# Greenfield mode: invoked as `/espalier-map greenfield: <idea>` from init
# Pass 1. The destination is the FIXED template ("conventions + architecture
# decided; skeleton scaffolded; ready for decision-sourced init Pass 2") —
# the judge reports behavior_correct on that, though this fixture gates on
# coverage/placement/typing like any planted fixture.
planted_decisions:
  - id: stack-choice
    text: which stack (the team is split Rails vs Django vs Node) — needs external comparison facts
    expected_placement: ticket
    expected_type: research
  - id: layering-shape
    text: architecture/layer convention (where request handling, domain logic, and persistence live)
    expected_placement: ticket
    expected_type: grilling
  - id: error-convention
    text: the error-handling convention (exceptions vs result values, and at which boundary)
    expected_placement: ticket
    expected_type: grilling
  - id: core-domain-model
    text: the core recipe/ingredient/plan model — feeds wiki/data-models at Pass 2
    expected_placement: ticket
    expected_type: grilling
  - id: scaffold-run
    text: running the chosen stack's scaffolder so conventions can bind to real files
    expected_placement: ticket
    expected_type: task
expected_behavior: >
  The destination matches the greenfield template (conventions + architecture
  decided; skeleton scaffolded; ready for decision-sourced init Pass 2), and
  the handoff note says a CLEARED map routes back to /espalier-init Pass 2 —
  not into FILED feature slices.
answer_script:
  - asks_about: destination confirmation
    reply: yes — decisions locked and skeleton scaffolded so init can bind the rules; recipe features themselves come after
  - asks_about: team stack experience
    reply: two of us know Rails well, one is a Django person, none of us wants to fight about it — get us the comparison and we'll decide on facts
  - asks_about: domain model basics
    reply: recipes have ingredients with quantities; a weekly plan picks recipes per day; shopping list derives from the plan
shadow: false
---
Idea (greenfield): a meal-planning web app — recipes, weekly plans, a
derived shopping list. Empty repo, nothing decided, team of three.
