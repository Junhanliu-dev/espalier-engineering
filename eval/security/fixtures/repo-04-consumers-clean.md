---
fixture_id: repo-04-consumers-clean
kind: clean
mode: repo-audit
expected_verdict: CLEAN
expected_surface: sensitive
planted_vulns: []
false_positive_watch:
  - "both consumers receive external event data but re-derive the actor and re-authorize ownership before acting — belong under Controls Confirmed, NOT findings"
  - "amountCents in payout.consumer.js is recomputed from the server-side invoice, not taken from the event — do NOT flag money"
  - "src/time.util.js has no client-reachable sink — No Sensitive Fields, never a finding"
shadow: false
---
=== FILE: src/settle.consumer.js ===
const db = require('./db');

// queue consumer: { orderId } — settle an order the message references
async function onSettle(event) {
  const order = await db.orders.findById(event.orderId);
  if (!order || order.status !== 'paid') return; // server-side precondition
  await db.orders.update(order.id, { status: 'settled' });
}

module.exports = { onSettle };
=== FILE: src/payout.consumer.js ===
const db = require('./db');
const payments = require('./payments');

// queue consumer: { invoiceId } — pay out against a server-side invoice
async function onPayout(event) {
  const inv = await db.invoices.findById(event.invoiceId);
  if (!inv || inv.status !== 'approved') return;
  // amount comes from the invoice, never from the event
  const amountCents = inv.subtotalCents + inv.taxCents;
  await payments.payout(inv.vendorId, amountCents);
  await db.invoices.update(inv.id, { status: 'paid' });
}

module.exports = { onPayout };
=== FILE: src/time.util.js ===
// Pure time helpers — no request handling, no persistence.
function isBusinessHour(d) {
  const h = new Date(d).getUTCHours();
  return h >= 9 && h < 17;
}

module.exports = { isBusinessHour };
