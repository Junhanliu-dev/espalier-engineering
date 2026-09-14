# Development Pipeline

## Lanes above and beside this pipeline

This file defines the FULL pipeline (`/espalier`, 10 stages). Related lanes
route into it rather than through it:

- `/espalier-fix` — the slim bug lane (7 stages, no Stage 2).
- `/espalier-map` — multi-session planning for efforts too big for one
  session (epics, greenfield). It plans only — a cleared map hands off
  `Status: FILED` change skeletons under `espalier/changes/feat/`, each with
  `charted_from:` frontmatter, and THIS pipeline adopts and runs them one at
  a time from Stage 1. See `espalier/skills/espalier-map/SKILL.md`.
- `/espalier-maprun` — the batch executor for a CLEARED map: an interactive
  master dispatches headless `/espalier` workers (stages 1–6, isolated
  worktrees, push-blocked) over hours/days, merges what passes into an
  integration branch, and relays worker questions to the human. Stages 7–10
  remain a deliberate human act on the assembled branch. See
  `espalier/skills/espalier-maprun/SKILL.md`.
- `/espalier-simplify` — the evidence-first simplification survey of the
  EXISTING code. Read-only: it ranks accidental complexity with a proof
  record per candidate into `espalier/wiki/simplify-survey.md` and files
  proven cuts as `Status: FILED` skeletons under `espalier/changes/refactor/`
  (`simplify_from:` frontmatter) that THIS pipeline adopts and runs — the
  coder retires the whole boundary, the panel re-proves every retired name,
  and Completion flags the docs that described it for `/espalier-prune`. See
  `espalier/skills/espalier-simplify/SKILL.md`.

## Stages

Each stage is a contract: trigger, what to load, the gate (the programmatic
condition that advances it), the output, the limit. The PROCEDURE — prompts,
gate scripts, bookkeeping — lives in the espalier skill's stage files and is
read at stage entry (`espalier/skills/espalier/SKILL.md` → Stage Execution
Protocol). The eleven headings below are frozen: `pre-push-gate.sh`,
`espalier-stats.sh`, and `maprun.py` parse stage numbers.

