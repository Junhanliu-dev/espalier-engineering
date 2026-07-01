---
name: espalier
description: Execute the Espalier development pipeline for a requirement
---

# Espalier Pipeline Runner

## When to Use
- "Implement this requirement using Espalier"
- "Run the full pipeline for this feature"
- "/espalier <requirement description>"

## Instructions

You are the pipeline orchestrator. For the given requirement, drive it through
all 10 stages defined in `espalier/pipeline.md`.

### Before Starting

1. Read `espalier/pipeline.md` for stage definitions
2. Check for existing state: look in `espalier/changes/` for a matching requirement
   - If found, read `pipeline-state.md` and RESUME from the current stage
   - If not found, create a new directory and start from Stage 1

### Flag Parsing

The invocation may carry flags BEFORE the requirement. Scan tokens from the start:
while a token looks like `--flag`, consume it; stop at the first token that does
not — everything from there on is the requirement text (so a `--word` inside the
requirement itself is never mistaken for a flag).

| Flag | Effect |
|------|--------|
| `--no-grill` | Set `GRILL_DISABLED=yes` — Stage 1 skips the requirement grill. |
| `--resume` | Recognized no-op. Resumption is already automatic (see Session Resumption); accept and drop the token. |

An unrecognized leading `--token` is NOT absorbed into the requirement — warn the
user (`unrecognized flag: --token; ignoring`) and drop it. Only the flags above are
recognized.

### Stage 0 Pre-Flight (drift + conventions + doctor)

Run this BEFORE Stage 1. Source the drift helpers:

```bash
. espalier/hooks/drift-helpers.sh
```

Gather all three signals BEFORE prompting:
1. **STALE** — `stale_files()` lists flagged files; `tier_counts()` buckets them
   into fresh / aging / stale / critical / expired.
2. **CONV** — if `espalier/.conventions.tsv` exists, scan for any `pattern_key`
   with >= 3 `diverges` rows (promotion candidates).
3. **DOCTOR** — `doctor_due()`. Skip if `/espalier-doctor` is not installed.

If all three are empty/false → no prompt, proceed to Stage 1.
Otherwise issue ONE `AskUserQuestion` summarising all three:

```
Pre-flight found:
  - {N} stale doc(s): {tier breakdown}
  - {M} convention(s) over the promotion threshold
  - doctor scan due ({cadence})
Options:
  1. Handle now — run /espalier-prune + review conventions, then resume
  2. Proceed    — continue to Stage 1 with current docs
  3. Abort
```

Default: "Handle now" if any stale doc is critical/expired, else "Proceed".
If only fresh (<14d) stale docs and no conv/doctor signal → treat as empty.

### Convention Promotion

When the Stage 0 pre-flight reports a `pattern_key` with >= 3 `diverges` rows in
`espalier/.conventions.tsv` and the user picks "Handle now", surface the
candidate with `AskUserQuestion`:

```
Convention "{pattern_key}" has diverged in {N} changes:
  {change_slug : location, one per row}
Options:
  1. Promote   — bless the new pattern in the rule file, deprecate the old.
  2. Reject    — the new pattern is wrong; code should conform to the rule.
  3. Exception — sanction it under the rule's "## Exceptions" (a carve-out,
                 not a new default).
  4. Wait      — leave the rows; re-prompt at the next occurrence.
```

- **Promote** — the orchestrator edits the rule file DIRECTLY (not
  `/espalier-prune`: prune re-runs a scout, which re-derives the rule from a
  code base that is now a MIX of old + new and cannot make the decision). Then
  flip those rows' status `diverges` → `promoted`.
- **Reject** — flip those rows → `rejected`. The threshold counts only
  `diverges`, so a rejected pattern stops counting.
- **Exception** — append under the rule's "## Exceptions"; flip rows → `exception`.
- **Wait** — leave rows `diverges`.

Flip a row's status by editing `espalier/.conventions.tsv` — change the 5th tab
field (`status`) of every matching row. The edit is committed by the same
Stage 0 → Stage 7 run (the orchestrator stages `.conventions.tsv` at Stage 7).
`coupled_with` candidates are surfaced together — promote/reject them as a set.

### Session Resumption

On every invocation, check:
```
find espalier/changes -mindepth 3 -maxdepth 3 -name pipeline-state.md
```

If any state file is found with an in-progress stage marker (Current Stage < 10):
- Read it to find current stage and history
- Announce: "Resuming {requirement} from Stage {N}"
- Continue from that stage (do NOT restart from 1)

