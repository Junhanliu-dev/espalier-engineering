---
fixture_id: light-02-api-rate-limit
mode: spec
expected_tier: light
expected_signals: 3
# KNOWN-ISSUES #4: "add rate limiting" announces all three gaps — the limit value, the
# scope (per-IP / per-key / global), and the over-limit response are the reflexive
# questions any engineer asks for this feature, so each is a non_obvious-1 (rubric
# "announced-gap test"). Coverage test, not insight — gated on coverage + depth only.
coverage_only: true
planted_ambiguities:
  - the rate limit value
  - the scope of the limit (per IP, per API key, global)
  - the response when the limit is exceeded
answer_script:
  - asks_about: limit value
    reply: 100 requests per minute
  - asks_about: scope
    reply: per API key
  - asks_about: exceeded behaviour
    reply: respond 429 with a Retry-After header
shadow: false
---
feat: add rate limiting to the public API
