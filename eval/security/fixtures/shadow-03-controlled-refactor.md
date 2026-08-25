---
fixture_id: shadow-03-controlled-refactor
kind: clean
file: src/subscription.controller.js
expected_verdict: PASS
expected_surface: sensitive
planted_vulns: []
false_positive_watch:
  - "this change MOVED the owner check from an inline assertion into requireOwner() but the control is intact — do NOT flag 'ownership check removed'; trace into the helper before concluding a control is missing"
  - "planId is validated against an OWN-PROPERTY allow-list (Object.hasOwn on PLANS) and price is recomputed from the plan, not the body — do NOT flag money, and do NOT flag prototype-chain lookup (the hasOwn guard closes it)"
shadow: true
---
const db = require('./db');

const PLANS = { basic: 900, pro: 2900, team: 9900 }; // cents/month, server-authoritative

async function requireOwner(subId, sessionUserId) {
  const sub = await db.subscriptions.findById(subId);
  if (!sub || sub.userId !== sessionUserId) {
    const err = new Error('not found'); err.status = 404; throw err;
  }
  return sub;
}

// PATCH /api/subscriptions/:subId  { planId }
async function changePlan(req, res) {
  try {
    const sub = await requireOwner(req.params.subId, req.session.userId);
    if (!Object.hasOwn(PLANS, req.body.planId)) {
      return res.status(422).json({ error: 'unknown plan' });
    }
    const priceCents = PLANS[req.body.planId];
    await db.subscriptions.update(sub.id, { planId: req.body.planId, priceCents });
    return res.json({ id: sub.id, planId: req.body.planId, priceCents });
  } catch (e) {
    return res.status(e.status || 500).json({ error: e.message });
  }
}

module.exports = { changePlan };