### Stage Execution Protocol

For each stage:
1. **Announce:** "## Stage N: {name}"
2. **Update state:** Write current stage to pipeline-state.md
3. **Load context:** Read the skill/agent file specified for this stage
4. **Execute:** Perform work or delegate to sub-agent
5. **Verify gate:** Check the quality gate
6. **Record:** Append result to pipeline-state.md
7. **Decision:**
   - PASS → advance to next stage (EXCEPT the Stage 2 → Stage 3 transition: the
     **Requirements Approval Gate** below must pass first — a Stage 2 PASS alone
     does NOT authorize coding)
   - FAIL → follow rollback path
   - HUMAN → pause and ask user (use AskUserQuestion tool)

### Requirements Approval Gate (BLOCKING — before Stage 3 Coding)

MANDATORY. Must NOT be skipped on a PASS. Stages 1 (requirements written +
grilled) and 2 (requirements review) finish WITHOUT writing any code. Do NOT
chain Stage 1 → 2 → 3 automatically — that is the bug this gate closes. After
Stage 2's gate passes (no P0/P1 reqs findings), HALT and get explicit user
sign-off on `requirements.md` before Stage 3.

1. Present a concise summary of the final `requirements.md`: the one-line goal,
   the acceptance criteria, and anything the Stage 1 grill resolved or marked
   out-of-scope.
2. Ask with `AskUserQuestion`:

   ```
   Requirements are written and reviewed. Nothing has been coded yet.
   Approve to start Stage 3 (Coding)?

   Options:
     1. Approve — proceed to coding.
     2. Edit    — tell me what to change; I revise requirements.md and re-ask.
     3. Abort   — stop here; leave requirements.md as a draft (Status: ABORTED).
   ```

3. Advance to Stage 3 ONLY on **Approve**. On **Edit**, revise `requirements.md`
   per the feedback, re-run the Stage 2 gate, and re-present this gate. On
   **Abort**, write Status: ABORTED to pipeline-state.md and stop.

**Non-interactive exception:** on a no-TTY run (same condition that auto-skips
the Stage 1 grill), this gate cannot prompt — record `requirements auto-approved
(non-interactive)` in the Stage History and proceed. Interactive runs ALWAYS
prompt.

Record the outcome in pipeline-state.md Stage History (e.g.
`| 2 | PASSED | … | Requirements approved by user |`).

### Sub-Agent Delegation

Stages 3-6 use sub-agents for separation of concerns:

**Stage 3 (Coding):**
```
Agent tool:
  prompt: |
    You are the harness-coder.
    Read espalier/agents/harness-coder.md for your full instructions.

    REQUIREMENT: {paste requirement from Stage 1 output}
    TASK: {specific sub-task from decomposition}

    When done, write your coding report to:
    espalier/changes/{type}/{slug}/coding-report.md
```

**Stage 4 (Review):**
```
Agent tool:
  prompt: |
    You are the harness-reviewer.
    Read espalier/agents/harness-reviewer.md for your full instructions.

    WHAT TO REVIEW: Read espalier/changes/{type}/{slug}/coding-report.md to see
    what the coder did. Then read the actual files listed there.

    Write your review to: espalier/changes/{type}/{slug}/review-record.md
```

**Stage 4 (Security Audit — runs as a panel with the review above):**
```
Agent tool:
  prompt: |
    You are the harness-security auditor.
    Read espalier/agents/harness-security.md for your full instructions.

    WHAT TO AUDIT: Read espalier/changes/{type}/{slug}/coding-report.md to see
    what changed, then trace the touched endpoints. Assume the client is hostile.

    Write your audit to: espalier/changes/{type}/{slug}/security-record.md
```

Stage 4 is a **review panel**: `harness-reviewer` (correctness / conventions,
→ review-record.md) and `harness-security` (trust boundary, → security-record.md)
both run on the CURRENT diff. Run this procedure every round — it IS the gate, not
a description. Do not advance to Stage 5 by any other path:

1. **Baseline.** Note whether `espalier/changes/{type}/{slug}/security-record.md`
   exists and its size/mtime. Spawn BOTH agents in ONE message (concurrent).
2. **Completion check.** After both return, confirm `security-record.md` was written
   THIS round (it now exists and differs from the baseline). `harness-security`
   OVERWRITES it each round, so it always reflects the current round only. If it is
   missing or unchanged, the security agent did NOT complete — re-spawn it; never
   treat a missing or stale file as a pass.
