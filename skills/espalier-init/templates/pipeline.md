# Development Pipeline

## Lanes above and beside this pipeline

This file defines the FULL pipeline (`/espalier`, 10 stages). Two related
lanes route into it rather than through it:

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
- **Limit:** Max `max-req-rounds` review rounds (default 3, from `espalier/.espalier-config`)
  → escalate to human. Check the cap BEFORE re-spawning: if the counter already
  equals `max-req-rounds`, escalate to the human immediately — no further review
  round runs. Before stopping, set `- Status: ESCALATED` and add a Stage History
  row `| 2 | ESCALATED | {ts} | {reason, round count} |` in pipeline-state.md.
- **Human checkpoint (BLOCKING):** user approves `requirements.md` before ANY
  coding. Stage 3 does not start on a Stage 2 PASS alone — see the espalier
  skill → "Requirements Approval Gate". Auto-approved only on an explicitly
  unattended run (interactivity_mode = unattended — CI / ESPALIER_UNATTENDED /
  ESPALIER_LOOP / ESPALIER_HEADLESS). NEVER keyed off a TTY test: stdin has no
  TTY inside Claude Code even when the user is present (see the espalier skill →
  Requirements Approval Gate).
- **Output:** espalier/changes/{type}/{slug}/review-record.md (append)

### 3. Coding Implementation
- **Trigger:** Requirements approved
- **Load:** Spawn `harness-coder` agent (see espalier/agents/harness-coder.md)
- **Execute:** Sub-agent implements per task decomposition
- **Gate (PROGRAMMATIC):** all sub-tasks done + the ORCHESTRATOR re-runs the
  discovered build and lint commands itself and both exit 0 — the coder's
  self-reported "Build status: pass" is a claim, not the gate. The two runs
  may execute as concurrent background jobs in one bash call (per-pid exit
  codes, per-job output) unless the commands plainly depend on each other —
  concurrency changes the wait, never the gate. A failing
  build/lint re-run goes straight back to the coder WITHOUT spawning the Stage 4
  panel (a panel round on unbuildable code is wasted).
- **Constraint:** One sub-agent invocation per sub-task. Sub-tasks whose
  planned file sets are pairwise DISJOINT (including any shared module both
  would touch — barrel files, route tables, migration indexes count as
  overlap) MAY be dispatched concurrently in one message; any overlap or
  uncertainty → serial. See the espalier skill → "Parallel Sub-Tasks".
- **Context pack (first entry only):** before the first coder spawn, the
  orchestrator assembles `espalier/changes/{type}/{slug}/context-pack.md`
  (see the espalier skill → "Stage 3 Entry: Context Pack") — every Stage 3-6
  spawn is pointed at it so no sub-agent re-derives the touched layers,
  specs, rules, and reference files. Paths and facts only, never
  conclusions; agents verify against current code.
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
     coding-report.md. Re-review rounds run in DELTA SCOPE (fix files + prior
     findings + direct dependents as the required reads; a floor, not a
     ceiling — each agent expands on any suspicion; the security agent runs
     delta mode when its own prior round was clean — see each agent's
     "Re-review Rounds" section). The verdict still covers the whole change:
     every line of the final diff was reviewed fresh in the round it last
     changed, build/lint re-runs whole-tree before every round, and the
     Reviewed-Diff fingerprint blocks unreviewed edits at push.
  2. **Non-PASS verdict (word `FAIL`, or p0/p1 > 0) from EITHER agent →** re-spawn
     `harness-coder` with the combined findings (a Stage 3 action), then **return
     to step 1 and re-review the NEW diff with the whole panel.** Never advance to
     Stage 5 on the coder's fix report alone — a fix is never the last action
     before the gate; a clean panel is. Each non-PASS round increments the counter.
  3. **Both last sentinels PASS/PASS_WITH_FIXES with p0=0 p1=0 on a fresh review
     of the current code →** PASS; record the certificate (below) and exit.
- **Gate (to leave Stage 4):** the MOST RECENT run of BOTH panel agents saw the
  CURRENT code and returned zero P0 — NOT "the earlier P0s were addressed." A coder
  fix always triggers another full panel round.
- **Certificate (write on PASS):** `git add -A` (so new files count), then record in
  pipeline-state.md, overwriting any prior value —
  `Reviewed-Diff: $(git diff <Base-Ref> -- . ':(exclude)espalier/' | git hash-object --stdin)`
  where `<Base-Ref>` is the Stage 3 SHA. The Stage 7 push gate blocks unless this
  fingerprint still matches the code being pushed.
