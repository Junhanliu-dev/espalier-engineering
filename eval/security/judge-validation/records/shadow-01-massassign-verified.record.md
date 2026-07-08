## Security Audit: POST /api/signup (src/signup.controller.js) (round 1)

| # | Priority | File | Field / Endpoint | Trusted-from-client defect | Fix |
|---|----------|------|------------------|----------------------------|-----|
| 1 | P0 | src/signup.controller.js:4,15 | verified / POST /api/signup | `verified` is on the `SIGNUP_FIELDS` allow-list and mass-assigned into `db.users.create` from the request body — a client sends `verified:true` and the new account is email-verified without ever verifying (state-axis violation) | drop `verified` from `SIGNUP_FIELDS`; set `verified:false` server-side, flip only through the email-verification flow |
| 2 | P0 | src/signup.controller.js:4,15 | plan / POST /api/signup | `plan` is on the allow-list and mass-assigned from the body — a client sends `plan:"enterprise"` and self-provisions a paid tier (permission-axis escalation) | drop `plan` from `SIGNUP_FIELDS`; default `plan` server-side to the free tier, change only via a server-side entitlement/billing path |

**Verdict:** FAIL

### Summary
- Sensitive surface touched: yes — a client-reachable persistent write (`db.users.create`) on POST /api/signup.
- Sensitive fields in scope: 2 — `verified` (state), `plan` (permission). (`email` is the new account's own self-asserted address at creation, not an actor-spoof; `displayName` is non-sensitive free text.)
- Trust-boundary defects (P0): 2.
- Controls confirmed: an allow-list (`pick`/`SIGNUP_FIELDS`) IS present, but it is mis-scoped — it includes two taxonomy fields, so the allow-list gives false comfort while still mass-assigning sensitive state/permission values. A correct allow-list excludes every taxonomy field.

### Abuse-Test Contract (Stage 5 must satisfy, Stage 6 enforces)

## Security-Sensitive Fields
- field: verified
  endpoint: POST /api/signup
  axis: state
  required_control: new accounts are created unverified server-side; `verified` cannot be set from the request body; it flips only through the email-verification flow
  abuse_test: "POST /api/signup { email, password, verified: true } → response ok, but persisted user.verified == false"
- field: plan
  endpoint: POST /api/signup
  axis: permission
  required_control: `plan` defaults to the free tier server-side and cannot be bound from the request body; tier changes only via a server-side entitlement/billing path
  abuse_test: "POST /api/signup { email, password, plan: 'enterprise' } → response ok, but persisted user.plan == free-tier default (not 'enterprise')"

VERDICT: FAIL p0=2 p1=0 round=1