3. **Collect P0s from BOTH files.** Read the current verdict + P0 rows from
   `review-record.md` (harness-reviewer) AND `security-record.md` (harness-security).
4. **If EITHER file has a P0 →** re-spawn `harness-coder` with the combined findings
   (a Stage 3 action), increment the shared round counter, and return to step 1. At
   counter = 2, escalate to a human WITHOUT another re-spawn (the coder gets at most
   one re-spawn per counter limit).
5. **Only when BOTH return zero P0 on the current code →** write the `Reviewed-Diff`
   certificate, THEN run the "Stage 4 Post-Review" drift processing below. The exit
   gate requires BOTH clean — never one agent's pass alone. A security P0 shares the
   correctness "Max 2 P0 rounds → escalate" counter.

**Stage 5 (Testing):**
```
Agent tool:
  prompt: |
    You are the harness-coder in testing mode.
    Read espalier/agents/harness-coder.md AND espalier/skills/espalier-testing/SKILL.md.

    WHAT TO TEST: Read espalier/changes/{type}/{slug}/coding-report.md to see
    what was implemented. Write tests for those changes.

    ALSO read espalier/changes/{type}/{slug}/security-record.md (if present) — for
    EVERY field in its `## Security-Sensitive Fields` contract, write the negative
    abuse test it names (tamper the value → assert rejected → assert store unchanged). A
    contracted field with no such test will be blocked at Stage 6.

    Append test report to: espalier/changes/{type}/{slug}/coding-report.md
```

**Stage 6 (Test Review):**
```
Agent tool:
  prompt: |
    You are the harness-reviewer reviewing tests.
    Read espalier/agents/harness-reviewer.md for your instructions.

    WHAT TO REVIEW: The test files created in Stage 5.
    Read espalier/changes/{type}/{slug}/coding-report.md for the list.

    Check: Are tests meaningful? Do they cover edge cases?
    Do they match project testing patterns in espalier/skills/espalier-testing/SKILL.md?
    Security coverage: does EVERY field in espalier/changes/{type}/{slug}/security-record.md's
    `## Security-Sensitive Fields` contract have a passing abuse test
    (tamper → rejected → store unchanged)? A missing one is a P0 → back to Stage 5.

    Append review to: espalier/changes/{type}/{slug}/review-record.md
```

### Stage 4 Post-Review: Drift & Convention Index

After Stage 4 PASSES (step 5 above — BOTH panel agents returned zero P0 and the
certificate is written), parse `review-record.md` for Convention Drift blocks (see
`harness-reviewer.md`) and flag the affected rule files. Do NOT run this on a P0
round: a malformed-drift P0 written back mid-loop would contaminate the next
round's P0 count.

> Variables in scope: `TYPE` and `SLUG` are the active change's type/slug.

```bash
. espalier/hooks/drift-helpers.sh
REV="espalier/changes/${TYPE}/${SLUG}/review-record.md"
[ -f "$REV" ] || exit 0
SHA=$(git rev-parse HEAD)

python3 espalier/hooks/parse-drift-blocks.py "$REV" \
| while IFS=$'\t' read -r KIND RULE_FILE COUPLED; do
  case "$KIND" in
    DRIFT)
      mark_stale "$RULE_FILE" "$SHA" "convention drift flagged in ${TYPE}/${SLUG} review"
      LINE="convention_drift: $RULE_FILE"
      [ -n "$COUPLED" ] && LINE="$LINE (coupled_with: $COUPLED)"
      echo "$LINE" >> "espalier/changes/${TYPE}/${SLUG}/pipeline-state.md"
      ;;
    MALFORMED)
      echo "P0: malformed Convention Drift block — $RULE_FILE" \
        >> "espalier/changes/${TYPE}/${SLUG}/review-record.md"
      ;;
  esac
