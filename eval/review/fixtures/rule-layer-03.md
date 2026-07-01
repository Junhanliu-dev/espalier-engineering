---
fixture_id: rule-layer-03
kind: violation
file: src/controllers/report-controller.js
expected_verdict: FAIL
planted_issues:
  - rule: controller-no-db (Boundary Rule)
    severity: P0
    hint: a controller imports and queries db directly, bypassing a service (layer violation)
false_positive_watch: []
shadow: false
---
const db = require('../db');   // controller importing db — layer violation

async function handleReport(req, res) {
  const rows = await db.query('SELECT * FROM reports WHERE user_id = $1', [req.session.userId]);
  return res.json(rows);
}

module.exports = { handleReport };
