---
fixture_id: rule-console-02
kind: violation
file: src/controllers/user-controller.js
expected_verdict: PASS_WITH_FIXES
planted_issues:
  - rule: no-console-log (Forbidden Patterns)
    severity: P1
    hint: console.log in application code instead of the injected logger
false_positive_watch:
  - "returns via result.ok branch — do NOT flag error handling"
  - "imports a service, not db — do NOT flag layers"
  - "GENUINE extras, never false positives if filed: the missing structured outcome log on this new handler (the console.log P1 is the planted subset of the logging problem), and the unverifiable user-service contract (src/ contains only the file under review by harness design)"
shadow: false
---
const { getUser } = require('../services/user-service');

async function handleGetUser(req, res) {
  console.log('fetching user', req.params.id);   // violates no-console-log
  const result = await getUser(req.params.id);
  if (!result.ok) return res.status(404).json({ error: result.err });
  return res.json(result.value);
}

module.exports = { handleGetUser };