done
```

A `MALFORMED` line means the reviewer bundled unrelated drifts into one block —
it is written back as a P0 so the next review round splits them. `coupled_with`
blocks resurface together at the next Stage 0 pre-flight (promote-together /
reject-together / split).

**Convention Observations → the convention index.** The reviewer also emits
lower-bar Convention Observations (see `harness-reviewer.md`) — one per
divergence, with NO aggregation key. The orchestrator assigns the key: a fresh
isolated reviewer cannot (three reviews of one pattern would coin three keys and
the count would never reach the threshold). For each Observation in
`review-record.md`:

1. Read existing keys: `cut -f3 espalier/.conventions.tsv 2>/dev/null | sort -u`.
2. Map the Observation's `description` to an existing `pattern_key`, or mint a
   new kebab-case key.
3. Append the row:

```bash
. espalier/hooks/drift-helpers.sh
append_convention "${TYPE}/${SLUG}" "$PATTERN_KEY" "$LOCATION"
```

`append_convention` sanitizes every field and de-dupes on
(change_slug, pattern_key, location), so re-running Stage 4 never inflates the
count. `espalier/.conventions.tsv` is tracked and append-only — columns
`date · change_slug · pattern_key · location · status` (+ optional 6th
`coupled_with`); `status` ∈ `diverges | promoted | rejected | exception`. When a
`pattern_key` reaches 3 `diverges` rows it is a promotion candidate, surfaced at
the next Stage 0 pre-flight (see Convention Promotion).

### State File Format

Parse `{type}` from the requirement prefix:
- `feat: <text>` → type = `feat`
- `fix: <text>` → type = `fix`
- `refactor: <text>` → type = `refactor`
- `docs: <text>` → type = `docs`
- Anything else → type = `feat` (default)

Then derive `{kebab}` from the remainder of the requirement (kebab-case, max 60 chars, strip slashes).

**Date-prefix the slug** so change folders sort chronologically in a directory
listing:

```bash
DATE="$(date -u +%Y-%m-%d)"   # ISO date, UTC — lexical sort == chronological sort
SLUG="${DATE}-${kebab}"       # e.g. 2026-06-02-add-login-rate-limit
```

`{slug}` = `{YYYY-MM-DD}-{kebab}` everywhere below. The ISO date MUST be a
*prefix* (not a suffix) — only a leading `YYYY-MM-DD` makes lexical sort equal
chronological sort. Session Resumption (above) globs `pipeline-state.md` by path
and reads Status, so the date prefix never breaks resume. Reverse-lookup derives
its slug from the folder basename, so the dated slug flows through unchanged.

Create `espalier/changes/{type}/{slug}/pipeline-state.md`:

```markdown
# Pipeline State: {requirement title}

## Status
- Current Stage: {N}
- Started: {ISO timestamp}
- Last Updated: {ISO timestamp}
- Total Rollbacks: {count}
- Review Rounds: req={n}/3, code={n}/2, test={n}/2

