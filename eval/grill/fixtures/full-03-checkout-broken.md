---
fixture_id: full-03-checkout-broken
mode: diagnosis
expected_tier: full
expected_signals: 6
# KNOWN-ISSUES #4: for a bare "checkout is broken" report every gap (no anchor, no repro,
# undefined symptom, no cause, no expected behaviour, which step) is announced by the
# vagueness itself, so each question is a reflexive non_obvious-1 (rubric "announced-gap
# test"). This is a coverage test — does grill surface all the reflexive diagnosis gaps —
# not an insight test, so it is gated on coverage + depth only (rubric "Coverage-only").
coverage_only: true
planted_ambiguities:
  - no anchor — no file, line, or stack trace
  - no reproduction steps
  - '"broken" — the actual symptom is undefined'
  - no root cause proposed or confirmed
  - the expected behaviour is not stated
  - which step of checkout (cart, payment, confirmation)
answer_script:
  - asks_about: what happens
    reply: the page hangs after clicking Pay
  - asks_about: which step
    reply: the payment step
  - asks_about: reproduction
    reply: any order with more than one item, every time
  - asks_about: error or log
    reply: the console shows a 500 from /api/payment/charge
  - asks_about: expected behaviour
    reply: the order completes and shows a confirmation page
shadow: false
---
fix: checkout is broken
