---
fixture_id: shadow-02-header-role
kind: vuln
file: src/admin.controller.js
expected_verdict: FAIL
expected_surface: sensitive
planted_vulns:
  - field: x-user-role (request header)
    axis: permission
    hint: the admin gate authorizes off the client-supplied 'x-user-role' request header — a caller sends 'x-user-role: admin' to pass the check; authorization must come from the session/authz store, never a client header
false_positive_watch:
  - "userId from req.session is trusted correctly — do NOT flag it; the defect is the header-derived role"
shadow: true
---
const db = require('./db');

// DELETE /api/admin/users/:id — requires admin
async function deleteUser(req, res) {
  const role = req.headers['x-user-role'];
  if (role !== 'admin') return res.status(403).json({ error: 'forbidden' });
  const actor = req.session.userId;
  await db.audit.log({ actor, action: 'delete_user', target: req.params.id });
  await db.users.delete(req.params.id);
  return res.status(204).end();
}

module.exports = { deleteUser };
