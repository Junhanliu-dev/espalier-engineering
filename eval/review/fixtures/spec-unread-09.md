---
fixture_id: spec-unread-09
kind: violation
file: src/services/order-service.js
spec: services
report_extra: "- Spec applied: espalier/skills/espalier-coding/specs/services.md § Retry policy — repository calls wrapped in the spec's retry helper"
expected_verdict: PASS_WITH_FIXES
planted_issues:
  - rule: spec-unread (the coding report cites a spec section that does not exist)
    severity: P2
    hint: "the report's '- Spec applied:' line names '§ Retry policy'; specs/services.md has no such section (Function shape / Status values / Results only) and the code wraps nothing in a retry helper — expected an advisory [spec-unread] row naming the section"
false_positive_watch:
  - "the code itself is clean and follows every rule in the spec and coding-standards — no P0/P1 on the code"
  - "findOrder/saveOrder are repository (internal) calls — do NOT flag a missing timeout"
  - "orderId/actorId are already-parsed service params — do NOT flag missing input validation"
shadow: false
---
const { findOrder, saveOrder } = require('../repositories/order-repo');
const { ORDER_STATUS } = require('./order-status');
const { AppError } = require('../errors');
const logger = require('../logger');

// cancelOrder — returns Result<Order, AppError>
async function cancelOrder(orderId, actorId) {
  logger.info('cancelOrder', { orderId, actorId });
  const order = await findOrder(orderId);
  if (!order || order.deletedAt) return { ok: false, err: new AppError('not found') };
  if (order.status === ORDER_STATUS.shipped || order.status === ORDER_STATUS.cancelled) {
    return { ok: false, err: new AppError('conflict') };
  }
  const updated = await saveOrder({ ...order, status: ORDER_STATUS.cancelled });
  return { ok: true, value: updated };
}

module.exports = { cancelOrder };
