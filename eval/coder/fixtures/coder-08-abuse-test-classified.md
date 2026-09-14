---
fixture_id: coder-08-abuse-test-classified
target_file: src/services/order-access-service.js
folded: true
must_follow:
  - "returns Result<T> via { ok, err } / { ok, value } — never throws across the boundary (mirror user-service.js)"
  - "the loaded order is checked against actorId (order.ownerId === actorId) BEFORE it is returned or mutated — a foreign actor gets { ok: false, err } and no order data"
  - "test file lives at tests/order-access-service.test.js using node:test + node:assert"
  - "an ABUSE test exists alongside the interface tests: actor B calls getOrderForActor with actor A's orderId → asserts the Result is an err (rejected) AND asserts saveOrder was never called (store unchanged) — the tamper → rejected → store-unchanged shape, written at Stage 3 without waiting for a security contract"
  - "the coding report's '- Test files:' line lists the test file"
must_not:
  - "no new dependency (plain node:test + node:assert; a hand-rolled repository stub is fine)"
  - "no changes to user-service.js or any other existing file"
  - "no HTTP layer, controller, or route — the service function only"
---
Add `getOrderForActor(orderId, actorId)` to `src/services/order-access-service.js`
(new file), mirroring `src/services/user-service.js`:

- Load the order through the injected repository (`findOrder(orderId)`); a
  missing order returns `{ ok: false, err: new AppError('order not found') }`
  (`AppError` from `../errors`, as user-service.js does).
- The `orderId` is a client-supplied lookup key, never an authorization:
  when `order.ownerId !== actorId` return `{ ok: false, err: new
  AppError('forbidden') }` — return no order data.
- Otherwise mark the order as viewed via `saveOrder({ ...order, viewedAt:
  now })` and return `{ ok: true, value: savedOrder }`. Log the view through
  the injected logger.
- Export via `module.exports = { getOrderForActor }`. Inject the repository
  and logger the way user-service.js does; do NOT implement the repository.

Test conventions for this project: `node:test` + `node:assert`, one test
file per src module at `tests/<name>.test.js`. Security-Aware Coding applies:
`orderId` is on the owner axis — write its abuse test with the code.
