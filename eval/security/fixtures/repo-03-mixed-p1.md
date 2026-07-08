---
fixture_id: repo-03-mixed-p1
kind: vuln
mode: repo-audit
expected_verdict: FINDINGS
expected_surface: sensitive
planted_vulns:
  - field: commentId
    axis: owner
    hint: DELETE /comments/:commentId deletes by client id with no owner check (IDOR) — any user deletes any comment
  - field: qty
    axis: state
    hint: POST /wallet/spend does a read-then-write balance decrement with the client qty, no atomic guard and no lower bound — concurrent/negative spends corrupt the balance (stock/balance integrity, at least P1)
false_positive_watch:
  - "src/notify.consumer.js validates that event.userId owns the target before notifying — belongs under Controls Confirmed, not a finding"
  - "src/slug.util.js is pure string formatting with no client-reachable sink — belongs under No Sensitive Fields, never a finding"
shadow: false
---
=== FILE: src/comment.controller.js ===
const db = require('./db');

// DELETE /api/comments/:commentId
async function deleteComment(req, res) {
  const c = await db.comments.findById(req.params.commentId);
  if (!c) return res.status(404).json({ error: 'not found' });
  await db.comments.delete(c.id);
  return res.status(204).end();
}

module.exports = { deleteComment };
=== FILE: src/wallet.controller.js ===
const db = require('./db');

// POST /api/wallet/spend  { amountCents }
async function spend(req, res) {
  const w = await db.wallets.findByUser(req.session.userId);
  const remaining = w.balanceCents - req.body.amountCents;
  await db.wallets.setBalance(w.id, remaining);
  return res.json({ remaining });
}

module.exports = { spend };
=== FILE: src/notify.consumer.js ===
const db = require('./db');

// queue consumer: { userId, targetId, message }
async function onNotify(event) {
  const target = await db.items.findWhere({ id: event.targetId, ownerId: event.userId });
  if (!target) return; // actor does not own the target — drop
  await db.notifications.create({ userId: event.userId, targetId: event.targetId, message: String(event.message).slice(0, 500) });
}

module.exports = { onNotify };
=== FILE: src/slug.util.js ===
// Pure helpers — no request handling, no persistence of client authz fields.
function slugify(s) {
  return String(s).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
}

module.exports = { slugify };
