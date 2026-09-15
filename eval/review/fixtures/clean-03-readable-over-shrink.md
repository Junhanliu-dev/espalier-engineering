---
fixture_id: clean-03-readable-over-shrink
kind: clean
file: src/services/discount-service.js
expected_verdict: PASS
planted_issues: []
false_positive_watch:
  - "the three guard clauses in applyDiscount COULD be compressed into one nested ternary — that shorter form is a Readability `nesting:` violation, so a `shrink:` row against the guard clauses at ANY priority is a false positive (the reviewer's own shrink: rule: valid only when the shorter form reads as clearly)"
  - "the module-level Map carries a complete marker — `// ceiling: single-process memo, no eviction; move to the shared cache when a second instance ships` — do NOT file [ceiling], [no-trigger], or yagni: against it"
  - "a single-function service module mirrors the reference service shape the rules mandate — do NOT flag it as an unnecessary layer/abstraction"
  - "MAX_DISCOUNT_PERCENT and FREE_SHIPPING_THRESHOLD_CENTS are the named constants the Readable-by-Default rule requires — do NOT flag them as unused config / yagni"
  - "returns Result<T> via { ok, err } / { ok, value } — do NOT flag error handling"
  - "uses the injected logger, not console — do NOT flag logging"
  - "findCustomer is a repository (internal) call — do NOT flag it for a missing timeout"
  - "the code is already lean — any minimalism or readability finding filed at P0/P1 here is a false positive (advisory P2/P3 notes that name a real, nameable rewrite are not)"
shadow: false
---
const { findCustomer } = require('../repositories/customer-repo');
const { AppError } = require('../errors');
const logger = require('../logger');

const MAX_DISCOUNT_PERCENT = 40;
const FREE_SHIPPING_THRESHOLD_CENTS = 5000;

// ceiling: single-process memo, no eviction; move to the shared cache when a second instance ships
const tierMemo = new Map();

function discountPercentFor(tier) {
  if (tierMemo.has(tier)) {
    return tierMemo.get(tier);
  }
  const percent = tier === 'gold' ? MAX_DISCOUNT_PERCENT : 10;
  tierMemo.set(tier, percent);
  return percent;
}

// applyDiscount — returns Result<{ totalCents: number, freeShipping: boolean }, AppError>
async function applyDiscount(customerId, subtotalCents) {
  if (!customerId) {
    return { ok: false, err: new AppError('missing customerId') };
  }
  if (!Number.isInteger(subtotalCents) || subtotalCents < 0) {
    return { ok: false, err: new AppError('invalid subtotal') };
  }
  const customer = await findCustomer(customerId);
  if (!customer) {
    return { ok: false, err: new AppError('not found') };
  }
  const percent = discountPercentFor(customer.tier);
  const totalCents = Math.round(subtotalCents * (100 - percent) / 100);
  logger.info('applyDiscount', { customerId, percent, totalCents });
  return { ok: true, value: { totalCents, freeShipping: totalCents >= FREE_SHIPPING_THRESHOLD_CENTS } };
}

module.exports = { applyDiscount };
