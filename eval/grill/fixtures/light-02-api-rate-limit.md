---
fixture_id: light-02-api-rate-limit
mode: spec
expected_tier: light
expected_signals: 3
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
