# Development Pipeline

## Stages

### 1. Requirements Analysis
- **Trigger:** New requirement received
- **Load:** Read espalier/skills/espalier-requirements/SKILL.md (which invokes espalier-grill)
- **Execute:** Main agent produces the requirements doc; `espalier-grill` interrogates it (adaptive depth) unless `--no-grill` was passed
- **Gate:** Requirements doc exists with acceptance criteria (≥ 2 criteria)
- **Output:** espalier/changes/{slug}/requirements.md

### 2. Requirements Review
- **Trigger:** Requirements doc complete
- **Load:** Read espalier/skills/espalier-review/SKILL.md
- **Execute:** Main agent reviews the requirements doc
- **Gate:** No P0/P1 findings remaining
- **Limit:** Max 3 review rounds → escalate to human
- **Human checkpoint (BLOCKING):** user approves `requirements.md` before ANY
  coding. Stage 3 does not start on a Stage 2 PASS alone — see the espalier
  skill → "Requirements Approval Gate". Auto-approved only on a no-TTY run.
- **Output:** espalier/changes/{slug}/review-record.md (append)

### 3. Coding Implementation
- **Trigger:** Requirements approved
- **Load:** Spawn `harness-coder` agent (see espalier/agents/harness-coder.md)
- **Execute:** Sub-agent implements per task decomposition
- **Gate:** All sub-tasks done + code builds + lint passes
- **Constraint:** One sub-agent invocation per sub-task
- **Output:** Code changes + espalier/changes/{slug}/coding-report.md

### 4. Code Review
- **Trigger:** Implementation complete
- **Load:** Spawn `harness-reviewer` agent (see espalier/agents/harness-reviewer.md)
- **Execute:** Reviewer reads diff, checks against review skill
- **Gate:** No P0 findings remaining
- **Limit:** Max 2 review rounds → escalate to human
- **Rollback:** P0 found → back to Stage 3 (re-spawn coder with review findings)
- **Output:** espalier/changes/{slug}/review-record.md (append)

### 5. Test Writing
- **Trigger:** Code review passed
- **Load:** Spawn `harness-coder` agent with testing skill
- **Execute:** Write tests for changed interfaces
- **Gate:** Tests exist for every changed public interface + tests pass

### 6. Test Review
- **Trigger:** Tests written
- **Load:** Spawn `harness-reviewer` agent
- **Execute:** Review tests for meaningfulness
- **Gate:** Tests are meaningful (not just "passes"), cover edge cases
- **Limit:** Max 2 rounds → escalate

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
- **Output:** espalier/changes/{slug}/ci-result.md

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
- **Human checkpoint:** Confirm deployment parameters
- **Gate:** Health/smoke check passes in target environment

### 10. User Confirmation
- **Human checkpoint:** Final delivery acceptance

## Rollback Rules
- Rollback targets the EARLIEST stage where the failure originated
- Never rollback more than 3 stages at once — escalate instead
- Each rollback increments a counter; >3 total rollbacks → human takeover

## Review Cycle Limits
| Review Type | Max Rounds | On Exceed |
|-------------|-----------|-----------|
| Requirements | 3 | Human decision |
| Code | 2 | Human decision |
| Test | 2 | Human decision |
