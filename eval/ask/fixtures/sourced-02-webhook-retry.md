---
fixture_id: sourced-02-webhook-retry
bucket: classify
question: where are the outbound webhook retry settings configured
expected_type: where
expect:
  - classifies the question as a where (location) question
  - locates all three retry knobs — max attempts, backoff base, and per-attempt timeout — each in its own file
  - EACH of the three values carries its own file:line source; naming one file for "the retry config" without a per-value source is unsourced and should score sourced < 2
  - cites espalier/wiki/critical-paths.md and/or the source files
  - no drift flag (doc matches code), no gap row
expect_drift: false
expect_gap: false
---
=== FILE: espalier/.merge-hook-decision ===
not-needed
=== FILE: espalier/wiki/critical-paths.md ===
# Critical Paths

## Outbound webhooks

Retry behaviour for outbound webhooks is split across three places: the max
attempt count lives in `src/webhook/config.ts`, the exponential backoff base is
in `src/webhook/backoff.ts`, and the per-attempt HTTP timeout is set where the
request is sent, in `src/webhook/sender.ts`.
=== FILE: src/webhook/config.ts ===
export const WEBHOOK_MAX_ATTEMPTS = 5;
=== FILE: src/webhook/backoff.ts ===
import { WEBHOOK_MAX_ATTEMPTS } from "./config";
export const BACKOFF_BASE_MS = 250;
export function delayFor(attempt) {
  return BACKOFF_BASE_MS * 2 ** attempt;
}
=== FILE: src/webhook/sender.ts ===
import { delayFor } from "./backoff";
export const PER_ATTEMPT_TIMEOUT_MS = 3000;
export async function send(url, body) {
  return httpPost(url, body, { timeoutMs: PER_ATTEMPT_TIMEOUT_MS });
}
