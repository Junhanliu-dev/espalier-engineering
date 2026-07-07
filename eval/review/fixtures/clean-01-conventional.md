---
fixture_id: clean-01-conventional
kind: clean
file: src/services/cart-service.js
expected_verdict: PASS
planted_issues: []
false_positive_watch:
  - "returns Result<T> via { ok, err } / { ok, value } — do NOT flag error handling"
  - "uses the injected logger, not console — do NOT flag logging"
  - "a service importing a repository is allowed — do NOT flag layers"
  - "findCart is a repository (internal) call — do NOT flag it for a missing timeout"
  - "naming is camelCase verb-first — do NOT flag naming"
  - "AppError is imported and is the project-standard error type (named in coding-standards.md) — do NOT flag it as undefined/missing-import"
shadow: false
---
const { findCart } = require('../repositories/cart-repo');
const { AppError } = require('../errors');
const logger = require('../logger');

// getCart — returns Result<Cart, AppError>
async function getCart(cartId, userId) {
  logger.info('getCart', { cartId });
  const cart = await findCart(cartId, userId);
  if (!cart) {
    return { ok: false, err: new AppError('not found') };
  }
  return { ok: true, value: cart };
}

module.exports = { getCart };
