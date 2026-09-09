---
fixture_id: coder-07-two-seam
kind: task
target_file: src/services/order-service.js
spec: services
extra_files: order-status.js
handoff_allowed: true
must_follow:
  - "services seam: cancelOrder(orderId, actorId) in src/services/order-service.js returning Result<T, AppError>, status via ORDER_STATUS constants, logger.info first statement"
  - "controllers seam: cancelOrderHandler(req, res) in src/controllers/order-controller.js calls the service and maps err('not found') → 404, err('conflict') → 409, ok → 200 with the order"
  - "the controller imports the service, never a repository (engineering-structure: controllers never touch db/repositories)"
  - "uses the injected logger, not console"
must_not:
  - "creates or modifies files under repositories/"
  - "adds routes, middleware, or functions beyond the two named"
shadow: false
---
Two seams, one task. (1) Add `cancelOrder(orderId, actorId)` to
`src/services/order-service.js` (new file): load via `findOrder` from
`../repositories/order-repo`, `err` if missing or not cancellable in its state,
otherwise mark cancelled via `saveOrder` and return the updated order as `ok`.
(2) Add `cancelOrderHandler(req, res)` to `src/controllers/order-controller.js`
(new file): read `req.params.orderId` and `req.user.id`, call the service, and
respond 404 for `not found`, 409 for `conflict`, 200 with the order otherwise.
Assume the repository functions and the Express `req`/`res` objects exist — do
NOT implement them. If the task does not fit one spawn, hand off per your
instructions instead of leaving either seam half-written.
