# /espalier — Stage 5–6 procedure

> Loaded by the espalier SKILL's Stage Execution Protocol when Stage 5–6
> starts (the contract phase and delta review (folded) or test writing and review (serial)). The router holds pre-flight, resumption, the state file,
> rollback, human checkpoints, and completion; `espalier/pipeline.md` is the
> contract. Verbatim procedure — read once, at stage entry.

### Stage 5/6 (folded): the contract phase

Under `test-mode: folded` the interface/failure-mode tests were written at
Stage 3 and reviewed by the Stage 4 panel; Stages 5/6 exist only for the
security abuse-test contract. Stage numbers are an interface —
`pre-push-gate.sh` parses `Current Stage:` as an integer (≥ 7 to push),
`espalier-stats.sh` buckets by stage number, and maprun parses it too — so
keep `Current Stage:` monotonic 3→4→5→6→7 and never remove a row.

**Contract detection (deterministic, right after the final panel PASS):**
`grep -q '^## Security-Sensitive Fields' espalier/changes/{type}/{slug}/security-record.md`
decides empty vs non-empty.

- **No contract (non-sensitive happy path — ZERO post-panel spawns):** in
  one bash, write both rows —
  `| 5 | SKIPPED | {ts} | folded: no contract |` and
  `| 6 | SKIPPED | {ts} | folded: reviewed at Stage 4 |` — set
  `Current Stage: 7`, and proceed to Stage 7.
