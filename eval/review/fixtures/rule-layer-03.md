---
fixture_id: rule-layer-03
kind: violation
file: src/controllers/report-controller.js
expected_verdict: FAIL
planted_issues:
  - rule: controller-no-db (Boundary Rule)
    severity: P0
    hint: a controller imports and queries db directly, bypassing a service (layer violation)
false_positive_watch:
  - "errors are handled via try/catch — do NOT flag error handling or a possible throw"
  - "req.session.userId is server-set (not req.body/params/query) — do NOT flag it as unvalidated input"
  - "db.query is an internal call — do NOT flag it for a missing timeout"
shadow: false
---
const db = require('../db');   // controller importing db — the planted layer violation

async function handleReport(req, res) {
  try {
    const rows = await db.query('SELECT * FROM reports WHERE owner_id = $1', [req.session.userId]);
    return res.json(rows);
  } catch (e) {
    return res.status(500).json({ error: 'internal' });
  }
}

module.exports = { handleReport };
