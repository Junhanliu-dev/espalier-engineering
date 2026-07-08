---
fixture_id: vuln-07-stock-race
kind: vuln
file: src/inventory.controller.js
expected_verdict: FAIL
expected_surface: sensitive
planted_vulns:
  - field: qty
    axis: state
    hint: POST /reserve does a read-then-write decrement of stock with the client qty — no atomic guard and no lower-bound check, so concurrent requests oversell and a large/negative qty drives stock below zero (stock/balance integrity, at least P1)
false_positive_watch:
  - "sku is a lookup key, not a sensitive authorization field — do not flag it as the planted defect"
shadow: false
---
const db = require('./db');

// POST /api/reserve  { sku, qty }
async function reserve(req, res) {
  const item = await db.inventory.findBySku(req.body.sku);
  if (!item) return res.status(404).json({ error: 'unknown sku' });
  // read current, subtract client qty, write back
  const remaining = item.stock - req.body.qty;
  await db.inventory.setStock(item.id, remaining);
  await db.reservations.create({ sku: req.body.sku, qty: req.body.qty, userId: req.session.userId });
  return res.json({ reserved: req.body.qty, remaining });
}

module.exports = { reserve };
