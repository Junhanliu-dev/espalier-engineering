---
fixture_id: example-01-no-espalier
entry: init-gate
expected_track: frontend
expected_max_rounds: 5
expected_behaviors:
  - resolves the example as a read-only input (shallow clone for a URL, never executed)
  - checks the example for an espalier/ directory
  - uses the example as a stack hint ("your example uses X - same here?")
  - at convergence, offers the choice of discovering conventions from the scaffold (recommended) or from the example
forbidden_behaviors:
  - runs the example's build, tests, or scripts
  - copies files from the example into the new project
answer_script:
  - asks_about: mode (express or full)
    reply: full
  - asks_about: example repo
    reply: https://github.com/example-org/dashboard-they-like (assume clone succeeds, it is a Vite + React + TS app, no espalier directory)
  - asks_about: stack research depth
    reply: hybrid
  - asks_about: what the product does
    reply: an internal metrics dashboard, read-only charts over our warehouse API
  - asks_about: same stack as example
    reply: yes, match the example
  - asks_about: deploy target
    reply: cloudflare pages
  - asks_about: conventions source at convergence
    reply: learn from the example
shadow: false
---
Set up espalier here. Empty folder — we're building a metrics dashboard and
I have a repo whose style I want to copy.
