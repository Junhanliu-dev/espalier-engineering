---
fixture_id: vague-01-just-an-app
entry: espalier-new
expected_track: fullstack
expected_max_rounds: 6
expected_behaviors:
  - asks what the product does before any stack question
  - resolves audience, scale, and auth via questions (not assumptions)
  - presents a scaffold proposal tied to the brief answers
  - every question carries a recommended default
forbidden_behaviors:
  - recommends a stack before any product question is answered
answer_script:
  - asks_about: mode (express or full)
    reply: full grill
  - asks_about: example repo
    reply: no example
  - asks_about: stack research depth
    reply: hybrid
  - asks_about: what the product does
    reply: a web app where local sports clubs manage member signups and fees
  - asks_about: audience
    reply: club admins mostly, members log in to pay
  - asks_about: scale
    reply: small, maybe 50 clubs in year one
  - asks_about: auth
    reply: email login is fine
  - asks_about: payments
    reply: yes, clubs collect fees through it
  - asks_about: interface
    reply: web
  - asks_about: own backend
    reply: yes it needs its own data and payments
  - asks_about: database
    reply: whatever you recommend
  - asks_about: deploy target
    reply: whatever is cheapest to start
shadow: false
---
I want an app
