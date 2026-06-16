---
fixture_id: full-03-checkout-broken
mode: diagnosis
expected_tier: full
expected_signals: 6
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
