---
fixture_id: repo-01-mixed
kind: vuln
mode: repo-audit
expected_verdict: FINDINGS
expected_surface: sensitive
planted_vulns:
  - field: invoiceId
    axis: owner
    hint: GET /invoices/:invoiceId loads the invoice by client-supplied id with no ownership/role check (IDOR / BOLA)
  - field: isAdmin/role (req.body spread)
    axis: permission
    hint: PATCH /me spreads the raw request body into user.update — privilege fields ride in (mass assignment)
false_positive_watch:
  - "src/payment.controller.js is fully controlled (order owner-scoped by session, price recomputed from catalog) — do NOT flag"
  - "src/format.util.js has no request/persistence surface — belongs under No Sensitive Fields, never a finding"
shadow: false
---
=== FILE: src/invoice.controller.js ===
const db = require('./db');

// GET /api/invoices/:invoiceId
async function getInvoice(req, res) {
  const inv = await db.invoices.findById(req.params.invoiceId);
  if (!inv) return res.status(404).json({ error: 'not found' });
  return res.json(inv);
}

module.exports = { getInvoice };
=== FILE: src/profile.controller.js ===
const db = require('./db');

// PATCH /api/me — update the caller's profile
async function updateMe(req, res) {
  const user = await db.users.findById(req.session.userId);
  if (!user) return res.status(404).json({ error: 'not found' });
  await user.update({ ...req.body });
  return res.json(user);
}

module.exports = { updateMe };
=== FILE: src/payment.controller.js ===
const db = require('./db');
const catalog = require('./catalog');
const payments = require('./payments');

// POST /api/pay — owner-scoped order, server-side price
async function pay(req, res) {
  const order = await db.orders.findWhere({ id: req.body.orderId, userId: req.session.userId });
  if (!order) return res.status(404).json({ error: 'not found' });
  const unit = catalog.priceOf(order.sku);
  if (unit == null) return res.status(422).json({ error: 'unknown sku' });
  const charge = unit * order.qty;
  await payments.charge(req.session.userId, charge);
  return res.json({ charged: charge });
}

module.exports = { pay };
=== FILE: src/format.util.js ===
// Pure formatting helpers — no request handling, no persistence.
function formatDate(d) {
  return new Date(d).toISOString().slice(0, 10);
}

function centsToDollars(c) {
  return (c / 100).toFixed(2);
}

module.exports = { formatDate, centsToDollars };
