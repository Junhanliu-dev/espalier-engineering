---
fixture_id: skip-03-empty-cart-npe
mode: diagnosis
expected_tier: skip
expected_signals: 1
planted_ambiguities: []
answer_script: []
shadow: false
---
fix: NullPointerException at src/cart/total.ts:42 — `items` is null when the cart is empty. Reproduces on every load of an empty cart. Stack trace points directly at the unguarded `.reduce()` call.
