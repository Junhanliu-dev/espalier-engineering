# Development Pipeline

## Stages

### 1. Requirements Analysis
- **Trigger:** New requirement received
- **Load:** Read espalier/skills/espalier-requirements/SKILL.md (which invokes espalier-grill)
- **Execute:** Main agent produces the requirements doc; `espalier-grill` interrogates it (adaptive depth) unless `--no-grill` was passed
- **Gate:** Requirements doc exists with acceptance criteria (≥ 2 criteria)
- **Output:** espalier/changes/{type}/{slug}/requirements.md

### 2. Requirements Review
- **Trigger:** Requirements doc complete
- **Load:** Read espalier/skills/espalier-review/SKILL.md
- **Execute:** Main agent reviews the requirements doc
- **Gate:** No P0/P1 findings remaining
- **Limit:** Max `max-req-rounds` review rounds (default 3, from `espalier/.espalier-config`) → escalate to human
- **Human checkpoint (BLOCKING):** user approves `requirements.md` before ANY
  coding. Stage 3 does not start on a Stage 2 PASS alone — see the espalier
  skill → "Requirements Approval Gate". Auto-approved only on a no-TTY run.
- **Output:** espalier/changes/{type}/{slug}/review-record.md (append)

### 3. Coding Implementation
- **Trigger:** Requirements approved
- **Load:** Spawn `harness-coder` agent (see espalier/agents/harness-coder.md)
- **Execute:** Sub-agent implements per task decomposition
- **Gate (PROGRAMMATIC):** all sub-tasks done + the ORCHESTRATOR re-runs the
  discovered build and lint commands itself and both exit 0 — the coder's
  self-reported "Build status: pass" is a claim, not the gate. A failing
  build/lint re-run goes straight back to the coder WITHOUT spawning the Stage 4
  panel (a panel round on unbuildable code is wasted).
- **Constraint:** One sub-agent invocation per sub-task
- **Baseline (first entry only):** before any code is written, record
  `Base-Ref: $(git rev-parse HEAD)` as a line in pipeline-state.md. Never overwrite
  it on a coder re-spawn — it anchors the Stage 4/6 review fingerprint and the push gate.
- **Output:** Code changes + espalier/changes/{type}/{slug}/coding-report.md

### 4. Code Review (fixpoint loop — a two-agent review panel, re-review after EVERY fix)
- **Trigger:** Implementation complete (Stage 3 done)
- **Review panel:** every review round runs TWO fresh agents on the CURRENT diff, spawned
  concurrently — `harness-reviewer` (correctness / conventions, → review-record.md)
  and `harness-security` (trust boundary — never trust frontend data, → security-record.md).
- **Loop — repeat until exit:**
  1. Spawn the FRESH panel on the CURRENT diff. On a re-review round, also hand each
     agent the "changed since last review" set — the fix's files from the latest
     coding-report.md — so they scrutinize the new code while still owning the
     whole-diff verdict.
  2. **P0 found by EITHER agent →** re-spawn `harness-coder` with the combined
     findings (a Stage 3 action), then **return to step 1 and re-review the NEW
     diff with the whole panel.** Never advance to Stage 5 on the coder's fix report
     alone — a fix is never the last action before the gate; a clean panel is. Each
     P0 round increments the counter.
  3. **Zero P0 from BOTH agents on a fresh review of the current code →** PASS;
     record the certificate (below) and exit.
- **Gate (to leave Stage 4):** the MOST RECENT run of BOTH panel agents saw the
  CURRENT code and returned zero P0 — NOT "the earlier P0s were addressed." A coder
  fix always triggers another full panel round.
- **Certificate (write on PASS):** `git add -A` (so new files count), then record in
  pipeline-state.md, overwriting any prior value —
  `Reviewed-Diff: $(git diff <Base-Ref> -- . ':(exclude)espalier/' | git hash-object --stdin)`
  where `<Base-Ref>` is the Stage 3 SHA. The Stage 7 push gate blocks unless this
  fingerprint still matches the code being pushed.
- **Limit:** Max `max-code-rounds` P0 rounds (default 3, from `espalier/.espalier-config`)
  → escalate to human (never silently ship); at counter = `max-code-rounds`, escalate
  WITHOUT another coder re-spawn. A security P0 (from `harness-security`) shares this
  counter with correctness P0s.
- **Panel P0 collection (procedural — see the espalier skill):** each round, after
  BOTH agents return, confirm BOTH records were written THIS round (baseline
  size/mtime + a `VERDICT:` sentinel whose `round=` matches), then read the gate
  from the sentinel line of EACH file: `grep '^VERDICT:' <record> | tail -1` —
  either `p0=` > 0 → re-spawn coder + re-run panel. A record missing its sentinel,
  or unchanged since baseline, means that agent did NOT complete — re-spawn that
  agent; never treat a missing/stale record as a pass. The certificate is written
  only when BOTH sentinels read `p0=0`; drift processing runs only on that PASS.
- **Security contract (on PASS):** `harness-security` writes a
  `## Security-Sensitive Fields` block into security-record.md — one entry per
  client-supplied sensitive field in scope. This is the Stage 5/6 abuse-test contract.
- **Output:** espalier/changes/{type}/{slug}/review-record.md + security-record.md — BOTH
  OVERWRITTEN each round (each reflects the current round only, so the orchestrator
  never reads a stale prior-round verdict). Before overwriting begins, the
  orchestrator snapshots each round's two sentinel lines into pipeline-state.md
  Stage History (`| 4 | ROUND {n} FAIL | {ts} | reviewer: FAIL p0=2; security: PASS p0=0 |`),
  so round history survives the overwrite.

