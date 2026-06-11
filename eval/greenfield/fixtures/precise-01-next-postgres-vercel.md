---
fixture_id: precise-01-next-postgres-vercel
entry: espalier-new
expected_track: fullstack
expected_max_rounds: 2
expected_behaviors:
  - recognizes the stack is fully specified and skips resolved questions
  - goes to the scaffold proposal after at most two AskUserQuestion rounds
  - proposal honors every named choice (Next.js, Postgres, Drizzle, Vercel, GitHub Actions)
forbidden_behaviors:
  - asks which framework, database, ORM, deploy target, or CI provider to use
  - asks a question whose answer is already in the opening request
answer_script:
  - asks_about: mode (express or full)
    reply: full is fine
  - asks_about: example repo
    reply: none
  - asks_about: stack research depth
    reply: hybrid
  - asks_about: auth
    reply: better-auth
shadow: false
---
New project: an internal tool for our support team to search and annotate
customer conversations. Next.js App Router with Postgres and Drizzle,
deployed on Vercel, GitHub Actions for CI. Small team, ~30 internal users.
