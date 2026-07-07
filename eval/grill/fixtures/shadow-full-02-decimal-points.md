---
fixture_id: shadow-full-02-decimal-points
mode: diagnosis
expected_tier: full
expected_signals: 5
planted_ambiguities:
  - '"decimal points" on which fields / which screen?'
  - no symptom — what actually goes wrong today?
  - is it a display/rounding bug or an input-entry bug? (unconfirmed cause)
  - no reproduction steps
  - unstated scope and edge behaviour (when should formatting apply?)
answer_script:
  - asks_about: which fields
    reply: the money inputs — gross amount, super, and GST — on the working-project row
  - asks_about: what actually breaks
    reply: typing "100." or a trailing zero gets clobbered back to "100" mid-edit; you can't enter a decimal
  - asks_about: display bug or input bug
    reply: input-entry bug — the field is bound straight to the numeric value, so reparsing overwrites what you're typing
  - asks_about: when to normalise to 2 decimals
    reply: on blur only, never while typing
  - asks_about: scope
    reply: just the working-project row component; don't touch the store or the currency-parse helper
shadow: true
---
fix: add decimal points