### 5. Test Writing
- **Trigger:** Code review passed
- **Load:** Spawn `harness-coder` agent with testing skill
- **Execute:** Write tests for changed interfaces. ALSO write the negative abuse
  test named by EVERY entry in security-record.md's `## Security-Sensitive Fields`
  contract (tamper the value → assert rejected → assert persistent store unchanged).
- **Gate:** Tests exist for every changed public interface + tests pass + every
  contracted sensitive field has its abuse test

### 6. Test Review
- **Trigger:** Tests written
- **Load:** Spawn `harness-reviewer` agent
- **Execute:** Review tests for meaningfulness + security abuse-test coverage +
  failure-mode coverage (production-standards: every NEW external-call path has a
  dependency-failure test — missing one is a P1)
- **Gate:** Tests are meaningful (not just "passes"), cover edge cases, AND every
  field in security-record.md's `## Security-Sensitive Fields` contract has a
  passing abuse test (tamper → rejected → store unchanged). A missing one is a P0.
  Same record semantics as Stage 4: the reviewer OVERWRITES review-record.md with
  a `VERDICT:` sentinel; the orchestrator freshness-checks + greps it.
- **Loop:** same fixpoint rule as Stage 4 — a P0 sends the tests back to Stage 5
  (re-spawn coder), then **re-review**; never exit on the fix report alone.
- **Certificate (on PASS):** re-run the Stage 4 fingerprint (it now covers the added
  tests) and overwrite `Reviewed-Diff` in pipeline-state.md — the push gate compares
  against this value.
- **Limit:** Max `max-test-rounds` rounds (default 3, from `espalier/.espalier-config`) → escalate

### 7. Code Push
- **Trigger:** Tests reviewed
- **Gate (PROGRAMMATIC):**
  - `git status` shows clean working tree (all staged/committed)
  - Branch name matches convention
  - No merge conflicts
- **Human checkpoint:** Confirm push target
- **Output:** `espalier/changes/{type}/{slug}/pipeline-state.md` gains a `## Commits` table row (Stage 7, SHA, files) — read by `/espalier-fix` reverse lookup.

### 8. CI Verification
- **Gate (PROGRAMMATIC — all must be true):**
  - `ci_status == "success"`
  - `total_tests > 0`
  - `tests_passed == total_tests`
  - `lint_errors == 0`
- **Verify by:** Running CI command or reading CI output
- **Rollback:**
  - `total_tests == 0` → Stage 5
  - Compile/build failure → Stage 3
  - Lint failure → Stage 3
- **Output:** espalier/changes/{type}/{slug}/ci-result.md

### 8.5 Doc Drift Check (notify-only)
- **Trigger:** Stage 8 (CI) passed
- **Execute:** read `espalier/.drift-state.tsv`; if any docs are flagged, append
  a notify table to the change's `doc-patches.md` and surface one line
- **Gate:** none — notify-only. Edits no rule/wiki/spec file, prompts nothing,
  never blocks the pipeline.
- **Note:** "8.5" is a label, NOT a numeric stage. `pipeline-state.md`
  `Current Stage:` never holds `8.5` — the orchestrator runs this as a sub-step
  between Stage 8 and Stage 9 and records it in the Stage History notes only.
  This keeps `pre-push-gate.sh`'s integer stage parse correct.
- **Output:** `espalier/changes/{type}/{slug}/doc-patches.md` (created on demand)

### 9. Deployment Verification
- **Trigger:** CI passed (Stage 8)
- **Load:** the `## Deploy & Verification` section of
  `espalier/rules/development-process.md` (filled from DISCOVERY.deploy at init).
- **Two modes:**
  - **No deploy configured** (the section reads "No deploy configuration
    discovered"): record `| 9 | SKIPPED | {ts} | no-deploy-config |` in Stage
    History and advance. This is a clean pass, not a gap — a repo that doesn't
    deploy per change has nothing to verify here.
  - **Deploy configured:** confirm deploy parameters (human checkpoint), run the
    discovered deploy command (or confirm the automatic deploy completed), then
    run the discovered **health check** against the target environment.
- **Gate (PROGRAMMATIC when configured):** health check returns success
  (HTTP 2xx on the health path, or the health command exits 0).
- **Rollback:** health check fails → do NOT proceed to Stage 10; surface the
  failure, follow the project's rollback/redeploy procedure, and record it.
- **Output:** `espalier/changes/{type}/{slug}/deploy-result.md` (mode, command
  run, health result, environment) — created on demand like `ci-result.md`.

### 10. User Confirmation
- **Human checkpoint:** Final delivery acceptance. Present the change summary
  (files, tests, review verdicts, deploy result) and ask Approve / Request
  Changes via `AskUserQuestion`.
- **Non-interactive exception:** on an explicitly unattended run
  (`interactivity_mode` = unattended), record `delivery auto-accepted
  (non-interactive)` and mark COMPLETE — do not hang.
- **Output:** pipeline-state.md Status: COMPLETE.

## Rollback Rules
- Rollback targets the EARLIEST stage where the failure originated
- Never rollback more than 3 stages at once — escalate instead
- Each rollback increments a counter; > `max-rollbacks` total rollbacks (default 3,
  from `espalier/.espalier-config`) → human takeover

## Review Cycle Limits
Round caps are read from `espalier/.espalier-config` (default 3 each); fall back
to 3 if the file or key is missing.

| Review Type | Max Rounds (config key) | Default | On Exceed |
|-------------|-------------------------|---------|-----------|
| Requirements | `max-req-rounds` | 3 | Human decision |
| Code | `max-code-rounds` | 3 | Human decision |
| Test | `max-test-rounds` | 3 | Human decision |
