---
fixture_id: shadow-full-03-builder-history
mode: diagnosis
expected_tier: full
expected_signals: 5
planted_ambiguities:
  - single bare noun "builderHistory" — no symptom stated at all
  - no actor, no trigger — what operation fails?
  - root cause entirely unstated
  - no reproduction
  - fix approach and scope unstated (schema? app code? data migration?)
answer_script:
  - asks_about: symptom
    reply: creating a BuilderHistory row fails with a unique-constraint violation
  - asks_about: which fields
    reply: companyId and xeroId are both marked @unique on the BuilderHistory model
  - asks_about: why that is wrong
    reply: one builder legitimately has many history snapshots that share the same companyId — uniqueness is too strict here
  - asks_about: preserve lookup performance
    reply: yes — replace each @unique with an @@index on the same field
  - asks_about: scope / data migration
    reply: schema.prisma only; no data backfill and no application-code change
shadow: true
---
fix: builderHistory
