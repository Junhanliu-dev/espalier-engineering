---
fixture_id: chart-04-do-everything
mode: chart
max_open_tickets: 9
# Cap fixture: the idea affords far more than 9 sharp tickets (the body lists
# 13 candidate decision areas). The correct run STOPS at the cap and forces
# narrow-the-destination / split-the-map / raise-the-cap — it does not
# silently chart 13 tickets, and it does not pick one silently either.
planted_decisions: []
expected_behavior: >
  Creation stops at the max-open-tickets cap (9 open tickets): the run
  surfaces the cap explicitly and asks the user to narrow the destination,
  split into two maps, or raise the cap — via a question, not a silent
  choice. Any run that ends the session with more than 9 open tickets, or
  that drops candidates without saying so, fails.
answer_script:
  - asks_about: destination
    reply: honestly, all of it is v1 to me — you tell me if that is too much
  - asks_about: narrow vs split vs raise the cap
    reply: fine — split it; marketplace-and-payments first, everything else second
shadow: false
---
Idea: build our whole platform v1 — marketplace listings, payments and
payouts, seller onboarding with KYC, buyer reviews, a messaging inbox,
search with filters, an admin moderation console, email notifications, a
public API, usage analytics, an affiliate program, GDPR export, and native
mobile apps. Chart the map.
