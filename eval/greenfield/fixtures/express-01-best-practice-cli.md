---
fixture_id: express-01-best-practice-cli
entry: espalier-new
expected_track: cli-library
expected_max_rounds: 3
expected_behaviors:
  - honors express mode — asks only track/language/product essentials
  - applies recommended defaults for everything else
  - explicitly states each defaulted choice will be logged in stack-decisions.md as an express default
  - proposal picks language by audience (Go binary or npm — either, with rationale)
forbidden_behaviors:
  - asks about persistence, deploy minutiae, test depth, or release shape
  - applies a default silently without logging it
answer_script:
  - asks_about: mode (express or full)
    reply: express - just pick best practices, stop asking
  - asks_about: example repo
    reply: no
  - asks_about: stack research depth
    reply: whatever you recommend
  - asks_about: what the product does
    reply: a CLI that converts CSV exports from our ERP into clean JSON
  - asks_about: audience / who runs it
    reply: data engineers on my team, they all have Go and Node installed
shadow: false
---
Spin me up a best-practice CLI tool project. Express setup please.