- **Limit:** Max `max-code-rounds` rounds (default 3, from `espalier/.espalier-config`)
  → escalate to human (never silently ship). Check the cap BEFORE re-spawning: if
  the counter already equals `max-code-rounds`, escalate to the human
  immediately — the coder is NOT re-spawned and no further panel round runs.
  Before stopping, set `- Status: ESCALATED` and add a Stage History row
  `| 4 | ESCALATED | {ts} | {reason, round count} |`. Otherwise re-spawn,
  increment the counter, and loop. A security P0/P1 (from `harness-security`)
  shares this counter with correctness findings.
- **Panel verdict collection (procedural — see the espalier skill):** each round,
  after BOTH agents return, confirm BOTH records were written THIS round (baseline
  size/mtime + a `VERDICT:` sentinel whose `round=` matches). A record missing its
  sentinel, or unchanged since baseline, means that agent did NOT complete —
  re-spawn that agent; never treat a missing/stale record as a pass.
  **Gate read (deterministic).** From EACH record:
  `V=$(grep '^VERDICT:' <record> | tail -1)`. Parse the verdict WORD and the counts.
  - `ESCALATION_REQUIRED` (either agent, either lane, any stage) → do NOT advance
    and do NOT re-spawn: snapshot the sentinel, then run the escalation protocol
    (fix lane: the late-escalation prompt; full lane: escalate to the human with
    the agent's Escalation Reason block). An `ESCALATION_REQUIRED` with `p0=0` is
    still an escalation.
  - Verdict word `FAIL`, or `p0=` > 0, or `p1=` > 0 → re-spawn `harness-coder`
    with the combined findings and loop (counter + `max-code-rounds` cap unchanged).
  - Advance ONLY when EVERY record's last sentinel has verdict word `PASS` or
    `PASS_WITH_FIXES` AND `p0=0` AND `p1=0` on the current code.
  The certificate is written only when both last sentinels are
  PASS/PASS_WITH_FIXES with p0=0 p1=0; drift processing runs only on that PASS.
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
- **Trigger:** dispatched SPECULATIVELY with the round-1 Stage 4 panel (a
  3-agent message; `speculative-tests: off` in `espalier/.espalier-config`
  restores the serial post-review dispatch) — and COMPLETED after the final
  panel PASS via the espalier skill's "Stage 4 → Stage 5 handoff" (guarded
  part-file append; contract phase / restore-reconcile as one spawn). On a
  panel FAIL the speculative tests are QUARANTINED under the change dir, so
  every later gate, panel round, and coder re-spawn sees a tree with zero
  speculative artifacts.
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
  a `VERDICT:` sentinel; the orchestrator freshness-checks it.
  **Gate read (deterministic).** From EACH record:
  `V=$(grep '^VERDICT:' <record> | tail -1)`. Parse the verdict WORD and the counts.
  - `ESCALATION_REQUIRED` (either agent, either lane, any stage) → do NOT advance
    and do NOT re-spawn: snapshot the sentinel, then run the escalation protocol
    (fix lane: the late-escalation prompt; full lane: escalate to the human with
    the agent's Escalation Reason block). An `ESCALATION_REQUIRED` with `p0=0` is
    still an escalation.
  - Verdict word `FAIL`, or `p0=` > 0, or `p1=` > 0 → re-spawn `harness-coder`
    with the combined findings and loop (counter + `max-test-rounds` cap unchanged).
  - Advance ONLY when EVERY record's last sentinel has verdict word `PASS` or
    `PASS_WITH_FIXES` AND `p0=0` AND `p1=0` on the current code.
- **Loop:** same fixpoint rule as Stage 4 — a non-PASS verdict sends the tests
  back to Stage 5 (re-spawn coder), then **re-review**; never exit on the fix
  report alone. On a round ≥ 2 the orchestrator hands the reviewer the
  changed-since-last-review set (the test files the Stage 5 re-spawn touched);
  the re-review runs in DELTA SCOPE per the agent's "Re-review Rounds" section
  — a floor, not a ceiling; the whole-change verdict rule is unchanged.
- **Certificate (on PASS):** re-run the Stage 4 fingerprint (it now covers the added
  tests) and overwrite `Reviewed-Diff` in pipeline-state.md — the push gate compares
  against this value.
- **Limit:** Max `max-test-rounds` rounds (default 3, from `espalier/.espalier-config`)
  → escalate. Check the cap BEFORE re-spawning: if the counter already equals
  `max-test-rounds`, escalate to the human immediately — the coder is NOT
  re-spawned and no further review round runs.

### 7. Code Push
- **Trigger:** Tests reviewed
- **Gate (PROGRAMMATIC):**
  - `git status` shows clean working tree (all staged/committed)
  - Branch name matches convention
  - No merge conflicts
- **Human checkpoint:** Confirm push target — SKIPPED when a target was
  pre-authorized at the Requirements Approval Gate (recorded as
  `- Push-Target:` in pipeline-state.md; `ASK` or a missing line → prompt
  here exactly as before). Pre-authorization removes only this redundant
  wait; every programmatic gate above, the pre-push hook, and the
  certificate check still apply in full.
- **Output:** `espalier/changes/{type}/{slug}/pipeline-state.md` gains a `## Commits` table row (Stage 7, SHA, files) — read by `/espalier-fix` reverse lookup.

### 8. CI Verification
- **Gate (PROGRAMMATIC — all must be true):**
  - `ci_status == "success"`
  - `total_tests > 0`
  - `tests_passed == total_tests`
  - `lint_errors == 0`
- **Verify by:** Running CI command or reading CI output
- **Wait protocol (remote CI):** never poll across messages — each poll is a
  full orchestrator round-trip. Prefer the CI provider's BLOCKING watch
  inside a single bash call (`gh run watch <run-id> --exit-status` or the
  provider's equivalent). Bash calls cap at ~10 minutes, so for longer CI
  chunk the wait: one `until`-loop per call with a generous internal
  interval and a ~9-minute per-call budget, repeated — turns become
  ceil(CI / 9min), not CI / poll-interval. The Stage 8.5 doc-drift bash may
  ride the SAME message as the first watch call (it reads only
  `.drift-state.tsv`, writes only the change's `doc-patches.md` — CI-
  independent and notify-only). The gate still reads the same final values.
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
  - **Deploy configured:** confirm deploy parameters (human checkpoint) —
    SKIPPED when a target was pre-authorized at the Requirements Approval
    Gate (recorded as `- Deploy-Target:` in pipeline-state.md; `ASK` or a
    missing line → prompt here exactly as before). Then run the
    discovered deploy command (or confirm the automatic deploy completed), then
    run the discovered **health check** against the target environment.
    **Unattended posture:** pre-authorized target → proceed (deploy + health
    check); `ASK`/missing on an unattended run → record
    `| 9 | SKIPPED | {ts} | deploy needs-human (unattended) |` and continue —
    an unauthorized target is NEVER auto-deployed.
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

## Multi-Developer Maintenance

Maintenance follows per-mechanism lanes (full table in `/espalier-prune` →
Multi-Developer Discipline): doctor scans and routine prune refreshes ride
ONE weekly maintenance PR on the canonical branch (`canonical-branch` in
`espalier/.espalier-config`); a prune for your OWN critical/expired flag and
convention promotions may ride a feature branch as their own isolated `docs:`
commits. Two recipes for the residual conflicts:

### Maintenance-commit conflicts (prune vs prune)

1. Inspect both sides — diff the conflicting doc against each merge parent.
2. Take the newer refresh wholesale: `git checkout --theirs -- <doc>` (or
   `--ours` when yours is newer), commit the merge.
3. Re-run `/espalier-prune <doc>` on the merged tree — an empty scout diff
   confirms the kept side; a non-empty one shows what the union of both
   branches' code changed.

A modify/delete conflict on an espalier doc resolves as DELETION (the other
side retired the doc).

### Per-key convention conflicts (`espalier/conventions/k-*.tsv`)

A same-key conflict is the promotion race DETECTION, not a breakage. Two
decisions (both sides flipped statuses) → pick the winning decision like any
5-line conflict. An observation append against another append or against a
status flip → **keep both lines** — every decided row AND every fresh
observation row survive; `conv_fold` dedupes repeated observations at read time,
so nothing double-counts. The shared `espalier/.doctor-stamp` is one line:
keep the newer line (or either `clean`).

### Slug collisions across branches

Two branches can mint the same `espalier/changes/{type}/{slug}/` folder on
the same day; the merge shows add/add conflicts inside it. All in ONE commit:

1. Rename the later-merging change's dir to the next free suffix:
   `git mv espalier/changes/{type}/{slug} espalier/changes/{type}/{slug}-2`.
2. Rebuild the reverse-lookup cache:
   `bash espalier/hooks/rebuild-commit-index.sh`.
3. Rewrite the old slug in every back-link that points at the renamed change:
   `grep -l "{type}/{slug}" espalier/changes/*/*/pipeline-state.md`, then fix
   each `## Follow-up Fixes` row from `{type}/{slug}` to `{type}/{slug}-2` —
   otherwise those back-links point at the other branch's change.
