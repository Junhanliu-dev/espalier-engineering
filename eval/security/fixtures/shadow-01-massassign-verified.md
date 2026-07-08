---
fixture_id: shadow-01-massassign-verified
kind: vuln
file: src/signup.controller.js
expected_verdict: FAIL
expected_surface: sensitive
planted_vulns:
  - field: verified / plan (req.body via a partial allow-list)
    axis: permission
    hint: registration binds the request body through a pick() that LOOKS like an allow-list but includes 'verified' and 'plan' alongside display fields — a caller sets account-trust and paid-plan flags at signup (mass assignment; the allow-list is the bug, not its absence)
false_positive_watch:
  - "email and displayName are legitimately client-set — flagging those is a false positive; the defect is that verified/plan are in the same pick()"
shadow: true
---
const db = require('./db');

// fields the signup form is allowed to send
const SIGNUP_FIELDS = ['email', 'displayName', 'verified', 'plan'];

function pick(obj, keys) {
  const out = {};
  for (const k of keys) if (k in obj) out[k] = obj[k];
  return out;
}

// POST /api/signup
async function signup(req, res) {
  const attrs = pick(req.body, SIGNUP_FIELDS);
  const user = await db.users.create({ ...attrs, passwordHash: hash(req.body.password) });
  return res.status(201).json({ id: user.id });
}

function hash(p) { return require('crypto').createHash('sha256').update(p).digest('hex'); }

module.exports = { signup };
