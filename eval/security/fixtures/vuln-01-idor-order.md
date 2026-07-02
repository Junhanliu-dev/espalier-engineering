---
fixture_id: vuln-01-idor-order
kind: vuln
file: src/order.controller.js
expected_verdict: FAIL
expected_surface: sensitive
planted_vulns:
  - field: orderId
    axis: owner
    hint: GET /orders/:orderId loads the order by client-supplied id with no ownership/role check (IDOR / BOLA)
false_positive_watch: []
shadow: false
---
const db = require('./db');

// GET /api/orders/:orderId
async function getOrder(req, res) {
  const order = await db.orders.findById(req.params.orderId);
  if (!order) return res.status(404).json({ error: 'not found' });
  return res.json(order);
}

module.exports = { getOrder };
