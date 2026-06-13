---
fixture_id: classify-01-where-handler
bucket: classify
question: where is the password reset request handled
expected_type: where
expect:
  - classifies the question as a where (location) question
  - cites espalier/wiki/critical-paths.md and/or the source file
  - names src/auth/reset.ts as the handler location
  - no drift flag (doc matches code), no gap row (doc covers it)
expect_drift: false
expect_gap: false
---
=== FILE: espalier/.merge-hook-decision ===
not-needed
=== FILE: espalier/wiki/critical-paths.md ===
# Critical Paths

## Password reset
Entry: `POST /auth/reset-request` → `requestReset()` in `src/auth/reset.ts`.
Sends a signed token by email; the token is verified on `POST /auth/reset-confirm`.
=== FILE: src/auth/reset.ts ===
// Password reset handlers.
export function requestReset(email: string) {
  const token = signToken(email);
  return mailer.send(email, "reset", token);
}
export function confirmReset(token: string, newPassword: string) {
  const email = verifyToken(token);
  return users.setPassword(email, newPassword);
}
