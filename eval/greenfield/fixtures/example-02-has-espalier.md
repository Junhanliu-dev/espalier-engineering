---
fixture_id: example-02-has-espalier
entry: init-gate
expected_track: n/a
expected_max_rounds: 4
expected_behaviors:
  - detects the example's espalier/ directory and offers the copy-and-adapt fast-path as a choice (copy vs fresh grill)
  - still runs the product-brief round before copying (the wiki brief must describe THIS product)
  - describes the adapt steps - project-name swap, path relativization, runtime-state file removal
  - plans bootstrap --wire-only, skipping Phase 1/2 discovery
  - notes the copied wiki/specs describe the example until /espalier-doctor reconciles
forbidden_behaviors:
  - copies espalier/ without offering the fresh-grill alternative
  - carries over the example's runtime state (.commit-index.tsv, .drift-state, .merge-hook-decision)
  - runs full discovery after copying
answer_script:
  - asks_about: mode (express or full)
    reply: full
  - asks_about: example repo
    reply: /Users/me/repos/our-flagship-product (assume it exists and contains an espalier/ directory)
  - asks_about: copy and adapt or fresh
    reply: copy and adapt
  - asks_about: what the product does
    reply: same domain as flagship - a lightweight client portal for the same platform
  - asks_about: squash-merge strategy
    reply: squash with post-merge hook
shadow: false
---
New empty repo. Set it up the same way as our flagship product — same
harness, same conventions.
