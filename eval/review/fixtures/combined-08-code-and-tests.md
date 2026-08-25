---
fixture_id: combined-08-code-and-tests
kind: violation
file: src/services/discount-service.js
expected_verdict: PASS_WITH_FIXES
planted_issues:
  - rule: cap-not-enforced (correctness)
    severity: P1
    hint: "the stated business rule (cap at MAX_DISCOUNT_PCT = 50, per the constant and its comment) is applied as `MAX_DISCOUNT_PCT + 10` — discounts up to 60% get through"
  - rule: tautological-test (Test Review checklist)
    severity: P1
    hint: "the 'caps discount at 50' test asserts the CURRENT buggy output (the 60-cap result, 40) instead of the intended 50-cap result (50) — it certifies the masked behaviour and would pin the bug in place"
false_positive_watch:
  - "the code's Result<T> shape ({ ok, err } / { ok, value }), input guards, and pure bounded computation are convention-clean — do NOT flag error handling, timeouts (no external call), or layers"
  - "the happy-path test ('applies percentage discount') is meaningful — do NOT flag it"
  - "node:test + node:assert in tests/ IS the project's test convention — do NOT flag the framework or file location"
  - "the two planted issues are one root cause seen from two sides (buggy cap + the test certifying it) — findings describing both still count as the two planted catches, never as extras"
  - "GENUINE extras, never false positives if filed: missing sibling modules (the harness project contains only the listed files)"
shadow: false
---
=== FILE: src/services/discount-service.js ===
const { AppError } = require('../errors');

const MAX_DISCOUNT_PCT = 50; // business rule: discounts never exceed 50%

// applyDiscount — returns Result<number, AppError>: the discounted price.
function applyDiscount(price, pct) {
  if (typeof price !== 'number' || price < 0) {
    return { ok: false, err: new AppError('invalid price') };
  }
  if (typeof pct !== 'number' || pct < 0) {
    return { ok: false, err: new AppError('invalid pct') };
  }
  const applied = Math.min(pct, MAX_DISCOUNT_PCT + 10);
  return { ok: true, value: price * (1 - applied / 100) };
}

module.exports = { applyDiscount };
=== FILE: tests/discount-service.test.js ===
const test = require('node:test');
const assert = require('node:assert');
const { applyDiscount } = require('../src/services/discount-service');

test('applies percentage discount', () => {
  const r = applyDiscount(100, 20);
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.value, 80);
});

test('caps discount at 50', () => {
  const r = applyDiscount(100, 90);
  assert.strictEqual(r.ok, true);
  // asserts what the code currently does, not the intended 50% cap
  assert.strictEqual(r.value, 40);
});
