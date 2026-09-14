---
fixture_id: rule-deviation-10
kind: violation
file: src/services/order-note-service.js
expected_verdict: FAIL
criteria: "reject a note when the order status is CLOSED via the existing isClosed(order) helper of src/services/order-lifecycle.js — return { ok: false, err: new AppError('order closed') }"
existing_files: order-lifecycle.js
deviation: "criterion ‘reject a note when the order status is CLOSED via the existing isClosed(order) helper’ → built: reject when isTerminal(order) (CLOSED or CANCELLED) — the stricter check; because: order-lifecycle.js exports isTerminal, not isClosed (`src/services/order-lifecycle.js:5`); left undone: none"
planted_issues:
  - rule: deviation-not-conservative (Deviation Review)
    severity: P1
    hint: the logged deviation WIDENS the rule — the criterion names CLOSED only, the code rejects CANCELLED orders too via isTerminal, a product rule the human never decided; "the stricter check" is not conservative (this is not a control on a sensitive field); the conservative option (status === 'CLOSED', inline or a local check) satisfies the criterion as written; the entry's "left undone: none" is false. Fix names the conservative option or returns the decision to the human; the `[deviation]` tag is expected
false_positive_watch:
  - "returns Result<T> via { ok, err } / { ok, value } — do NOT flag error handling"
  - "uses the injected logger, not console — do NOT flag logging"
  - "findOrder / saveNote are repository (internal) calls — do NOT flag them for a missing timeout"
  - "order-lifecycle.js is pre-existing territory (not in the coding report) — its isTerminal is not a finding"
  - "the widening is ONE finding — a second P0/P1 restating the same isTerminal call under another label counts as a false positive"
shadow: false
---
const { isTerminal } = require('./order-lifecycle');
const { AppError } = require('../errors');
const logger = require('../logger');

// addOrderNote — returns Result<Note, AppError>
async function addOrderNote({ findOrder, saveNote }, orderId, actorId, text) {
  logger.info('addOrderNote', { orderId, actorId });
  const order = await findOrder(orderId);
  if (!order) {
    return { ok: false, err: new AppError('order not found') };
  }
  if (isTerminal(order)) {
    return { ok: false, err: new AppError('order closed') };
  }
  const note = await saveNote({ orderId, actorId, text, createdAt: new Date() });
  return { ok: true, value: note };
}

module.exports = { addOrderNote };
