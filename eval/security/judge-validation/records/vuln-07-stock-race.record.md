## Security Audit: POST /api/reserve (inventory reserve) (round 1)
| # | Priority | File | Field / Endpoint | Trusted-from-client defect | Fix |
|---|----------|------|------------------|----------------------------|-----|
| 1 | P0 | src/inventory.controller.js:8 | qty / POST /api/reserve | client `qty` applied to inventory with no range check — negative `qty` INFLATES stock (`stock - (-100) = stock+100`) and over-limit `qty` drives stock negative (oversell). Moves inventory value directly. | reject non-integer / `qty < 1` / `qty > item.stock`; recompute `remaining` server-side only from validated qty |
| 2 | P1 | src/inventory.controller.js:8 | qty / POST /api/reserve | read-then-write decrement is non-atomic: `findBySku` → subtract → `setStock`. Concurrent requests race; both read same `stock`, both write, decrement lost → stock goes negative / double-reserve. | atomic conditional decrement at the store (`UPDATE ... SET stock = stock - :qty WHERE id = :id AND stock >= :qty`) and treat 0-rows-affected as insufficient-stock |

**Verdict:** FAIL

### Summary
- Sensitive surface touched: yes — request handler with persistent inventory write.
- Sensitive fields in scope: 1 — `qty` (money/stock axis). `sku` is a public catalog lookup key (non-owner); `userId` correctly re-derived from `req.session.userId` (identity control OK).
- Trust-boundary defects (P0): 1 (unvalidated `qty` moves inventory); plus 1 P1 (non-atomic race).
- Controls confirmed: identity re-derived from session (`req.session.userId`, line 10). Missing: stock range-check, atomic apply.

### Security-Sensitive Fields
- field: qty
  endpoint: POST /api/reserve
  axis: money
  required_control: validate qty is a positive integer within available stock; apply the decrement atomically (conditional update), never read-then-write
  abuse_test: "POST /api/reserve { sku:'X', qty:-100 } → rejected (422); persisted item.stock unchanged (NOT inflated). And POST qty greater than stock → rejected; stock never goes negative. Concurrency: N parallel reserves of qty=1 against stock=1 → exactly one succeeds, stock ends at 0, never negative."

VERDICT: FAIL p0=1 p1=1 round=1
