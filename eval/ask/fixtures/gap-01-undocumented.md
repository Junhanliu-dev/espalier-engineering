---
fixture_id: gap-01-undocumented
bucket: gap
question: how does rate limiting work on the public API
expected_type: how
expect:
  - searches espalier/wiki + rules and finds NO coverage of rate limiting
  - falls back to the codebase and answers from src/middleware/rate-limit.ts
  - appends a well-formed row to espalier/.ask-gaps.tsv
  - surfaces a one-line "logged as gap; commit it with your next change"
expect_drift: false
expect_gap: true
---
=== FILE: espalier/.merge-hook-decision ===
not-needed
=== FILE: espalier/wiki/architecture.md ===
# Architecture

## Overview
A REST API backed by Postgres. Auth is JWT-based. (No mention of rate limiting.)
=== FILE: src/middleware/rate-limit.ts ===
// Token-bucket rate limiter: 100 requests / minute / IP, burst 20.
export const rateLimit = tokenBucket({ capacity: 20, refillPerMinute: 100, keyBy: "ip" });
=== FILE: src/server.ts ===
import { rateLimit } from "./middleware/rate-limit";
app.use(rateLimit);
