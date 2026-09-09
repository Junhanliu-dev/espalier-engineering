# Mode: repo-audit

Read by `harness-security` when the spawning prompt says **REPO-AUDIT MODE** (`/espalier-audit`). Named on that prompt line by the orchestrator;
not loaded otherwise. Verbatim procedure — the agent body keeps the heading
and a one-line pointer; nothing here is a budget.

## Repo-Audit Mode (spawned by /espalier-audit)

When the spawning prompt says **REPO-AUDIT MODE**, you are auditing EXISTING
code — a list of surface files as they stand now — not a pipeline change. There
is no `coding-report.md`, no `changes/` dir, and nothing to hard-block. The
taxonomy, the required controls, the trace-to-sink process (Audit Process steps
1-3), and the priority rubric all apply unchanged, with these deltas:

1. **Scope = the listed files, whole.** Audit every handler/consumer in each
   listed file, not a diff. Follow a client value into a helper the file calls
   (read the helper) — the control may live one hop away; say so when it does.
2. **Do NOT write `security-record.md`.** Return your findings as your final
   message in the exact format below — the `/espalier-audit` orchestrator
   consolidates batches into `espalier/wiki/security-audit.md`. In this mode
   your final message is data for the orchestrator, not prose for a human.
3. **The scope gate inverts.** The orchestrator pre-selected candidate
   surfaces, so do not self-noop the whole run — but a listed file that turns
   out to carry no sensitive client input goes under `### No Sensitive Fields`,
   never into manufactured findings. The no-manufacture rule is unchanged.
4. **Contract entries are per-DEFECT only.** In change-audit mode every
   in-scope sensitive field gets a contract entry; repo-wide that would balloon
   to the whole codebase. Emit a `### Security-Sensitive Fields` entry only for
   each finding — it seeds the abuse test of the `/espalier-fix` lane that will
   fix it. Confirmed-controlled fields go under `### Controls Confirmed` instead.
5. **Findings do not block.** There is no gate and no fixpoint loop here — a P0
   ranks the fix queue (Priority Rubric bar unchanged), it is not a verdict on a
   change.

Repo-audit output format (your ENTIRE final message):

```
## Repo-Audit Findings: {batch scope}
| # | Priority | File | Field / Endpoint | Trusted-from-client defect | Fix |
|---|----------|------|------------------|----------------------------|-----|

**Batch verdict:** FINDINGS ({n}) / CLEAN

### Security-Sensitive Fields
- field: ...
  endpoint: ...
  axis: money | identity | permission | owner | state
  required_control: ...
  abuse_test: "..."

### Controls Confirmed
- {endpoint} — {control present} ({file:line})

### No Sensitive Fields
- {file} — {why it carries no sensitive client input}
```

Omit an empty subsection's entries but keep its heading — the orchestrator
parses by heading. An empty findings table with `**Batch verdict:** CLEAN` is a
correct, complete answer for a well-controlled batch.
