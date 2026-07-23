---
fixture_id: rule-readability-07
kind: violation
file: src/services/invoice-service.js
expected_verdict: FAIL
planted_issues:
  - rule: cryptic-exported-name (Readability)
    severity: P1
    hint: the exported service function is named `proc` — the name states nothing
      about what it does (collect a customer's unpaid overdue invoices); the fix
      names an intent-stating replacement (e.g. `getOverdueInvoices`) at the
      definition and in `module.exports`
false_positive_watch:
  - "returns Result<T> via { ok, err } / { ok, value } — do NOT flag error handling"
  - "uses the injected logger, not console — do NOT flag logging"
  - "findInvoicesByCustomer is a repository (internal) call — do NOT flag it for a missing timeout"
  - "no new dependency is introduced — do NOT flag a minimalism new-dependency P1"
  - "the terse INTERNAL locals (`x`, `inv`) are advisory-only per the Readability rule — a P0/P1 finding on an internal local counts as a false positive"
  - "the `proc` name is ONE finding — a second P0/P1 restating the same name under another label (once for the function, once for the export line) counts as a false positive"
shadow: false
---
const { findInvoicesByCustomer } = require('../repositories/invoice-repo');
const { AppError } = require('../errors');
const logger = require('../logger');

// proc — returns Result<Invoice[], AppError>
async function proc(customerId) {
  logger.info('proc', { customerId });
  const invoices = await findInvoicesByCustomer(customerId);
  if (!invoices) {
    return { ok: false, err: new AppError('not found') };
  }
  const now = Date.now();
  const inv = invoices.filter((x) => x.dueAt < now && !x.paidAt);
  return { ok: true, value: inv };
}

module.exports = { proc };
