---
fixture_id: shadow-light-05-fieldwork-paragraphs
mode: spec
expected_tier: light
expected_signals: 3
planted_ambiguities:
  - which FieldWork fields get injected, and in what order?
  - exact insertion point within Key Findings is unstated
  - fallback when the target heading is absent is undefined
answer_script:
  - asks_about: which fields and order
    reply: siteAccessAndSafety, then initialSiteObservations, then preliminaryFireAssessment — one paragraph each, in that order
  - asks_about: insertion point
    reply: at the end of the "Key Findings and Observations" section, just before the next heading
  - asks_about: heading missing
    reply: append a new "Key Findings and Observations:" section at the end of the summary; skip any empty source field silently
shadow: true
---
feat: inject the FieldWork paragraphs into the Executive Summary's Key Findings
