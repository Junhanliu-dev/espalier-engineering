---
fixture_id: shadow-light-02-invoice-failures
mode: diagnosis
expected_tier: light
expected_signals: 3
planted_ambiguities:
  - root cause of the false success is unstated — why does a failure show success?
  - batch behaviour undefined — one card fails vs the whole batch?
  - partial-failure behaviour and which error message to show are unspecified
answer_script:
  - asks_about: why it falsely succeeds
    reply: the success toast lives in a `finally` block, so it fires even when the invoice mutation throws
  - asks_about: batch semantics
    reply: a shared builder-contact error fails every card in that batch together; per-card errors come back as individual results
  - asks_about: partial failures
    reply: show "N of M invoice(s) failed" and still commit the cards that did succeed; on a total failure show the first failure's message
shadow: true
---
fix: invoice creation shows a success toast even when it failed
