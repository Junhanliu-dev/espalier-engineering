---
fixture_id: rule-throw-01
kind: violation
file: src/services/order-service.js
expected_verdict: FAIL
planted_issues:
  - rule: no-throw (Error Handling Pattern)
    severity: P0
    hint: throws AppError instead of returning Result<T, AppError>
false_positive_watch:
  - "getOrder is a repository (internal) call — do NOT flag it for a missing timeout"
  - "orderId/amount are already-parsed service params, not an HTTP boundary — do NOT flag missing validation"
  - "GENUINE extras, never false positives if filed: missing sibling modules (order-repo / errors do not exist — src/ contains only the file under review by harness design), and an unguarded getOrder rejection propagating as a throw on a money path (same Result-contract family as the planted throws)"
shadow: false
---
const { getOrder } = require('../repositories/order-repo');
const { AppError } = require('../errors');

// createRefund — per coding-standards, should return Result<Refund, AppError>
async function createRefund(orderId, amount) {
  const order = await getOrder(orderId);
  if (!order) {
    throw new AppError('order not found');       // violates Result<T> convention
  }
  if (amount > order.total) {
    throw new AppError('refund exceeds total');  // violates Result<T> convention
  }
  return { ok: true, value: { orderId, amount } };
}

module.exports = { createRefund };
