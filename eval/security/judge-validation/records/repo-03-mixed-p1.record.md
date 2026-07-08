## Repo-Audit Findings: repo-03-mixed-p1 (comment, wallet, notify, slug)

| # | Priority | File | Field / Endpoint | Trusted-from-client defect | Fix |
|---|----------|------|------------------|----------------------------|-----|
| 1 | P0 | src/comment.controller.js:5 | commentId / DELETE /api/comments/:commentId | loads + deletes comment by client id, no owner check — any actor deletes any comment (IDOR) | scope load by owner: `findWhere({id: req.params.commentId, ownerId: req.session.userId})`, 404 if none, then delete |
| 2 | P0 | src/wallet.controller.js:6 | amountCents / POST /api/wallet/spend | client amount subtracted with no range check + non-atomic read-then-write; negative amount credits balance, no overdraw guard | reject `amountCents <= 0`; assert `remaining >= 0`; apply as atomic conditional decrement in DB |

**Batch verdict:** FINDINGS (2)

### Security-Sensitive Fields
- field: commentId
  endpoint: DELETE /api/comments/:commentId
  axis: owner
  required_control: session actor must own the comment (comment.ownerId == session.userId); "not yours" and "not found" both 404
  abuse_test: "user A deletes user B's commentId → 404, db comment(B) still exists"
- field: amountCents
  endpoint: POST /api/wallet/spend
  axis: money
  required_control: reject non-positive amount, forbid overdraw (remaining >= 0), decrement atomically against source-of-truth balance
  abuse_test: "POST amountCents=-500 → rejected (422), db wallet.balanceCents unchanged (not credited); POST amount > balance → 422, balance unchanged"

### Controls Confirmed
- POST /api/wallet/spend — actor identity re-derived from session, not request (`req.session.userId`, wallet.controller.js:5)
- notify consumer onNotify — object ownership enforced: target loaded via owner-scoped query `findWhere({id: targetId, ownerId: userId})`, dropped if not owned; message coerced+truncated `String(...).slice(0,500)` (notify.consumer.js:5-7). userId is recipient bound to the same ownership check, not used as an external authorization key.

### No Sensitive Fields
- src/slug.util.js — pure string helper (`slugify`); no request handling, no authorization decision, no persistence. Input coerced with `String(s)`.
