## Security Audit: PATCH /api/orders/:orderId/status — order status transition (round 1)
| # | Priority | File | Field / Endpoint | Trusted-from-client defect | Fix |
|---|----------|------|------------------|----------------------------|-----|
| 1 | P0 | src/order.status.controller.js:10 | orderId / PATCH /api/orders/:orderId/status | `findById(req.params.orderId)` loads and mutates ANY order by client id with no owner/actor check — user A drives user B's order (owner × state cross-axis IDOR) | scope the load to the session actor: `findOne({ id: req.params.orderId, ownerId: session.userId })`; 404 on miss (no existence oracle) before transition |
| 2 | P0 | src/order.status.controller.js:12 | status / PATCH /api/orders/:orderId/status | state machine checks transition legality (`isLegalTransition`) but NOT that this actor may perform it; no session/identity is read anywhere in the handler | after owner assertion, gate the transition on actor role/ownership; a legal transition on another actor's order must still be refused |

**Verdict:** FAIL

### Summary
- Sensitive surface touched: yes (request handler + persistent write to order state)
- Sensitive fields in scope: 2 (orderId [owner], status [state])
- Trust-boundary defects (P0): 2 (same root cause — no session actor is ever consulted)
- Controls confirmed: state-machine legality only (isLegalTransition) — necessary but insufficient; NO ownership check, NO actor authorization, NO caller identity derived from session

Handler reads `req.params.orderId` and `req.body.status` and writes order state with zero authorization against the calling actor. The legality gate blocks illegal *values* but not illegal *access* — any authenticated (or unauthenticated, depending on upstream middleware) client can transition any order it can name. Canonical owner × state cross-axis IDOR.

### Security-Sensitive Fields
- field: orderId
  endpoint: PATCH /api/orders/:orderId/status
  axis: owner
  required_control: session actor must own (or hold a role permitting) the order; load scoped by owner so "not yours" and "not found" both 404
  abuse_test: "user A PATCHes user B's orderId with a legal status (e.g. shipped) → 403/404, and db order(B).status unchanged"
- field: status
  endpoint: PATCH /api/orders/:orderId/status
  axis: state
  required_control: transition validated by server-side state machine AND authorized against the actor; client cannot drive a transition on an order it does not own
  abuse_test: "user A PATCHes B's orderId { status: 'shipped' } (a LEGAL transition) → rejected 403/404, persisted order(B).status unchanged; also PATCH own order with illegal status ('paid'/'delivered' from pending) → 422, status unchanged"

VERDICT: FAIL p0=2 p1=0 round=1
