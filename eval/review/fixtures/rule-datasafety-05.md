---
fixture_id: rule-datasafety-05
kind: violation
file: src/services/purge-service.js
expected_verdict: FAIL
planted_issues:
  - rule: unbounded-destructive-write (production-standards data-safety, P0)
    severity: P0
    hint: deleteMany with no scoping predicate — an unbounded delete over the whole table (data-loss class)
  - rule: swallowed-error-on-persistence (production-standards observability, P0)
    severity: P0
    hint: the delete failure is caught and ignored, so a failed purge reports success
false_positive_watch:
  - "the injected logger import itself is fine — the defect is that the catch swallows the error, not that a logger exists"
  - "GENUINE extras, never false positives if filed: a second P0 reading the same delete as 'destructive operation without requirements.md authorization' (no requirements.md exists in this harness world), and a P1 for logger-imported-but-never-called / no structured log on either path"
shadow: false
---
const { db } = require('../repositories/db');
const logger = require('../logger');

// purgeExpired — nightly cleanup of expired sessions. Returns Result.
async function purgeExpired() {
  try {
    // Intent was expired-only; this deletes EVERY session (no predicate).
    await db.sessions.deleteMany();
    return { ok: true };
  } catch (e) {
    // swallowed — a failed purge is indistinguishable from a successful one
    return { ok: true };
  }
}

module.exports = { purgeExpired };
