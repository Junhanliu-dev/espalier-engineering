---
fixture_id: vuln-05-queue-consumer
kind: vuln
file: src/refund.consumer.js
expected_verdict: FAIL
expected_surface: sensitive
planted_vulns:
  - field: orderId
    axis: owner
    hint: the consumer acts on an order addressed by message orderId with no ownership / tenant check — a NON-HTTP surface the auditor must NOT self-noop
  - field: amount
    axis: money
    hint: the refund amount is taken from the message with no server-side recompute against the order
false_positive_watch:
  - "status is the literal 'approved' — server-set, never client-written; a missing paid/refundable precondition, idempotency, or replay of the same message is the reviewer's production-readiness concern and a second effect of the planted missing recompute (amount), not a separate P0/P1"
shadow: false
---
const db = require('./db');

// Message-queue consumer for the 'refund.requested' topic.
// msg = { orderId, amount, requestedBy }
async function onRefundRequested(msg) {
  const order = await db.orders.findById(msg.orderId);
  await db.refunds.create({
    orderId: order.id,
    amount: msg.amount,      // trusted straight from the message
    status: 'approved',
  });
}

module.exports = { onRefundRequested };
