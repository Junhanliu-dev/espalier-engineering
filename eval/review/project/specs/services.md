# Layer spec — `src/services/` (CoderApp — eval fixture project)

The shape every service function takes. `src/services/user-service.js` is the
reference; this file names the parts of the shape the reference cannot show.

## Function shape
- One exported `async function` per capability; `module.exports = { name }` at
  the bottom, exactly like `user-service.js`.
- The FIRST statement of every service function is the structured log line:
  `logger.info('<functionName>', { <the ids it received> })` — before any
  repository call, so a hang is attributable.

## Status values
- Order status is compared and assigned ONLY through the `ORDER_STATUS`
  constants in `src/services/order-status.js` — never a string literal
  (`'shipped'`, `'Shipped'`). Stored values are lowercase; the literal form has
  drifted twice in this codebase.

## Results
- A missing row is `{ ok: false, err: new AppError('not found') }` — that exact
  message is what controllers map to 404.
- A state conflict (already shipped, already cancelled) is
  `{ ok: false, err: new AppError('conflict') }` — mapped to 409.
