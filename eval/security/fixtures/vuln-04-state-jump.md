---
fixture_id: vuln-04-state-jump
kind: vuln
file: src/order.status.controller.js
expected_verdict: FAIL
expected_surface: sensitive
planted_vulns:
  - field: status
    axis: state
    hint: order.status is set directly from req.body with no server-side state machine or transition-actor check — a client can force 'paid' / 'shipped'
false_positive_watch:
  - "the order is loaded owner-scoped via findOwned(id, session.userId) — do NOT flag IDOR"
shadow: false
---
const db = require('./db');

// PATCH /api/orders/:id/status
async function setStatus(req, res) {
  const order = await db.orders.findOwned(req.params.id, req.session.userId);
  if (!order) return res.status(404).json({ error: 'not found' });
  order.status = req.body.status;   // WRONG: any lifecycle value, no state machine
  await db.orders.save(order);
  return res.json(order);
}

module.exports = { setStatus };
