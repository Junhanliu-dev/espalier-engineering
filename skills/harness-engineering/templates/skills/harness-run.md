---
name: harness-run
description: Execute the harness development pipeline for a requirement
---

# Harness Pipeline Runner

## When to Use
- "Implement this requirement using the harness"
- "Run the full pipeline for this feature"
- "/harness-run <requirement description>"

## Instructions

You are the pipeline orchestrator. For the given requirement, drive it through
all 10 stages defined in `harness/pipeline.md`.

### Before Starting

1. Read `harness/pipeline.md` for stage definitions
2. Check for existing state: look in `harness/changes/` for a matching requirement
   - If found, read `pipeline-state.md` and RESUME from the current stage
   - If not found, create a new directory and start from Stage 1

### Session Resumption

On every invocation, check:
```
find harness/changes -mindepth 3 -maxdepth 3 -name pipeline-state.md
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
   - PASS → advance to next stage
   - FAIL → follow rollback path
   - HUMAN → pause and ask user (use AskUserQuestion tool)

### Sub-Agent Delegation

Stages 3-6 use sub-agents for separation of concerns:

**Stage 3 (Coding):**
```
Agent tool:
  prompt: |
    You are the harness-coder.
    Read harness/agents/harness-coder.md for your full instructions.

    REQUIREMENT: {paste requirement from Stage 1 output}
    TASK: {specific sub-task from decomposition}

    When done, write your coding report to:
    harness/changes/{type}/{slug}/coding-report.md
```

**Stage 4 (Review):**
```
Agent tool:
  prompt: |
    You are the harness-reviewer.
    Read harness/agents/harness-reviewer.md for your full instructions.

    WHAT TO REVIEW: Read harness/changes/{type}/{slug}/coding-report.md to see
    what the coder did. Then read the actual files listed there.

    Write your review to: harness/changes/{type}/{slug}/review-record.md
```

**Stage 5 (Testing):**
```
Agent tool:
  prompt: |
    You are the harness-coder in testing mode.
    Read harness/agents/harness-coder.md AND harness/skills/harness-testing/SKILL.md.

    WHAT TO TEST: Read harness/changes/{type}/{slug}/coding-report.md to see
    what was implemented. Write tests for those changes.

    Append test report to: harness/changes/{type}/{slug}/coding-report.md
```

**Stage 6 (Test Review):**
```
Agent tool:
  prompt: |
    You are the harness-reviewer reviewing tests.
    Read harness/agents/harness-reviewer.md for your instructions.

    WHAT TO REVIEW: The test files created in Stage 5.
    Read harness/changes/{type}/{slug}/coding-report.md for the list.

    Check: Are tests meaningful? Do they cover edge cases?
    Do they match project testing patterns in harness/skills/harness-testing/SKILL.md?

    Append review to: harness/changes/{type}/{slug}/review-record.md
```

### State File Format

Parse `{type}` from the requirement prefix:
- `feat: <text>` → type = `feat`
- `fix: <text>` → type = `fix`
- `refactor: <text>` → type = `refactor`
- `docs: <text>` → type = `docs`
- Anything else → type = `feat` (default)

Then derive `{slug}` from the remainder of the requirement (kebab-case, max 60 chars, strip slashes).

Create `harness/changes/{type}/{slug}/pipeline-state.md`:

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

### Stage 7 Commit Recording

After `git push` at Stage 7 succeeds, capture the commit SHA + files changed and
append to the state file's Commits table.

> Variables in scope: `TYPE` and `SLUG` are the active change's type/slug, set by
> the orchestrator at Stage Execution entry. Substitute them when running the snippet.

```bash
SHA=$(git rev-parse HEAD)
FILES=$(git diff-tree --no-commit-id --name-only -r HEAD | tr '\n' ',' | sed 's/,$//')
STATE="harness/changes/${TYPE}/${SLUG}/pipeline-state.md"

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

# Self-heal reverse-lookup cache (Phase 4.6 — silently no-op if helpers absent)
[ -f harness/hooks/lookup-helpers.sh ] && {
  . harness/hooks/lookup-helpers.sh
  _cache_append "$SHA" "${TYPE}/${SLUG}" "original"
}
```

This commit-record is read at fix-time by `/harness-fix` Stage 0 reverse lookup,
and used by the post-merge hook for squash-merge mapping.

### Stage 7 Reverse-link to PARTIAL_FIX (when applicable)

If this feat's `requirements.md` frontmatter has `filed_from_partial_fix: fix/{slug}`
(meaning it was filed as the root-cause for a partial fix), write back to the partial
fix's pipeline-state.md so the audit chain closes:

> Variables in scope: `TYPE` and `SLUG` are the active change's identifiers.

```bash
REQS="harness/changes/${TYPE}/${SLUG}/requirements.md"
FILED_FROM=$(grep '^filed_from_partial_fix:' "$REQS" 2>/dev/null | awk '{print $2}')

if [ -n "$FILED_FROM" ]; then
  PARTIAL_STATE="harness/changes/${FILED_FROM}/pipeline-state.md"
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
