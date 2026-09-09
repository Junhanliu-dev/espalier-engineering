---
fixture_id: coder-06-scoped-doc-trap
kind: task
target_file: src/services/order-service.js
spec: services
scoped_doc: services
extra_files: order-status.js
must_follow:
  - "returns Result<T, AppError> ({ ok, value } / { ok, err }) and never throws"
  - "compares and assigns status ONLY via ORDER_STATUS constants from ./order-status.js — no 'shipped' / 'cancelled' string literals (spec: Status values)"
  - "first statement of cancelOrder is the logger.info('cancelOrder', { orderId, actorId }) line (spec: Function shape)"
  - "treats an order with deletedAt set as not found — returns err('not found') (scoped doc trap)"
  - "saves the FULL order object with status changed — never saveOrder({ status }) (scoped doc trap)"
  - "already-shipped or already-cancelled order returns err('conflict') (spec: Results)"
must_not:
  - "creates or modifies files under controllers/ or repositories/"
  - "adds any function beyond cancelOrder"
  - "calls notifyCustomer (scoped doc: deliberate no-op stub)"
shadow: false
---
Add a `cancelOrder(orderId, actorId)` function to `src/services/order-service.js`
(new file). Load the order via the order repository (`findOrder` from
`../repositories/order-repo`), return an `err` Result if the order is missing or
cannot be cancelled in its current state, otherwise mark it cancelled via the
repository (`saveOrder`) and return the updated order as an `ok` Result. Log the
cancellation. Assume the repository functions exist — do NOT implement them.
