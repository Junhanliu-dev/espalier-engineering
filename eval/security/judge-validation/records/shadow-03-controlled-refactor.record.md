## Security Audit: PATCH /api/subscriptions/:subId — changePlan (round 1)
| # | Priority | File | Field / Endpoint | Trusted-from-client defect | Fix |
|---|----------|------|------------------|----------------------------|-----|
| — | — | src/subscription.controller.js | subId, planId / PATCH /api/subscriptions/:subId | none — all controls present | n/a |

**Verdict:** PASS

### Summary
- Sensitive surface touched: yes (request handler + persistent write)
- Sensitive fields in scope: 2 (subId [owner], planId [permission/money])
- Trust-boundary defects (P0): 0
- Controls confirmed:
  - ownership — `requireOwner(subId, session.userId)` asserts `sub.userId === session.userId`, throws 404; same 404 for not-found and not-owner, no existence oracle (subscription.controller.js:5-11,16)
  - recompute (money) — `priceCents` derived server-side from `PLANS[planId]`; client price never read/persisted (subscription.controller.js:3,17,19)
  - allow-list / state — `planId` validated against `PLANS` keys, unknown plan rejected 422 (subscription.controller.js:17-18)
  - identity — actor from `req.session.userId`, never from body/path (subscription.controller.js:16)
  - no mass assignment — `update` binds explicit `{ planId, priceCents }`, no `...req.body` (subscription.controller.js:19)

## Security-Sensitive Fields
- field: subId
  endpoint: PATCH /api/subscriptions/:subId
  axis: owner
  required_control: session actor must own the subscription (sub.userId == session.userId); "not yours" and "not found" both 404
  abuse_test: "user A PATCHes user B's subId with a valid planId → 404, and db subscription(B) planId/priceCents unchanged"
- field: planId
  endpoint: PATCH /api/subscriptions/:subId
  axis: permission
  required_control: priceCents recomputed server-side from PLANS allow-list; unknown/tampered plan rejected 422; client-sent price ignored
  abuse_test: "PATCH { planId: 'basic', priceCents: 1 } (or planId: 'enterprise') → server persists PLANS['basic']=900 (or 422); persisted priceCents != 1"

VERDICT: PASS p0=0 p1=0 round=1
