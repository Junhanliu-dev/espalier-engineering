---
fixture_id: vuln-06-identity-spoof
kind: vuln
file: src/transfer.controller.js
expected_verdict: FAIL
expected_surface: sensitive
planted_vulns:
  - field: fromUserId
    axis: identity
    hint: POST /transfer takes the acting account from req.body.fromUserId instead of the session — any caller can move funds out of any user's account by naming it in the body
false_positive_watch:
  - "toUserId is just a destination label, not an authorization decision — flagging it alone is not the planted defect"
shadow: false
---
const db = require('./db');

// POST /api/transfer  { fromUserId, toUserId, amountCents }
async function transfer(req, res) {
  const { fromUserId, toUserId, amountCents } = req.body;
  const from = await db.accounts.findByUser(fromUserId);
  const to = await db.accounts.findByUser(toUserId);
  if (!from || !to) return res.status(404).json({ error: 'account not found' });
  await db.accounts.debit(from.id, amountCents);
  await db.accounts.credit(to.id, amountCents);
  return res.json({ ok: true });
}

module.exports = { transfer };
