---
fixture_id: classify-02-why-decision
bucket: classify
question: why do we queue emails instead of sending them inline
expected_type: why
expect:
  - classifies the question as a why (rationale/history) question
  - cites the change record requirements.md as the rationale source
  - explains the reason (inline sends blocked the request thread / timed out)
  - no drift flag, no gap row
expect_drift: false
expect_gap: false
---
=== FILE: espalier/.merge-hook-decision ===
not-needed
=== FILE: espalier/changes/feat/2026-03-02-async-email/requirements.md ===
# Requirement: async email delivery

## Why
Inline SMTP sends inside the request handler blocked the worker thread and
caused p99 latency spikes; under load the SMTP call timed out and dropped the
user's response. Decision: enqueue email jobs and send from a background worker.

## Acceptance criteria
- request handler returns before any SMTP call
- failed sends retry with backoff
=== FILE: src/email/queue.ts ===
// Email is enqueued here, never sent inline. See changes/feat/2026-03-02-async-email.
export function enqueueEmail(job: EmailJob) {
  return queue.add("email", job, { attempts: 5, backoff: 30000 });
}
