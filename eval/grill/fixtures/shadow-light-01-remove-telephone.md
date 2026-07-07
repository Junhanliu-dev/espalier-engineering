---
fixture_id: shadow-light-01-remove-telephone
mode: spec
expected_tier: light
expected_signals: 3
planted_ambiguities:
  - '"telephone" is ambiguous — there are two phone fields (tel vs phone); which one?'
  - scope unstated — frontend only, or backend schema/column too?
  - how far it reaches (which forms / transformers) is unsaid
answer_script:
  - asks_about: which phone field
    reply: the `tel` field specifically — `phone` stays as the sole phone-number field
  - asks_about: backend / schema too
    reply: no, frontend contractor-onboarding flow only; leave the DB column in place
  - asks_about: which touchpoints
    reply: the contact-info form, the review summary row, the zod schema/defaults, and all the onboarding data transformers
shadow: true
---
feat: remove telephone from existence
