# /espalier — Stage 4 procedure

> Loaded by the espalier SKILL's Stage Execution Protocol when Stage 4
> starts (code review — the two-agent panel, every round). The router holds pre-flight, resumption, the state file,
> rollback, human checkpoints, and completion; `espalier/pipeline.md` is the
> contract. Verbatim procedure — read once, at stage entry.

### Stage 4: The Review Panel

**Stage 4 (Review):**
```
Agent tool:
  prompt: |
    You are the harness-reviewer.
    Your instructions are espalier/agents/harness-reviewer.md (auto-loaded as
    your system prompt on Claude Code; read it only if it is not already in
    your context).

    CONTEXT PACK: espalier/changes/{type}/{slug}/context-pack.md — read it
    first (paths and facts only — your verdict comes from the code you read).
    WHAT TO REVIEW: Read espalier/changes/{type}/{slug}/coding-report.md to see
    what the coder did. Then read the actual files listed there — the code
    AND its "Test files" subsection. Earlier spawns' reports are in
    espalier/changes/{type}/{slug}/coding-log/ — open one only when the
    current report cites it or a finding needs the history.
    COMMITS: {git log --oneline <Base-Ref>..HEAD} — the coder's commits;
    a commit that bundles unrelated seams or a message off the project's
    Commit Conventions is an advisory `commits:` row (P3), never a FAIL. One verdict covers both: run your
    test-review checklist on the tests (assertions meaningful, not
    tautological; changed-interface coverage; failure-mode coverage per
    espalier/rules/production-standards.md — a missing one is a P1) with
    the code in view. Do NOT check abuse-test coverage this round — the
    security contract is being written concurrently; that check runs at
    the contract delta review.
    DEVIATIONS: run your Deviation Review — the coding report's
    "### Deviations" block (absent = nothing logged) against the diff, and
    the diff against requirements.md's acceptance criteria; an unlogged or
    non-conservative departure is a [deviation] P1.
    ROUND: {n} — put round={n} in your VERDICT sentinel line.
    {On round ≥ 2 add:} CHANGED SINCE LAST REVIEW: {fix's files from the
    latest coding-report.md}. Read espalier/agents/modes/re-review.md
    first (its harness-reviewer section) and re-review in delta scope.
    {On a change whose requirements.md carries simplify_from: add:}
    SIMPLIFICATION CHANGE: read espalier/agents/modes/simplification.md
    first (its harness-reviewer section), then requirements.md
    "## Retired Surface" — your own re-search of every retired name BEFORE
    reading the coder's residue search.

    Write (OVERWRITE) your review to:
    espalier/changes/{type}/{slug}/review-record.md
    End the file with your VERDICT sentinel line.
```

**Stage 4 (Security Audit — runs as a panel with the review above):**
```
Agent tool:
  prompt: |
    You are the harness-security auditor.
    Your instructions are espalier/agents/harness-security.md (auto-loaded as
    your system prompt on Claude Code; read it only if it is not already in
    your context).

    CONTEXT PACK: espalier/changes/{type}/{slug}/context-pack.md — read it
    first (paths and facts only — your verdict comes from the code you read).
    WHAT TO AUDIT: Read espalier/changes/{type}/{slug}/coding-report.md to see
    what changed, then trace the touched endpoints. Assume the client is hostile.
    Earlier spawns' reports are in espalier/changes/{type}/{slug}/coding-log/
    — open one only when the current report cites it or a finding needs
    the history.
    Test files in the diff are in scope for secrets / live-endpoint /
    fixture-data leakage only — otherwise they are not findings surface.
    DEVIATIONS: a "### Deviations" entry in the coding report that drops,
    relaxes, or bypasses a control on a sensitive field is a P0 (your
    Audit Process step 5).
    ROUND: {n} — put round={n} in your VERDICT sentinel line.
    {On round ≥ 2 add:} CHANGED SINCE LAST REVIEW: {fix's files from the
    latest coding-report.md}. Read espalier/agents/modes/re-review.md
    first (its harness-security section); if your own prior round was
    clean, run its delta mode.

    Write (OVERWRITE) your audit to:
    espalier/changes/{type}/{slug}/security-record.md
    End the file with your VERDICT sentinel line.
```

Stage 4 is a **review panel**: `harness-reviewer` (correctness / conventions /
production readiness, → review-record.md) and `harness-security` (trust boundary,
→ security-record.md) both run on the CURRENT diff. BOTH records are OVERWRITTEN
each round and end with a machine-greppable `VERDICT:` sentinel. Run this
procedure every round — it IS the gate, not a description. Do not advance to
Stage 5 by any other path:

