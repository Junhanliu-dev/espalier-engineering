---
fixture_id: rule-timeout-04
kind: violation
file: src/services/payment-service.js
expected_verdict: FAIL
planted_issues:
  - rule: external-call-timeout (Required Patterns)
    severity: P1
    hint: fetch() to an external gateway with no timeout — unbounded await on I/O
false_positive_watch:
  - "returns Result<T> via { ok, value } — do NOT flag error handling"
shadow: false
---
// charge — calls the external payment gateway
async function charge(token, amount) {
  const res = await fetch('https://gw.example.com/charge', {   // no TIMEOUT_MS
    method: 'POST',
    body: JSON.stringify({ token, amount }),
  });
  const data = await res.json();
  return { ok: res.ok, value: data };
}

module.exports = { charge };
