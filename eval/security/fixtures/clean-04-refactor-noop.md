---
fixture_id: clean-04-refactor-noop
kind: clean
file: src/pricing.util.js
expected_verdict: PASS
expected_surface: none
planted_vulns: []
false_positive_watch:
  - "pure calculation refactor — no request handling, no auth decision, no persistence, no client-reachable path; the auditor must self-noop with NO SENSITIVE SURFACE, not manufacture a finding about the numbers"
shadow: true
---
// Pure pricing math. No req/res, no db, no I/O — called by the checkout service
// with values the caller has already validated.
const TAX_RATE = 0.08;

function subtotal(lineItems) {
  return lineItems.reduce((sum, li) => sum + li.unitCents * li.qty, 0);
}

function withTax(cents) {
  return Math.round(cents * (1 + TAX_RATE));
}

function total(lineItems) {
  return withTax(subtotal(lineItems));
}

module.exports = { subtotal, withTax, total, TAX_RATE };
