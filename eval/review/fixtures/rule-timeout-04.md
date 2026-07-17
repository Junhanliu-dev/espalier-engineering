---
fixture_id: rule-timeout-04
kind: violation
file: src/services/payment-service.js
expected_verdict: PASS_WITH_FIXES
planted_issues:
  - rule: external-call-timeout (Required Patterns)
    severity: P1
    hint: fetch() to an external gateway with no timeout — unbounded await on I/O
false_positive_watch:
  - "a try/catch exists and the catch returns an err Result — do NOT flag a missing try/catch or a possible unhandled throw"
  - "GENUINE extras, never false positives if filed: the malformed Result on a non-2xx (`ok: res.ok` yields `{ ok: false }` with no err field while parsing the body as value), the catch flattening the cause to a constant string / missing structured log, and missing sibling modules (src/ contains only the file under review by harness design)"
shadow: false
---
const { AppError } = require('../errors');

// charge — calls the external payment gateway. Returns Result<Charge, AppError>.
async function charge(token, amount) {
  try {
    const res = await fetch('https://gw.example.com/charge', {   // no timeout applied — the planted issue
      method: 'POST',
      body: JSON.stringify({ token, amount }),
    });
    return { ok: res.ok, value: await res.json() };
  } catch (e) {
    return { ok: false, err: new AppError('gateway error') };
  }
}

module.exports = { charge };
