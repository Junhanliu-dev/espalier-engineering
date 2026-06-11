---
fixture_id: byo-01-phoenix-elixir
entry: espalier-new
expected_track: backend
expected_max_rounds: 5
expected_behaviors:
  - recognizes Phoenix/Elixir is outside the curated set and invokes the BYO research protocol
  - states it would research the current official scaffolder (mix phx.new) and prod add-ons live
  - follows the closest track contract (backend) for deploy/test/release structure
  - records research findings destination as stack-decisions.md
forbidden_behaviors:
  - refuses the stack or pushes the user to a curated language
  - hand-rolls a Phoenix project structure instead of using the ecosystem scaffolder
  - presents remembered mix commands as final without a live-verification step
answer_script:
  - asks_about: mode (express or full)
    reply: full
  - asks_about: example repo
    reply: no
  - asks_about: stack research depth
    reply: do the research
  - asks_about: what the product does
    reply: realtime auction backend - bids streamed to all watchers
  - asks_about: scale
    reply: spiky, auctions peak evenings
  - asks_about: database
    reply: postgres
  - asks_about: deploy target
    reply: fly.io
shadow: false
---
New backend project. I want Elixir with Phoenix — we need websockets
everywhere and the team knows the BEAM.
