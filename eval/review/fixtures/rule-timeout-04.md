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
  - "wrapped in try/catch returning an err Result — do NOT flag error handling or a possible throw"
shadow: false
---
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
