---
fixture_id: shadow-light-03-sidebar-tooltips
mode: diagnosis
expected_tier: light
expected_signals: 2
planted_ambiguities:
  - root cause unconfirmed — is it a z-index value, or a stacking-context problem?
  - scope unstated — fix the sidebar only, or the shared tooltip everywhere?
answer_script:
  - asks_about: is it a z-index value
    reply: no — it's a stacking-context trap; the tooltip's z-50 is nested inside a z-10 sidebar ancestor, so it can never rise above the header
  - asks_about: fix approach
    reply: wrap the tooltip content in a Portal to document.body so it escapes the sidebar's stacking context; don't change any z-index values
  - asks_about: scope — sidebar only
    reply: fix the shared tooltip primitive, so it applies app-wide; the sidebar was just where the symptom showed
shadow: true
---
fix: sidebar tooltips get hidden behind the header when the nav is collapsed