### 1. Requirements Analysis
- **Trigger:** New requirement received
- **Load:** espalier/skills/espalier-requirements/SKILL.md (invokes espalier-grill unless `--no-grill`)
- **Gate:** requirements.md exists with ≥ 2 acceptance criteria; the grill's verdict recorded (`GRILLED (light|full)` / `SKIPPED: <reason>`)
- **Output:** espalier/changes/{type}/{slug}/requirements.md (the contract) + requirements-notes.md (derivation, alternatives, the grill's Q&A)
- **Procedure:** espalier skill → stages/1-2-requirements.md

### 2. Requirements Review
- **Trigger:** Requirements doc complete
- **Load:** espalier/skills/espalier-review/SKILL.md (main agent reviews)
- **Gate:** no P0/P1 findings; a heading outside the requirements contract set is a P2 with Fix = "move to requirements-notes.md"
- **Limit:** `max-req-rounds` (default 3, `espalier/.espalier-config`) — at the cap escalate: `- Status: ESCALATED`, `| 2 | ESCALATED | {ts} | {reason, round count} |`
- **Human checkpoint (BLOCKING):** the user approves `requirements.md` before ANY coding — a Stage 2 PASS alone never starts Stage 3. Auto-approved only when `interactivity_mode` = unattended (CI / ESPALIER_UNATTENDED / ESPALIER_LOOP / ESPALIER_HEADLESS), never off a TTY test. The gate also collects `- Push-Target:` (Stage 7), `- Session-Boundary:` (the fresh-session preference for the Stage 2 and Stage 4 boundaries, read there — never asked again), and, when deploy is configured, `- Deploy-Target:` (Stage 9).
- **Output:** espalier/changes/{type}/{slug}/review-record.md (append); `| 2 | PASSED | {ts} | Requirements approved by user |`
- **Procedure:** espalier skill → stages/1-2-requirements.md

### 3. Coding Implementation
- **Trigger:** Requirements approved
- **Load:** the context pack (`context-pack.md` — paths and facts only, written in the approval-gate turn), then spawn `harness-coder` (espalier/agents/harness-coder.md); under `test-mode: folded` (default) the coder also writes the change's interface and failure-mode tests and the abuse test for every sensitive field it classifies, and verifies each cycle with the gate's own `exit_gate` call
- **Gate (PROGRAMMATIC, every coder return):** `- HANDOFF: true` on the report → archive it to `coding-log/` and continue with a fresh coder (the panel never sees a handoff report); then `exit_gate` — the discovered build and lint exit 0 and, folded, the discovered tests scoped to the report's listed test files pass (exit 1 = red → back to the coder without a panel round; exit 2 / 3 = run the gate by hand). The coder's self-reported "Build status: pass" is a claim, not the gate.
- **Constraint:** one spawn per sub-task; sub-tasks with pairwise-disjoint planned file sets may run concurrently, any overlap → serial; `report_archive` before every coder spawn after the first (`coding-report.md` is the CURRENT spawn's report)
- **Commits:** the coder commits each bounded unit at a clean point (one seam per commit, message per `espalier/rules/development-process.md` → Commit Conventions, staged by path — harness-coder.md → Commit Discipline); under PARALLEL DISPATCH no coder runs git — the orchestrator commits each part's files as one commit after the wave
- **Baseline (first entry only):** `Base-Ref: $(git rev-parse HEAD)` in pipeline-state.md — never overwritten on a re-spawn
- **Output:** code as atomic commits since `Base-Ref` + espalier/changes/{type}/{slug}/coding-report.md (`- Commits:`; + coding-log/)
- **Procedure:** espalier skill → stages/3-coding.md

### 4. Code Review (fixpoint loop — a two-agent review panel, re-review after EVERY fix)
- **Trigger:** Stage 3 gate green
- **Load:** every round TWO fresh agents on the CURRENT diff, concurrently — `harness-reviewer` (→ review-record.md) and `harness-security` (→ security-record.md); folded: the reviewer's verdict covers code AND tests; round ≥ 2 runs in DELTA SCOPE (`CHANGED SINCE LAST REVIEW`, modes/re-review.md — a floor, not a ceiling)
- **Gate (to leave Stage 4):** the MOST RECENT run of BOTH agents saw the CURRENT code and its last `VERDICT:` sentinel is `PASS` or `PASS_WITH_FIXES` with `p0=0 p1=0` — never "the earlier P0s were addressed". `V=$(grep '^VERDICT:' <record> | tail -1)`, both records written THIS round (baseline + `round={n}`); `ESCALATION_REQUIRED` runs the escalation protocol, never advances
- **Loop:** a non-PASS verdict from EITHER agent → `report_archive`, re-spawn `harness-coder` under `FIX ROUND {n}:` (modes/fix-round.md — the defect CLASS, `### Class Sweep`), then a FULL panel round on the new diff — a fix is never the last action before the gate; the round's two sentinels + one bracketed finding per failing agent are snapshotted into Stage History (`| 4 | ROUND {n} FAIL | … |`) — the findings digest's only source
- **Limit:** `max-code-rounds` (default 3), checked BEFORE re-spawning; security P0/P1 share the counter — at the cap `- Status: ESCALATED`, `| 4 | ESCALATED | {ts} | … |`
- **Certificate (on PASS):** `certificate_write` — `git add -A`, then `Reviewed-Diff: $(git diff <Base-Ref> -- . ':(exclude)espalier/' | git hash-object --stdin)` in pipeline-state.md — the push gate blocks unless it still matches
- **Security contract (on PASS):** `## Security-Sensitive Fields` in security-record.md → `contract_extract` → security-contract.md, the Stage 5/6 input; drift processing (`drift_index`) and the boundary read (`- Session-Boundary:`) run on that PASS
- **Output:** review-record.md + security-record.md, BOTH overwritten each round; `| 4 | PASSED | … |`
- **Procedure:** espalier skill → stages/4-panel.md

### 5. Contract Phase (folded) / Test Writing (serial)
- **Trigger:** Stage 4 PASS
- **Load (folded, `test-mode: folded` — absent key honors legacy `speculative-tests: off` → serial):** `grep -q '^## Security-Sensitive Fields'` on security-record.md — no contract → `| 5 | SKIPPED | {ts} | folded: no contract |` and advance; non-empty → `contract_gaps`: every entry `covered_by:` a test in the diff → `| 5 | PASSED | {ts} | folded: contract covered at Stage 3 |`, no spawn; gaps → ONE `harness-coder` CONTRACT PHASE spawn reads security-contract.md and writes the abuse tests for the gap entries only
- **Gate (folded):** the Stage 3 exit gate re-run green on the contract tests (`exit_gate`) — on the gap path; the covered path's tests passed the Stage 3 gate and the panel already
- **Serial (`test-mode: serial`):** one spawn writes interface + failure-mode + contracted abuse tests; gate: tests exist for every changed public interface, pass, and every contracted field has its abuse test
- **Output:** the test files listed in coding-report.md (written fresh; the prior report in coding-log/)
- **Procedure:** espalier skill → stages/5-6-contract.md

### 6. Contract Delta Review (folded) / Test Review (serial)
- **Trigger:** Stage 5 done (or SKIPPED)
- **Load (folded, no contract):** `| 6 | SKIPPED | {ts} | folded: reviewed at Stage 4 |` — `Current Stage:` stays monotonic 3→4→5→6→7 (the push gate's integer parse, stats, and maprun depend on the rows)
- **Load (folded, contract):** ONE `harness-reviewer` in delta scope (the contract test files + security-contract.md; modes/stage6-abuse-coverage.md)
- **Gate:** single-record read — last `VERDICT:` is PASS/PASS_WITH_FIXES with `p0=0 p1=0`; every contracted field has a passing tamper → rejected → store-unchanged test (a missing one is a P0)
- **FAIL routing:** test-only fix → contract loop under `max-test-rounds` (default 3, cap checked BEFORE re-spawning); a fix touching any NON-test file → a FULL Stage 4 panel round under `max-code-rounds` (no second counter), then Stage 5 again
- **Serial:** `harness-reviewer` on the Stage 5 tests — Stage 4's fixpoint rule with a single-record gate read; round ≥ 2 in delta scope; limit `max-test-rounds`, at the cap escalate
- **Certificate (on PASS, both modes):** refresh `Reviewed-Diff` (`certificate_write` — it now covers the tests); serial mode reads `- Session-Boundary:` here
- **Output:** review-record.md (overwritten); `| 6 | PASSED | {ts} | contract delta review |`
- **Procedure:** espalier skill → stages/5-6-contract.md

### 7. Code Push
- **Trigger:** Stage 6 done
- **Gate (PROGRAMMATIC):** clean working tree (all staged/committed); branch name matches convention; no merge conflicts; the pre-push hook (`espalier/hooks/pre-push-gate.sh`) passes — `Current Stage:` ≥ 7 and `Reviewed-Diff` matches
- **Human checkpoint:** confirm the push target — SKIPPED when `- Push-Target:` was pre-authorized at the approval gate (`ASK` or missing → prompt here)
- **Commits:** the coder's commits are pushed as made — the pipeline never squashes or rebases them (squash-merge is the pull request's policy; the post-merge hook maps it back); code left uncommitted is committed by path under the report's message, the change's records as one `chore(espalier):` commit
- **Output:** `## Commits` rows — one per commit in `Base-Ref..HEAD` (Stage 7, SHA, files) in pipeline-state.md (`record_commits`) — read by `/espalier-fix` reverse lookup; the convention index staged; the PARTIAL_FIX reverse-link when applicable
- **Procedure:** espalier skill → stages/7-10-delivery.md

### 8. CI Verification
- **Trigger:** pushed
- **Gate (PROGRAMMATIC — all true):** `ci_status == "success"`, `total_tests > 0`, `tests_passed == total_tests`, `lint_errors == 0` — verified by running the CI command or reading CI output
- **Wait protocol (remote CI):** never poll across messages — one BLOCKING watch per bash call (`gh run watch <run-id> --exit-status` or the provider's equivalent), chunked at ~9 minutes per call; the Stage 8.5 bash may ride the first watch call
- **Rollback:** `total_tests == 0` → Stage 3 (folded — tests are a Stage 3 duty; serial → Stage 5); build or lint failure → Stage 3
- **Output:** espalier/changes/{type}/{slug}/ci-result.md
- **Procedure:** espalier skill → stages/7-10-delivery.md

### 8.5 Doc Drift Check (notify-only)
- **Trigger:** Stage 8 passed
- **Gate:** none — `stage85_drift` reads `espalier/.drift-state.tsv`, appends a notify table to the change's `doc-patches.md`, surfaces one line; edits no rule/wiki/spec, prompts nothing, never blocks
- **Note:** "8.5" is a label, NOT a numeric stage — `Current Stage:` never holds `8.5` (the push gate's integer parse); recorded in Stage History notes only
- **Output:** espalier/changes/{type}/{slug}/doc-patches.md (on demand)
- **Procedure:** espalier skill → stages/7-10-delivery.md

### 9. Deployment Verification
- **Trigger:** CI passed
- **Load:** the `## Deploy & Verification` section of `espalier/rules/development-process.md`
- **Modes:** no deploy configured → `| 9 | SKIPPED | {ts} | no-deploy-config |` and advance (a clean pass); configured → confirm the target (SKIPPED when `- Deploy-Target:` was pre-authorized; `ASK` or missing → prompt), run the discovered deploy command (or confirm the automatic deploy), then the discovered health check. Unattended: pre-authorized → proceed; `ASK`/missing → `| 9 | SKIPPED | {ts} | deploy needs-human (unattended) |` — an unauthorized target is NEVER auto-deployed
- **Gate (PROGRAMMATIC when configured):** health check succeeds (HTTP 2xx on the health path, or the health command exits 0)
- **Rollback:** health check fails → do NOT proceed; surface it, follow the project's rollback/redeploy procedure, record it
- **Output:** espalier/changes/{type}/{slug}/deploy-result.md (on demand)
- **Procedure:** espalier skill → stages/7-10-delivery.md

### 10. User Confirmation
- **Human checkpoint:** final delivery acceptance — present files, tests, review verdicts, deploy result; Approve / Request Changes via `AskUserQuestion`. Push and deploy pre-authorization NEVER extend here
- **Non-interactive exception:** unattended → record `delivery auto-accepted (non-interactive)` and mark COMPLETE — do not hang
- **Output:** pipeline-state.md `- Status: COMPLETE`; the bookkeeping commit (`chore(espalier): close {slug}`)
- **Procedure:** espalier skill → Completion

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

Under `test-mode: folded`, code+test findings share the `max-code-rounds`
loop (they are one diff); `max-test-rounds` counts contract delta-review
rounds only, and a code-touching contract fix consumes `max-code-rounds`.

## Multi-Developer Maintenance

Maintenance follows per-mechanism lanes — the full table and the three
conflict recipes (maintenance-commit conflicts, per-key convention conflicts,
slug collisions across branches) live in `/espalier-prune` →
Multi-Developer Discipline, which owns the maintenance discipline.
