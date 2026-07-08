---
fixture_id: sourced-03-export-rationale
bucket: classify
question: why does the data export run as a nightly batch job instead of inline per request
expected_type: why
expect:
  - classifies the question as a why (rationale/history) question
  - gathers rationale from BOTH change records' requirements.md, not just one
  - distinguishes the doc-sourced rationale (inline timed out; batching dedups vendor calls) from the code-confirmed nightly-window gate in src/export/job.ts
  - EACH distinct rationale point carries its own source; merging every reason under a single citation, or citing only one of the two change records, is unsourced and should score sourced < 2
  - no drift flag, no gap row
expect_drift: false
expect_gap: false
---
=== FILE: espalier/.merge-hook-decision ===
not-needed
=== FILE: espalier/changes/2026-01-10-export-job/requirements.md ===
# Export job

Move data export off the request path. Running the export inline blocked the
request thread and timed out past the 30s gateway limit on large accounts, so
it must run as an out-of-band job.
=== FILE: espalier/changes/2026-03-02-export-batching/requirements.md ===
# Export batching

Batch exports on a nightly schedule rather than per-trigger. Multiple triggers
for the same account within a day produced duplicate vendor API calls;
collapsing them into one nightly run cut vendor calls by ~80%.
=== FILE: src/export/job.ts ===
import { isNightlyWindow } from "./schedule";
export async function runExportJob() {
  if (!isNightlyWindow()) return; // only fires in the nightly cron window
  const accounts = await loadDueAccounts();
  for (const a of accounts) await exportAccount(a);
}
=== FILE: src/export/schedule.ts ===
export function isNightlyWindow() {
  const h = new Date().getUTCHours();
  return h >= 2 && h < 4; // 02:00-04:00 UTC
}
