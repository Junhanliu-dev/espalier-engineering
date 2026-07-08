---
fixture_id: vuln-09-refund-unbounded
kind: vuln
file: src/refund.controller.js
expected_verdict: FAIL
expected_surface: sensitive
planted_vulns:
  - field: amountCents
    axis: money
    hint: POST /refund refunds the client-supplied amountCents with no bound against the original charge — a caller can refund more than was paid (or a negative amount), moving money by tampering the request value
false_positive_watch:
  - "orderId IS owner-scoped here (findWhere id+userId) — do NOT flag IDOR; the money defect is the unbounded amount, not object access"
shadow: false
---
const db = require('./db');
const payments = require('./payments');

// POST /api/refund  { orderId, amountCents }
async function refund(req, res) {
  const order = await db.orders.findWhere({ id: req.body.orderId, userId: req.session.userId });
  if (!order) return res.status(404).json({ error: 'not found' });
  // refund whatever the client asked for
  await payments.refund(order.chargeId, req.body.amountCents);
  await db.refunds.create({ orderId: order.id, amountCents: req.body.amountCents });
  return res.json({ refunded: req.body.amountCents });
}

module.exports = { refund };
