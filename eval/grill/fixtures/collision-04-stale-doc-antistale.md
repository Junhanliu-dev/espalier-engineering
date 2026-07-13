---
fixture_id: collision-04-stale-doc-antistale
mode: spec
expected_tier: skip
# The anti-stale guard (rubric dimension 6). The requirement is crisp (skip on text). A
# rules doc APPEARS to collide ("no unauthenticated routes" vs a public /healthz), but the
# architecture doc shows public infra routes are intentional and the rule line is out of
# date. Correct behaviour: verify, find the doc stale, FLAG it (mark_stale), raise NO
# collision, and stay `skip`. Zero collisions are planted. A wrongly-raised collision floors
# the tier off `skip`, which fails depth-calibration — the existing gate catches the false
# positive with no extra machinery.
expected_signals: 0
planted_ambiguities: []
planted_collisions: []
answer_script:
  - asks_about: no questions expected — the requirement is crisp and the apparent rule collision is a stale doc
    reply: correct, /healthz is a public infra route by design — the security-standards line is out of date; flag it, don't block me
shadow: false
---
feat: add a GET /healthz endpoint that returns 200 OK

## MOCK CONTEXT

The following is the entire `espalier/rules/` and `espalier/wiki/` for this project.

### espalier/rules/security-standards.md

```markdown
# Security Standards

## Authentication
Every HTTP route MUST be registered behind `requireAuth`. There are NO unauthenticated
routes in this service.
```

### espalier/wiki/architecture.md

```markdown
# Architecture

## Routing (current, as of the last release)
The service mounts a **public router** (`src/server/publicRouter.ts`) BEFORE `requireAuth`.
Infra/health routes — `/healthz`, `/readyz`, `/metrics` — live on it and are intentionally
unauthenticated so the load balancer and Prometheus can reach them without a token. This is
the established pattern; a new health route belongs on the public router.

> NOTE: the `security-standards.md` line "There are NO unauthenticated routes" predates the
> public router and is out of date — infra routes have been public since the LB migration.
```