- **Non-empty contract (sensitive change):**
  1. Write `| 5 | IN_PROGRESS | {ts} | contract phase |`; extract the
     contract — `contract_extract "espalier/changes/{type}/{slug}"` writes
     `security-contract.md` = the `## Security-Sensitive Fields` block to
     the next heading (the auditor's round-N adjudication prose never rides
     into a Stage 5/6 spawn again); archive the current report
     (`report_archive … "round{n}-fix"`, or `"stage3"` when no fix round
     ran); then ONE
     test-coder spawn, alone in its message: "CONTRACT PHASE: read
     espalier/changes/{type}/{slug}/security-contract.md (fallback: the
     `## Security-Sensitive Fields` block of security-record.md) — for EVERY
     field listed, write the negative abuse
     test it names (tamper the value → assert rejected → assert store
     unchanged). Write your coding report fresh to coding-report.md — the
     earlier report is in coding-log/."
  2. Re-run the Stage 3 exit gate (`exit_gate`, `stages/3-coding.md` —
     build + lint + scoped test run; the contract tests must build and PASS
     before anyone reviews them).
  3. **Contract delta review (Stage 6):** ONE `harness-reviewer` spawn,
     alone in its message, its prompt's first line `CONTRACT DELTA REVIEW:
     read espalier/agents/modes/stage6-abuse-coverage.md first`, delta
     scope = the contract test files +
     security-contract.md (fallback: the block in security-record.md). Its
     job is the abuse-coverage check: every
     contracted field has a passing test (tamper → rejected → store
     unchanged) — a missing or happy-path-only one is a P0. Freshness-check
     review-record.md as at Stage 4. The gate read is SINGLE-record (one
     reviewer, one sentinel): `V=$(grep '^VERDICT:' <record> | tail -1)` —
     advance only on PASS/PASS_WITH_FIXES with p0=0 p1=0.
  4. **Contract-phase FAIL routing:**
     - fix touches ONLY test files → contract loop: archive the report
       (`report_archive … "contract-phase"`), re-spawn the coder in
       CONTRACT PHASE mode with the findings, re-run the exit gate, delta
       review again — under `max-test-rounds` (read
       `grep '^max-test-rounds:' espalier/.espalier-config | grep -oE '[0-9]+'`,
       default 3; cap-before-respawn — at the cap, escalate:
       `| 6 | ESCALATED | {ts} | {reason, round count} |`).
     - fix must touch ANY non-test file (an abuse test failed because the
       CODE is vulnerable) → that is a security-relevant code change: route
       back to a FULL Stage 4 panel round under `max-code-rounds`
       (cap-before-respawn applies — code counter already at its cap →
       escalate immediately; no second counter, no reset). After the panel
       passes again, re-run contract detection and this phase.
  5. **On delta-review PASS:** refresh the certificate (same command as
     below — it now covers the contract tests) and write
     `| 6 | PASSED | {ts} | contract delta review |`.

**Certificate (write at the final panel PASS; refresh at delta-review
PASS):** `git add -A` (so new files count), then record in
pipeline-state.md, overwriting any prior value —
`Reviewed-Diff: $(git diff <Base-Ref> -- . ':(exclude)espalier/' | git hash-object --stdin)`
where `<Base-Ref>` is the SHA recorded at Stage 3 entry (never overwritten
on a re-spawn). The Stage 7 push gate blocks unless this fingerprint still
matches the pushed code.

**Crash recovery (folded — no part-files, no quarantine):** tests are
ordinary tracked files listed in coding-report.md. A resume into Stage 4
re-runs the exit gate then the panel. A resume into Stage 5/6 where the
certificate no longer matches the tree means the contract spawn wrote
tests before the crash — re-run contract detection, re-run the exit gate,
re-spawn the delta review, refresh the certificate.

**`test-mode: serial` (the conservative fallback):** Stage 3 carries no
TESTS duty; after the final panel PASS, one test-coder spawn writes the
interface tests, failure-mode tests, AND the contracted abuse tests
(reading security-contract.md, fallback security-record.md), writing its
report fresh to coding-report.md (the orchestrator archives the Stage 3
report first — `report_archive … "stage3"` / `"round{n}-fix"`); then
Stage 6 below reviews them as its own fixpoint loop. Stage 5/6 rows record
normally — no SKIPPED rows in serial mode. This is the pre-v0.22 flow.

**Stage 6 (serial mode only — Test Review):**
```
Agent tool:
  prompt: |
    You are the harness-reviewer reviewing tests.
    Your instructions are espalier/agents/harness-reviewer.md (auto-loaded as
    your system prompt on Claude Code; read it only if it is not already in
    your context). Read espalier/agents/modes/stage6-abuse-coverage.md
    first — the abuse-coverage check below is its procedure.

    CONTEXT PACK: espalier/changes/{type}/{slug}/context-pack.md — read it
    first (paths and facts only — your verdict comes from the tests you read).
    WHAT TO REVIEW: The test files created in Stage 5.
    Read espalier/changes/{type}/{slug}/coding-report.md for the list.
    ROUND: {n} — put round={n} in your VERDICT sentinel line.
    {On round ≥ 2 add:} CHANGED SINCE LAST REVIEW: {the test files the
    Stage 5 fix re-spawn touched, from the latest coding-report.md}.
    Read espalier/agents/modes/re-review.md first and re-review in delta
    scope.

    Check: Are tests meaningful? Do they cover edge cases?
    Do they match project testing patterns in espalier/skills/espalier-testing/SKILL.md?
    Security coverage: does EVERY field in espalier/changes/{type}/{slug}/security-contract.md
    (fallback: security-record.md's `## Security-Sensitive Fields` block) have a passing abuse test
    (tamper → rejected → store unchanged)? A missing one is a P0 → back to Stage 5.
    Failure-mode coverage: does every NEW external-call path have a
    dependency-failure test (per espalier/rules/production-standards.md)?
    A missing one is a P1.

    Write (OVERWRITE) your review to: espalier/changes/{type}/{slug}/review-record.md
    End the file with your VERDICT sentinel line.
```

Serial Stage 6 uses the same record semantics as Stage 4: freshness-check
review-record.md against its baseline, snapshot each round's sentinel into
Stage History. (Stage 4's final record is overwritten here — its verdicts live
in Stage History and the certificate.)

**Gate read (deterministic — SINGLE record: one reviewer runs here).** From
review-record.md:
`V=$(grep '^VERDICT:' <record> | tail -1)`. Parse the verdict WORD and the counts.
- `ESCALATION_REQUIRED` → do NOT advance
  and do NOT re-spawn: snapshot the sentinel, then run the escalation protocol
  (fix lane: the late-escalation prompt; full lane: escalate to the human with
  the agent's Escalation Reason block). An `ESCALATION_REQUIRED` with `p0=0` is
  still an escalation.
- Verdict word `FAIL`, or `p0=` > 0, or `p1=` > 0 → re-spawn `harness-coder`
  with the combined findings and loop (counter + `max-test-rounds` cap
  unchanged).
- Advance ONLY when the record's last sentinel has verdict word `PASS` or
  `PASS_WITH_FIXES` AND `p0=0` AND `p1=0` on the current code.

Stage 6's loop cap is `max-test-rounds`. Check the cap BEFORE re-spawning: if
the counter already equals `max-test-rounds`, escalate to the human
immediately — the coder is NOT re-spawned and no further panel round runs.
Before stopping, set `- Status: ESCALATED` and add a Stage History row
`| 6 | ESCALATED | {ts} | {reason, round count} |` in pipeline-state.md.
Otherwise re-spawn, increment the counter, and loop. After snapshotting a
ROUND row, also update the `Review Rounds:` numerators in pipeline-state.md —
a resumed session recounts rounds from this line plus the ROUND rows, never
from memory. On the serial Stage 6 PASS (row + certificate refreshed) make
the same stage-boundary offer as Stage 4's step 5, resuming at Stage 7.
