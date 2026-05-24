---
fixture_id: light-03-slow-login
mode: diagnosis
expected_tier: light
expected_signals: 3
planted_ambiguities:
  - the exact conditions that trigger the slowness ("sometimes")
  - what "slow" means in measured terms
  - whether a root cause has actually been confirmed
answer_script:
  - asks_about: when it is slow
    reply: only on the first login after a server restart
  - asks_about: how slow
    reply: about 8 seconds vs the usual 400ms
  - asks_about: confirmed cause
    reply: not confirmed — suspected cold connection pool, not verified
shadow: false
---
fix: login is sometimes slow
