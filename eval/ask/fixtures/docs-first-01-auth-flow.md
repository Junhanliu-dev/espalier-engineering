---
fixture_id: docs-first-01-auth-flow
bucket: docs-first
question: how does login authentication work
expected_type: how
expect:
  - reads espalier/wiki/architecture.md FIRST (before crawling the codebase)
  - verifies the doc's claim by reading the cited src/auth/service.ts
  - answer cites both the wiki and src/auth/service.ts with the JWT detail
  - no drift flag (doc matches code), no gap row
expect_drift: false
expect_gap: false
---
=== FILE: espalier/.merge-hook-decision ===
not-needed
=== FILE: espalier/wiki/architecture.md ===
# Architecture

## Authentication
`POST /login` is handled by `AuthService.login()` in `src/auth/service.ts`. It
validates the credentials against the `users` table and, on success, issues a
signed JWT with a 24h expiry. The JWT is returned in the response body.
=== FILE: src/auth/service.ts ===
import { signJwt } from "./jwt";
export class AuthService {
  async login(email: string, password: string) {
    const user = await users.findByEmail(email);
    if (!user || !verifyPassword(user, password)) throw new AuthError();
    return signJwt({ sub: user.id }, { expiresIn: "24h" });
  }
}
=== FILE: src/auth/jwt.ts ===
export function signJwt(payload: object, opts: object) {
  return jwt.sign(payload, process.env.JWT_SECRET, opts);
}
