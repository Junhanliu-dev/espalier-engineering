---
fixture_id: repo-02-clean
kind: clean
mode: repo-audit
expected_verdict: CLEAN
expected_surface: sensitive
planted_vulns: []
false_positive_watch:
  - "teamId lookups are owner-scoped in the query (findWhere id+ownerId) — do NOT flag IDOR"
  - "renameTeam binds an explicit allow-list (name only) — do NOT flag mass assignment"
  - "src/status.job.js is a cron job with NO client input (query + values are server-derived) — do NOT flag the direct status write as a state defect"
shadow: false
---
=== FILE: src/team.controller.js ===
const db = require('./db');

// GET /api/teams/:teamId — owner-scoped
async function getTeam(req, res) {
  const team = await db.teams.findWhere({ id: req.params.teamId, ownerId: req.session.userId });
  if (!team) return res.status(404).json({ error: 'not found' });
  return res.json(team);
}

// PATCH /api/teams/:teamId — owner-scoped, allow-list bind
async function renameTeam(req, res) {
  const team = await db.teams.findWhere({ id: req.params.teamId, ownerId: req.session.userId });
  if (!team) return res.status(404).json({ error: 'not found' });
  await team.update({ name: String(req.body.name).slice(0, 80) });
  return res.json(team);
}

module.exports = { getTeam, renameTeam };
=== FILE: src/status.job.js ===
const { daysAgo } = require('./time.util');

// Nightly cron — no client input; criteria and values are server-derived.
async function expireStaleDrafts(db) {
  await db.orders.updateWhere(
    { status: 'draft', updatedAt: { lt: daysAgo(30) } },
    { status: 'expired' }
  );
}

module.exports = { expireStaleDrafts };
