---
fixture_id: coder-01-cancel-order
kind: task
target_file: src/services/order-service.js
must_follow:
  - returns Result<T, AppError> ({ ok, value } / { ok, err }) and never throws
  - placed in src/services/ (business-logic layer)
  - uses the injected logger, not console
  - mirrors the reference pattern in src/services/user-service.js
must_not:
  - creates or modifies files under controllers/ or repositories/
  - adds any function beyond cancelOrder
shadow: false
---
Add a `cancelOrder(orderId, actorId)` function to the order service. Load the order
via the order repository (`findOrder`), return an `err` Result if the order is
missing or already shipped, otherwise mark it cancelled via the repository
(`saveOrder`) and return the updated order as an `ok` Result. Log the cancellation.
Assume the repository functions exist — do NOT implement them.
