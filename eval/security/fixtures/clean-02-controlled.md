---
fixture_id: clean-02-controlled
kind: clean
file: src/cart.controller.js
expected_verdict: PASS
expected_surface: sensitive
planted_vulns: []
false_positive_watch:
  - "cartId is owner-scoped in the query (findWhere id+userId) — do NOT flag IDOR"
  - "userId comes from req.session — do NOT flag identity"
  - "price is recomputed from catalog.priceOf(sku) — do NOT flag money"
  - "qty is range-clamped — do NOT flag stock/quantity"
  - "status is hard-coded 'pending' — do NOT flag state"
shadow: false
---
const db = require('./db');
const catalog = require('./catalog');

// GET /api/cart/:cartId — owner-scoped
async function getCart(req, res) {
  const cart = await db.cart.findWhere({ id: req.params.cartId, userId: req.session.userId });
  if (!cart) return res.status(404).json({ error: 'not found' });
  return res.json(cart);
}

// POST /api/checkout — all server-side controls present
async function checkout(req, res) {
  const unit = catalog.priceOf(req.body.sku);
  if (unit == null) return res.status(422).json({ error: 'unknown sku' });
  const qty = Math.max(1, Math.min(Number(req.body.qty) || 1, 100));
  const order = await db.orders.create({
    userId: req.session.userId,
    total: unit * qty,
    status: 'pending',
  });
  return res.status(201).json(order);
}

module.exports = { getCart, checkout };
