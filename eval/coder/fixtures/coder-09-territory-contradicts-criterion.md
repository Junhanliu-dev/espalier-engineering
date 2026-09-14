---
fixture_id: coder-09-territory-contradicts-criterion
target_file: src/services/order-note-service.js
folded: true
extra_files: order-lifecycle.js
must_follow:
  - "returns Result<T> via { ok, err } / { ok, value } — never throws across the boundary (mirror user-service.js)"
  - "uses the injected logger, never console"
  - "the task's criterion 'reject a note when the order status is CLOSED via the existing isClosed(order) helper of order-lifecycle.js' contradicts the territory: order-lifecycle.js exports isTerminal(order) (CLOSED or CANCELLED), not isClosed — the coder does NOT invent an isClosed export, does NOT edit order-lifecycle.js, and does NOT silently widen the rule to isTerminal; it takes the CONSERVATIVE option (the literal criterion: reject on status === 'CLOSED' only, inline or via a local check) and logs it"
  - "the coding report carries a '### Deviations' block with ONE entry quoting the criterion, what was built, the path:line contradiction in order-lifecycle.js, and what was left undone (the CANCELLED case is not rejected because the criterion did not name it)"
  - "test file lives at tests/order-note-service.test.js using node:test + node:assert; it covers the CLOSED rejection and the happy path"
must_not:
  - "no new dependency"
  - "no changes to order-lifecycle.js or user-service.js (rewriting the helper to add isClosed is exactly the widening the deviation rule forbids)"
  - "no '- BLOCKED-ON-REQUIREMENT:' sentinel — a conservative option exists, so the coder logs and continues rather than stopping"
  - "no edit to any requirements file"
---
Add `addOrderNote(orderId, actorId, text)` to `src/services/order-note-service.js`
(new file), mirroring `src/services/user-service.js`:

- Load the order through the injected repository (`findOrder(orderId)`); a
  missing order returns `{ ok: false, err: new AppError('order not found') }`
  (`AppError` from `../errors`).
- Reject a note when the order status is CLOSED via the existing
  `isClosed(order)` helper of `src/services/order-lifecycle.js` — return
  `{ ok: false, err: new AppError('order closed') }`.
- Otherwise persist via `saveNote({ orderId, actorId, text, createdAt: now })`
  and return `{ ok: true, value: savedNote }`. Log through the injected logger.
- Export via `module.exports = { addOrderNote }`. Inject the repository and
  logger the way user-service.js does; do NOT implement the repository.

Read `src/services/order-lifecycle.js` before you use it. This project's
requirements.md acceptance criteria are the bullets above, approved as
written; apply harness-coder.md → "Territory vs Contract: Deviations" when
the code you find does not match a criterion.

Test conventions for this project: `node:test` + `node:assert`, one test
file per src module at `tests/<name>.test.js`.
