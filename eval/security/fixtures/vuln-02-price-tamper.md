---
fixture_id: vuln-02-price-tamper
kind: vuln
file: src/checkout.service.js
expected_verdict: FAIL
expected_surface: sensitive
planted_vulns:
  - field: price
    axis: money
    hint: order total is computed from client-supplied req.body.price instead of the server-side catalog
false_positive_watch:
  - "userId is taken from req.session — do NOT flag it as an identity defect"
  - "status is hard-coded 'pending' — do NOT flag it as a state defect"
shadow: false
---
const db = require('./db');

// POST /api/checkout
async function checkout(req, res) {
  const total = req.body.price * req.body.quantity;
  const order = await db.orders.create({
    userId: req.session.userId,   // correct: from session
    total,                        // WRONG: client-supplied price
    status: 'pending',            // correct: hard-coded
  });
  return res.status(201).json(order);
}

module.exports = { checkout };