1. **Baseline.** Note whether EACH of `review-record.md` and `security-record.md`
   exists, and its size/mtime. Spawn BOTH agents in ONE message (concurrent) —
   the panel is TWO agents, every round: under `test-mode: folded` the diff
   they review already contains the tests; under `serial` the tests come
   after the panel. Either way, no third seat.
   On a re-review round, include the `CHANGED SINCE LAST REVIEW:` line in both
   prompts — the agents then review in delta scope (their "Re-review Rounds"
   sections; required reads = fix files + prior findings + direct dependents,
   expandable on any suspicion; security runs delta mode when its own prior
   round was clean). Both agents still return fresh current-round sentinels
   and still own the whole-change verdict.
2. **Completion check — BOTH files.** After both return, confirm EACH record was
   written THIS round: it exists, differs from its baseline, and its last
   `VERDICT:` line carries `round={n}` for the current round. A record that is
   missing, unchanged, or lacks a current-round sentinel means THAT agent did not
   complete — re-spawn that agent (once; a second failure → escalate to human).
   Never treat a missing or stale record as a pass.
3. **Gate read (deterministic).** From EACH record:
   `V=$(grep '^VERDICT:' <record> | tail -1)`. Parse the verdict WORD and the counts.
   - `ESCALATION_REQUIRED` (either agent, either lane, any stage) → do NOT
     advance and do NOT re-spawn: snapshot the sentinel, then run the escalation
     protocol (fix lane: the late-escalation prompt; full lane: escalate to the
     human with the agent's Escalation Reason block). An `ESCALATION_REQUIRED`
     with `p0=0` is still an escalation.
   - Verdict word `FAIL`, or `p0=` > 0, or `p1=` > 0 → re-spawn `harness-coder`
     with the combined findings and loop (counter + `max-code-rounds` cap
     unchanged).
   - Advance ONLY when EVERY record's last sentinel has verdict word `PASS` or
     `PASS_WITH_FIXES` AND `p0=0` AND `p1=0` on the current code.
4. **On a non-PASS round (verdict `FAIL`, or p0/p1 > 0) →** snapshot both
   sentinel lines into pipeline-state.md Stage History, appending in the
   same notes cell one bracketed finding line per FAILING agent — its top
   finding as `[{P-sev} {≤80-char summary}]`:
   (`| 4 | ROUND {n} FAIL | {ts} | reviewer: FAIL p0=2 p1=0 [P0 access.filter.update missing on update]; security: PASS p0=0 p1=0 |`).
   One bracket per failing agent, ≤80 chars each — this snapshot is the
   findings digest's only source: both records are overwritten next round,
   so finding text survives nowhere else.
   Check the cap BEFORE re-spawning: if the counter already equals
   `max-code-rounds` (default 3, read from `espalier/.espalier-config` via
   `grep '^max-code-rounds:' espalier/.espalier-config | grep -oE '[0-9]+'`; fall
   back to 3 if the file or key is unset), escalate to the human immediately —
   the coder is NOT re-spawned and no further panel round runs. Before stopping,
   set `- Status: ESCALATED` and add a Stage History row
   `| 4 | ESCALATED | {ts} | {reason, round count} |` in pipeline-state.md.
   Otherwise archive the current report first —
   `report_archive "espalier/changes/{type}/{slug}" "stage3"` before the
   first fix round, `"round{n-1}-fix"` after — then re-spawn `harness-coder`
   with the combined findings (a Stage 3
   action — its build/lint/test exit gate applies; code and test findings
   share this ONE loop, tests looping as ordinary files in the diff), increment the shared
   round counter, and return to step 1. The re-spawn prompt's first line is
   `FIX ROUND {n}: read espalier/agents/modes/fix-round.md first, then for
   every P0/P1 below run the Class Sweep — fix every sibling of the defect
   class, not the flagged line; one `### Class Sweep` block per finding in
   coding-report.md; commit each class as its own commit
   (`fix({scope}): {class} (review round {n})`) — never amend a commit this
   panel has seen.` — the panel verifies the sweep next round. After snapshotting a ROUND row, also
   update the `Review Rounds:` numerators in pipeline-state.md — a resumed
   session recounts rounds from this line plus the ROUND rows, never from
   memory.
   **Simplification changes (`simplify_from:` in requirements.md) — a
   `[simplify-consumer]` or `[simplify-protected]` P0 is never fixed
   around.** Re-spawn the coder ONCE with the finding; its only legitimate
   outcomes are (a) the consumer is itself provably dead — it widens
   `## Retired Surface` in requirements.md under the same proof discipline
   and the panel re-verifies next round, or (b) it restores the boundary
   fully (the cut reverted, nothing half-removed) and reports
   `- Missed consumer:` ≠ `none`. On (b) do not loop: set
   `- Status: ABORTED`, add
   `| 4 | ABORTED | {ts} | simplify: missed consumer {file:line} |`,
   rewrite that candidate's row in
   `espalier/wiki/simplify-survey.md` (the `#{n}` in `simplify_from:`)
   from `refactor/{slug}` to `LEAD — missed consumer: {file:line}` so the
   next survey starts from the fact, commit both
   (`chore(espalier): abort {slug} — missed consumer`), and tell the
   user. A cut is proved or withdrawn — never patched into a partial
   delete.
5. **Only when both last sentinels are PASS/PASS_WITH_FIXES with p0=0 p1=0 on
   the current code →** snapshot the two sentinel lines into Stage History
   (`| 4 | PASSED | … |`), write the `Reviewed-Diff` certificate
   (`certificate_write`, `stages/5-6-contract.md`), **surface the
   deviations** — `. espalier/hooks/drift-helpers.sh && deviations_list
   "espalier/changes/{type}/{slug}"` prints the coding report's
   `### Deviations` entries (nothing when there are none): print them under
   the PASS line, verbatim, and append `deviations: {n}` to the PASSED
   row's notes (the delivery brief carries them too) — THEN run the "Stage
   4 Post-Review" drift processing below — it must finish BEFORE any
   contract delta-review spawn (that spawn overwrites the review-record.md
   the parse reads) — then the **stage boundary**: with the PASSED row, the
   certificate, and the drift rows on disk, read `- Session-Boundary:` from
   pipeline-state.md (collected at the Requirements Approval Gate; no
   question here). `after-4` or `both` → write `- Current Stage: 5`, print
   `run /clear, then /espalier with no argument: Session Resumption picks
   this change up at Stage 5 from pipeline-state.md`, and stop. Any other
   value, a missing line, or an unattended run → continue. Then the
   Stage 5/6 contract flow. The exit gate requires BOTH
   clean — never one agent's pass alone. A security P0/P1 shares the correctness
   `max-code-rounds` round counter.

### Stage 4 Post-Review: Drift & Convention Index

After Stage 4 PASSES (step 5 above — BOTH panel agents returned zero P0 and the
certificate is written), parse `review-record.md` for Convention Drift blocks (see
`harness-reviewer.md`) and flag the affected rule files. Do NOT run this on a P0
round: a malformed-drift P0 written back mid-loop would contaminate the next
round's P0 count.

> Variables in scope: `TYPE` and `SLUG` are the active change's type/slug.

```bash
. espalier/hooks/drift-helpers.sh && drift_index "$TYPE" "$SLUG"
```

`drift_index` runs `parse-drift-blocks.py` over the record: each `DRIFT`
block marks its rule file stale (`mark_stale`, reason `convention drift
flagged in {type}/{slug} review`) and appends
`convention_drift: {rule file}` (+ `(coupled_with: …)`) to
pipeline-state.md; a `MALFORMED` block appends
`convention_drift_malformed: {rule file} (reviewer bundled blocks — drift NOT
indexed)` instead. It prints the lines it appended; no record or no python3
is a no-op.

A `MALFORMED` line means the reviewer bundled unrelated drifts into one block.
Stage 4 has already PASSED when this parse runs, so there is no later round to
fix it in this change — do NOT write a fake P0 into review-record.md (it would
contaminate the Stage 6 gate read). Instead the malformed block is recorded in
pipeline-state.md and surfaced to the user in ONE line ("a Convention Drift
block was malformed and not indexed — the underlying drift will resurface via
the post-merge detector or the next review that sees it"). `coupled_with`
blocks resurface together at the next Stage 0 pre-flight (promote-together /
reject-together / split).

**Convention Observations → the convention index.** The reviewer also emits
lower-bar Convention Observations (see `harness-reviewer.md`) — one per
divergence, with NO aggregation key. The orchestrator assigns the key: a fresh
isolated reviewer cannot (three reviews of one pattern would coin three keys and
the count would never reach the threshold). For each Observation in
`review-record.md`:

1. Read existing keys: `. espalier/hooks/drift-helpers.sh && conv_fold | cut -f1`
   (folds the legacy file AND the per-key files — never parse them yourself).
2. Map the Observation's `description` to an existing `pattern_key`, or mint a
   new kebab-case key.
3. Append the row:

```bash
. espalier/hooks/drift-helpers.sh
append_convention "${TYPE}/${SLUG}" "$PATTERN_KEY" "$LOCATION"
```

`append_convention` sanitizes every field and de-dupes on
(change_slug, pattern_key, location), so re-running Stage 4 never inflates the
count. Convention state is tracked and row-append-only — columns
`date · change_slug · pattern_key · location · status` (+ optional 6th
`coupled_with`); `status` ∈ `diverges | promoted | rejected | exception`. When a
`pattern_key` reaches 3 deduped `diverges` observations (per `conv_fold`) it is
a promotion candidate, surfaced at the next Stage 0 pre-flight (see Convention
Promotion).
