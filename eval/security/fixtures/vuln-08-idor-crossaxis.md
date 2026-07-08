---
fixture_id: vuln-08-idor-crossaxis
kind: vuln
file: src/order.status.controller.js
expected_verdict: FAIL
expected_surface: sensitive
planted_vulns:
  - field: orderId
    axis: owner
    hint: PATCH /orders/:orderId/status validates the transition against a server-side state machine but never checks that the session actor OWNS the order — a legal transition (pending->shipped) applied to another user's order is still a cross-actor IDOR/BOLA
false_positive_watch:
  - "the transition legality check (isLegalTransition) is correct — do NOT flag the state machine itself; the missing control is the OWNER check, not the transition validation"
shadow: false
---
const db = require('./db');

const LEGAL = { pending: ['shipped', 'cancelled'], shipped: ['delivered'] };
function isLegalTransition(from, to) {
  return (LEGAL[from] || []).includes(to);
}

// PATCH /api/orders/:orderId/status  { status }
async function setStatus(req, res) {
  const order = await db.orders.findById(req.params.orderId);
  if (!order) return res.status(404).json({ error: 'not found' });
  if (!isLegalTransition(order.status, req.body.status)) {
    return res.status(422).json({ error: 'illegal transition' });
  }
  await db.orders.update(order.id, { status: req.body.status });
  return res.json({ id: order.id, status: req.body.status });
}

module.exports = { setStatus };