## Stage History
| Stage | Status | Timestamp | Notes |
|-------|--------|-----------|-------|
| 1 | PASSED | 2025-01-15T10:00 | Requirements accepted |
| 2 | PASSED | 2025-01-15T10:05 | 1 round, no P0s |
| 3 | IN_PROGRESS | 2025-01-15T10:10 | |
```

### Stage 7: Stage the Convention Index

If this run appended to `espalier/.conventions.tsv` (Stage 4) or flipped a
row's status (Convention Promotion), stage the file into the Stage 7 commit
alongside `espalier/changes/{type}/{slug}/*`:

```bash
git add espalier/.conventions.tsv
```

`.conventions.tsv` is tracked; staging it here keeps the working tree clean for
the Stage 7 gate and never leaves an automation-written file uncommitted.

### Stage 7 Commit Recording

After `git push` at Stage 7 succeeds, capture the commit SHA + files changed and
append to the state file's Commits table.

> Variables in scope: `TYPE` and `SLUG` are the active change's type/slug, set by
> the orchestrator at Stage Execution entry. Substitute them when running the snippet.

```bash
SHA=$(git rev-parse HEAD)
FILES=$(git diff-tree --no-commit-id --name-only -r HEAD | tr '\n' ',' | sed 's/,$//')
STATE="espalier/changes/${TYPE}/${SLUG}/pipeline-state.md"

# Ensure section exists
if ! grep -q "^## Commits" "$STATE"; then
  cat >> "$STATE" << EOF

## Commits
| Stage | SHA | Files |
|-------|-----|-------|
EOF
fi

# Idempotency: skip if this stage+SHA pair already recorded
if ! grep -qE "^\| 7 \| ${SHA} " "$STATE"; then
  echo "| 7 | $SHA | $FILES |" >> "$STATE"
fi

# Self-heal reverse-lookup cache (silently no-op if helpers absent)
[ -f espalier/hooks/lookup-helpers.sh ] && {
  . espalier/hooks/lookup-helpers.sh
  _cache_append "$SHA" "${TYPE}/${SLUG}" "original"
}
```

This commit-record is read at fix-time by `/espalier-fix` Stage 0 reverse lookup,
and used by the post-merge hook for squash-merge mapping.

### Stage 7 Reverse-link to PARTIAL_FIX (when applicable)

If this feat's `requirements.md` frontmatter has `filed_from_partial_fix: fix/{slug}`
(meaning it was filed as the root-cause for a partial fix), write back to the partial
fix's pipeline-state.md so the audit chain closes:

> Variables in scope: `TYPE` and `SLUG` are the active change's identifiers.

```bash
REQS="espalier/changes/${TYPE}/${SLUG}/requirements.md"
FILED_FROM=$(grep '^filed_from_partial_fix:' "$REQS" 2>/dev/null | awk '{print $2}')

if [ -n "$FILED_FROM" ]; then
  PARTIAL_STATE="espalier/changes/${FILED_FROM}/pipeline-state.md"
  if [ -f "$PARTIAL_STATE" ]; then
    # Update Root Cause Status line
    if [ "$(uname)" = "Darwin" ]; then
      sed -i '' 's|^- Root Cause Status:.*$|- Root Cause Status: COMPLETE (verified '"$(date -u +%Y-%m-%d)"')|' "$PARTIAL_STATE"
    else
      sed -i    's|^- Root Cause Status:.*$|- Root Cause Status: COMPLETE (verified '"$(date -u +%Y-%m-%d)"')|' "$PARTIAL_STATE"
    fi

    if ! grep -q "^## Root Cause Addressed By" "$PARTIAL_STATE"; then
      cat >> "$PARTIAL_STATE" << EOF

## Root Cause Addressed By
| Feat | Status | Date |
|------|--------|------|
EOF
    fi
    echo "| feat/${SLUG} | COMPLETE | $(date -u +%Y-%m-%d) |" >> "$PARTIAL_STATE"
  fi
fi
```

### Stage 8.5 — Doc Drift Check (notify-only)

Runs as a sub-step between Stage 8 (CI verify) and Stage 9 (deploy). It edits no
doc, prompts nothing, blocks nothing — it only surfaces drift this run may have
caused.

> "8.5" is a label, not a numeric stage. Do NOT write `Current Stage: 8.5` to
> pipeline-state.md — it would break `pre-push-gate.sh`'s integer stage parse.
> Record Stage 8.5 only in the Stage History notes.

```bash
. espalier/hooks/drift-helpers.sh
STALE=$(stale_files)
PATCHES="espalier/changes/${TYPE}/${SLUG}/doc-patches.md"

if [ -z "$STALE" ]; then
  echo "Stage 8.5: no drift."
else
  {
    echo ""
    echo "## Stage 8.5 Doc Drift (notify-only)"
    echo "| File | Tier | Reason |"
    echo "|------|------|--------|"
    printf '%s\n' "$STALE" | while IFS= read -r f; do
      [ -z "$f" ] && continue
      tier=$(classify_tier "$f")
      reason=$(awk -F'\t' -v x="$f" '$1==x {print $4; exit}' espalier/.drift-state.tsv)
      echo "| $f | $tier | $reason |"
    done
  } >> "$PATCHES"
  N=$(printf '%s\n' "$STALE" | grep -c .)
  echo "Stage 8.5: $N stale doc(s) — run /espalier-prune to refresh. (Not blocking; pipeline continues.)"
fi
```

`doc-patches.md` is a per-change artifact created on demand under
`espalier/changes/{type}/{slug}/` — like `ci-result.md`. Stage 8.5 touches no
rule/wiki/spec file, so it cannot dirty a project-level doc. Advance to Stage 9
regardless of the result. In-pipeline auto-apply is a v2 item — refresh stays a
deliberate `/espalier-prune`.

### Rollback Protocol

When a gate fails:
1. Identify failure type from gate output
2. Look up rollback target in pipeline.md
3. Update pipeline-state.md (increment rollback counter, record failure)
4. If total rollbacks > 3: STOP and ask human
5. Otherwise: announce rollback target and re-execute from that stage

### Human Checkpoints

At stages marked with human checkpoint in pipeline.md:
- Present a concise summary of what was done
- Use AskUserQuestion tool with options: Approve / Request Changes / Skip
- "Skip" only allowed for stages 9-10
- "Request Changes" triggers rollback with human's feedback as context

### Completion

When Stage 10 passes:
- Update pipeline-state.md with final status: COMPLETE
- Summarize: files changed, tests added, review findings addressed
- Report total rounds and rollbacks
