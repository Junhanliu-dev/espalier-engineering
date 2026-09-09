# src/services/ — traps and invariants (scoped doc)

Claims the code cannot show. Verify against the code before relying on one.

- **`saveOrder(order)` overwrites the whole row.** Pass the full order object
  with the changed field — `saveOrder({ ...order, status: ORDER_STATUS.cancelled })`
  or mutate then save. A partial `saveOrder({ status })` wipes `items` and
  `customerId` (happened in the 2025-11 incident).
- **`findOrder(id)` returns soft-deleted orders too** (`deletedAt` set). Every
  service treats `order.deletedAt` as not found; only the admin restore path
  reads them.
- **Deliberate stub:** `notifyCustomer` in `src/services/notify.js` is a no-op
  until the mail provider lands — do not call it expecting an email.
