---
fixture_id: vuln-03-massassign-role
kind: vuln
file: src/user.controller.js
expected_verdict: FAIL
expected_surface: sensitive
planted_vulns:
  - field: role
    axis: permission
    hint: PATCH /users spreads req.body into the update (mass assignment) so a client can set role / isAdmin — privilege escalation
false_positive_watch: []
shadow: false
---
const db = require('./db');

// PATCH /api/users/me  — update the caller's own profile
async function updateProfile(req, res) {
  const updated = await db.users.update(req.session.userId, { ...req.body });
  return res.json(updated);
}

module.exports = { updateProfile };
