---
name: harness-fix
description: Bug-fix orchestrator — 5-stage pipeline with auto-link to the change that introduced the bug
---

# Harness Fix Runner

## When to Use
- "Fix the bug in <file>:<line>"
- "/harness-fix <bug description>"
- "Bug: NPE at src/payment.ts:42"

Do NOT use for:
- Features ("add X") → use `/harness-run feat: …`
- Refactors with no behaviour change → use `/harness-run refactor: …`
- Fixes that obviously cross >5 files, multiple layers, or require schema changes → use `/harness-run fix: …` directly (full pipeline)

## Pipeline Overview (5 stages, vs 10 for harness-run)

| Stage | Name | Skipped from harness-run? |
|-------|------|---------------------------|
| 0 | Auto-link Discovery | NEW (fix-only) |
| 1 | Bug Requirements | Slimmer than feat reqs |
| 3 | Coding | Same |
| 4 | Code Review | Same |
| 5 | Test Writing | Same |
| 6 | Test Review | Same |
| 7 | Push | Same + back-link write |

Skipped from full pipeline:
- **Stage 2** (standalone reqs review — merged into Stage 4 code review)
- **Stage 8** (CI verify — fix lane defers to repo CI hook)
- **Stage 9** (deploy verify — fix lane assumes same deploy as next normal release)
- **Stage 10** (user confirm — bug reporter confirms via the regression test, not a separate gate)

## Flags

| Flag | Effect |
|------|--------|
| `--slug <name>` | Override auto-derived slug (see Slug Derivation below). Must match `^[a-z0-9][a-z0-9-]{0,79}$`. |
| `--caused-by <slug>` | Skip blame, explicit causal link (e.g. `--caused-by feat/bulk-export-endpoint`). |
| `--build-index` | Run `harness/hooks/rebuild-commit-index.sh`, then continue normally. |
| `--rebuild-index` | Delete `harness/.commit-index.tsv`, then run rebuild (forces fresh state). |
| `--no-index` | Bypass reverse-lookup cache for this invocation only (debug). |

Env vars:
- `HARNESS_CACHE_THRESHOLD_MS=<ms>` — override the auto-build slow-scan threshold (default 1000ms; 0 = never warn).

### Flag Handling (parsed at invocation entry)

Parse flags from the user's invocation string. Strip them out before deriving the slug from remaining text. Set the corresponding shell variables for Stage 0 / later stages to consume:

```bash
# Pseudo-shell of what the orchestrator must do before Stage 0:
SLUG_OVERRIDE=""
CAUSED_BY_OVERRIDE=""
NO_INDEX="no"
DO_BUILD_INDEX="no"
DO_REBUILD_INDEX="no"

# Walk tokens, extract flags
# (Orchestrator parses argv; below is the variable contract — not literal bash)
case "$flag" in
  --slug)          SLUG_OVERRIDE="$next_arg" ;;
  --caused-by)     CAUSED_BY_OVERRIDE="$next_arg" ;;
  --no-index)      NO_INDEX="yes" ;;
  --build-index)   DO_BUILD_INDEX="yes" ;;
  --rebuild-index) DO_REBUILD_INDEX="yes" ;;
esac

# Pre-Stage-0 actions
if [ "$DO_REBUILD_INDEX" = "yes" ]; then
  rm -f harness/.commit-index.tsv
  bash harness/hooks/rebuild-commit-index.sh
elif [ "$DO_BUILD_INDEX" = "yes" ]; then
  bash harness/hooks/rebuild-commit-index.sh
fi

# Stage 0 then reads $NO_INDEX, $SLUG_OVERRIDE, $CAUSED_BY_OVERRIDE.
# Source helpers once:
. harness/hooks/lookup-helpers.sh
```

The remaining (flag-stripped) text becomes the bug description fed to Slug Derivation step 2+.

## Slug & Path

- Slug derivation: see Slug Derivation section below. Summary: sanitize bug input → kebab-case ASCII, max 80 chars; `--slug <name>` overrides; collision prompts user.
- Path = `harness/changes/fix/{slug}/`
- All files inherit from `harness/changes/_template/`.

## Slug Derivation

Slug is produced by this pipeline. All steps are deterministic except step 1 (override) and step 11 (collision prompt).

### Step 1: Override check
If user passed `--slug <name>`:
  - Validate: must match `^[a-z0-9][a-z0-9-]{0,79}$` (≤ 80 chars, kebab, starts non-hyphen)
  - If valid, skip to step 11 (collision check).
  - If invalid, error and exit with message showing the regex.

### Step 2: Strip type prefix
`fix: foo bar` → `foo bar`
`feat: ignored` → error (wrong skill — harness-fix should only see fix-shape input)

### Step 3: Lowercase
`NPE In Cart` → `npe in cart`

### Step 4: Transliterate Unicode → ASCII
Use Python `unidecode` library:
```python
from unidecode import unidecode
ascii_text = unidecode(input_text)
```
If unidecode unavailable, fall back to:
```python
ascii_text = input_text.encode('ascii', 'ignore').decode('ascii')
```
(Strip fallback loses CJK/RTL meaning but never crashes.)

Examples:
- `修复支付错误` → unidecode: `Xiu Fu Zhi Fu Cuo Wu` → continues to step 5
- `café crash` → unidecode: `cafe crash`
- With ASCII-strip fallback: `修复支付错误` → `` (continues to step 8 → timestamp fallback)

### Step 5: Replace non-[a-z0-9] runs with single hyphen
`npe in cart` → `npe-in-cart`
`bug at src/payment.ts:42` → `bug-at-src-payment-ts-42`
`v2.3.1 broken` → `v2-3-1-broken`

### Step 6: Trim leading/trailing hyphens
`-rf this is joke-` → `rf-this-is-joke`

### Step 7: Truncate to 80 chars at word boundary
- If ≤ 80, keep as-is.
- If > 80, cut at last hyphen ≤ 80. If no hyphen in first 80 chars, hard-cut at 80.

### Step 8: Empty-result fallback
If empty after sanitization (e.g., all-symbol input or ASCII-strip-emptied CJK), use:
`fix-{YYYYMMDD-HHMMSS}` (UTC timestamp, e.g., `fix-20260518-143022`)

### Step 9: Reserved-name prefix
If slug ∈ {con, aux, nul, prn, com1..9, lpt1..9} (Windows reserved):
prefix with `fix-`

### Step 10: Leading-hyphen guard
If starts with hyphen (post-sanitization edge case): prefix with `x-`

### Step 11: Collision detection + prompt
Check `harness/changes/fix/{slug}/` (and tombstones at `harness/changes/fix/{slug}/TOMBSTONE.md`):

| Existing state | Action |
|----------------|--------|
| No directory | Use slug. Done. |
| Directory exists, Status: IN_PROGRESS | Resume that fix. Announce "Resuming fix/{slug} from Stage {N}". |
| Directory exists, terminal Status (COMPLETE / ABORTED / ABORTED_LATE / ESCALATED / ESCALATED_LATE) | **Prompt user** (below) |
| Directory exists, Status: PARTIAL_FIX | **Prompt user** (below) |
| Only `TOMBSTONE.md` exists (legacy migration) | Follow tombstone pointer; ask user "fix/{slug} was migrated to feat/{target}. New fix at fix/{slug}-2, or work on feat/{target} instead?" |

Collision prompt (use `AskUserQuestion`):

```
Slug collision detected.

Existing: harness/changes/fix/{slug}/ — Status: {EXISTING_STATUS}
{If PARTIAL_FIX: Root cause feat: {root_cause_feat}}
{If COMPLETE: Closed on {date}}

Options:
  1. New fix with suffix — use fix/{slug}-2 (or next available -N)
  2. {Only if Status=PARTIAL_FIX or IN_PROGRESS:} Resume / extend the existing fix
  3. {Only if Status=COMPLETE/ABORTED/etc:} Re-open the existing fix
       (mark Status: REOPENED, restart from Stage 1, append "Reopened at" row to pipeline-state.md)
  4. Custom slug — re-prompt for --slug value
  5. Abort
```

### Step 12: Final validation
- Confirm slug matches `^[a-z0-9][a-z0-9-]{0,79}$` one more time.
- Confirm `harness/changes/fix/{slug}/` is now creatable (does not exist OR was user-confirmed for reuse).

## Before Starting

1. Read `harness/pipeline.md` for stage definitions (Stages 3-7 unchanged from harness-run).
2. Check session resumption:
   ```bash
   find harness/changes/fix -mindepth 2 -maxdepth 2 -name pipeline-state.md
   ```
   Read each, look for `Current Stage:` < 7 (in-progress).
3. If matching slug found, RESUME from current stage.
4. Otherwise, derive slug (above) and create new `harness/changes/fix/{slug}/`.

## Stage 0: Auto-Link Discovery (NEW)

> Fully specified in plan §6 (Phase 4). Summary follows; see plan for full code.

### 0.1 Parse user input for a bug anchor

Priority order (try each until one succeeds):

| Priority | Source | Example | Extracts |
|----------|--------|---------|----------|
| 1 | `--caused-by <slug>` flag | `/harness-fix --caused-by feat/bulk-export NPE...` | slug directly, skip blame |
| 2 | `file:line` pattern in bug text | `src/payment.ts:42` | file, line |
| 3 | Stack trace block | `at handler (src/auth.ts:88:14)` | list of file:line frames |
| 4 | Bare file path | `bug in src/payment.ts` | file only |
| 5 | Symbol name | `bug in processPayment function` | symbol → grep first match → file:line |
| 6 | No anchor at all | "checkout is broken" | prompt user |

### 0.2 Tiered reverse-lookup chain

Per-SHA lookup runs through Layers 0-3. `harness/.merge-hook-decision`
(written at `/harness-engineering` init via plan §6.5) governs Layer 3.

> Prerequisite: source helpers once before this block runs (also done by Flag Handling section):
> `. harness/hooks/lookup-helpers.sh`

```bash
DECISION=$(cat harness/.merge-hook-decision 2>/dev/null || echo "ask-later")

# Resolve ask-later UPFRONT so the inner loop never hits a prompt.
# (Prompt is the only path that needs user input mid-loop; hoisting avoids
# the "skip-current-SHA after prompt" trap that `continue` inside `case` causes.)
if [ "$DECISION" = "ask-later" ] || [ -z "$DECISION" ]; then
  _prompt_user_for_merge_decision
  DECISION=$(cat harness/.merge-hook-decision 2>/dev/null || echo "skip-only")
fi

# Build entries in stack-trace order. Index 0 = primary, rest = call_path. Cap=5.
TOTAL_FRAMES=${#SHAS[@]}
CAP=5
if [ "$TOTAL_FRAMES" -gt "$CAP" ]; then
  SHAS=("${SHAS[@]:0:$CAP}")
  OVERFLOW_NOTE="$((TOTAL_FRAMES - CAP)) additional frames not linked (cap reached)"
fi

for IDX in "${!SHAS[@]}"; do
  SHA="${SHAS[$IDX]}"
  ROLE=$([ "$IDX" = "0" ] && echo "primary" || echo "call_path")

  # Layer 0: cache hit (Phase 4.6 — fast path)
  if [ "$NO_INDEX" != "yes" ] && [ -f "harness/.commit-index.tsv" ]; then
    CACHE_HIT=$(grep "^$SHA	" harness/.commit-index.tsv 2>/dev/null | head -1)
    if [ -n "$CACHE_HIT" ]; then
      SLUG=$(echo "$CACHE_HIT" | cut -f2)
      KIND=$(echo "$CACHE_HIT" | cut -f3)
      LOOKUP=$([ "$KIND" = "squashed_to" ] && echo "squash_hook" || echo "exact")
      _push_entry "$SLUG" "$SHA" "$ROLE" "$LOOKUP"
      continue
    fi
  fi

  # Layer 1: exact SHA match (scan + self-heal cache)
  SCAN_START=$(date +%s%N 2>/dev/null || date +%s)
  SLUG=$(grep -lr "$SHA" harness/changes/*/*/pipeline-state.md 2>/dev/null \
         | head -1 | sed 's|harness/changes/||; s|/pipeline-state.md||')
  _maybe_warn_slow_scan "$SCAN_START"
  if [ -n "$SLUG" ]; then
    _push_entry "$SLUG" "$SHA" "$ROLE" "exact"
    _cache_append "$SHA" "$SLUG" "original"
    continue
  fi

  # Layer 2: hook-recorded squash mapping (self-heal cache)
  SCAN_START=$(date +%s%N 2>/dev/null || date +%s)
  SLUG=$(grep -lr "squashed_to: $SHA" harness/changes/*/*/pipeline-state.md 2>/dev/null \
         | head -1 | sed 's|harness/changes/||; s|/pipeline-state.md||')
  _maybe_warn_slow_scan "$SCAN_START"
  if [ -n "$SLUG" ]; then
    _push_entry "$SLUG" "$SHA" "$ROLE" "squash_hook"
    _cache_append "$SHA" "$SLUG" "squashed_to"
    continue
  fi

  # Layer 3: dispatch based on cached merge-hook decision
  case "$DECISION" in
    installed)
      SLUG=$(_fuzzy_file_overlap_match "$SHA")
      [ -n "$SLUG" ] && _push_entry "$SLUG" "$SHA" "$ROLE" "fuzzy_after_hook_miss" \
                   || _push_entry "unknown_squash" "$SHA" "$ROLE" "unknown"
      ;;
    fuzzy-allowed)
      SLUG=$(_fuzzy_file_overlap_match "$SHA")
      [ -n "$SLUG" ] && _push_entry "$SLUG" "$SHA" "$ROLE" "fuzzy" \
                   || _push_entry "unknown_squash" "$SHA" "$ROLE" "unknown"
      ;;
    skip-only|never-ask)
      _push_entry "unknown_squash" "$SHA" "$ROLE" "skipped"
      ;;
    not-needed)
      _push_entry "unknown" "$SHA" "$ROLE" "unknown"
      ;;
    *)
      # Defensive: should not reach here — ask-later resolved upfront.
      _push_entry "unknown" "$SHA" "$ROLE" "unknown"
      ;;
  esac
done

_dedupe_entries_preserve_primary
[ -n "$OVERFLOW_NOTE" ] && _push_note_entry "$OVERFLOW_NOTE"
```

Helpers (`_push_entry`, `_push_note_entry`, `_dedupe_entries_preserve_primary`,
`_fuzzy_file_overlap_match`, `_prompt_user_for_merge_decision`,
`_cache_append`, `_maybe_warn_slow_scan`) live in `harness/hooks/lookup-helpers.sh`
and are sourced at Stage 0 entry.

### 0.3 Per-entry frontmatter shape

```yaml
---
type: fix
caused_by:
  - slug: feat/auth
    sha: abc1234
    role: primary
    lookup: exact
  - slug: feat/log
    sha: def5678
    role: call_path
    lookup: squash_hook
  - note: "2 additional frames not linked (cap reached)"
---
```

| Field | Values |
|-------|--------|
| `slug` | `{type}/{slug}` or `unknown_squash` or `unknown` |
| `sha` | git SHA blame returned |
| `role` | `primary` (top stack frame) \| `call_path` |
| `lookup` | `exact` \| `squash_hook` \| `fuzzy` \| `fuzzy_after_hook_miss` \| `unknown` \| `skipped` |

### 0.4 Load linked context for Stage 1

For each `caused_by` entry where slug ∉ {unknown, unknown_squash}:
- Read `harness/changes/{slug}/requirements.md` (original intent)
- Read `harness/changes/{slug}/coding-report.md` (what shipped)
- Read `harness/changes/{slug}/review-record.md` (predicted concerns — especially dismissed P2/P3)

If combined linked context > 8K tokens, summarize each linked change to acceptance-criteria + open P2/P3 findings only. Full files available via Read on demand during Stage 3.

### 0.5 Record Stage 0 outcome

Append to pipeline-state.md Stage History:

```markdown
| 0 | PASSED | {ISO timestamp} | Auto-linked to {N} change(s): {list}. Anchor: {file:line|stack|flag|symbol|skipped}{; cap reached if applicable} |
```

## Stage 1: Bug Requirements (slimmer than feat reqs)

Write `harness/changes/fix/{slug}/requirements.md`:

```yaml
---
type: fix
caused_by:           # populated by Stage 0
  - slug: ...
    sha: ...
    role: ...
    lookup: ...
---

# Bug: {one-line summary}

## Symptom
{what user sees}

## Reproduction
{steps to reproduce}

## Expected behaviour
{what should happen instead}

## Acceptance criteria
- [ ] Bug no longer reproduces with steps above
- [ ] Regression test added in tests/{matching path}
- [ ] Original feature (per caused_by) still works

## Out of scope
{anything reporter asked for that isn't this specific bug}
```

**Escalation Gate (Stage 1):** see "Escalation Gates" section below.

## Stage 3: Coding

Spawn sub-agent. Prompt:

```
You are the harness-coder.
Read harness/agents/harness-coder.md for full instructions.

REQUIREMENT: {paste requirement summary from Stage 1}
CAUSED BY: {caused_by list — read those changes' requirements + coding-report + review-record}
TASK: Fix the bug described above. Stay within the file(s) identified.

When done, write your coding report to:
harness/changes/fix/{slug}/coding-report.md
```

**Escalation Gate (Stage 3):** see "Escalation Gates" section below.

## Stage 4: Code Review

Spawn `harness-reviewer`. Output to `harness/changes/fix/{slug}/review-record.md`.

Special check for fix lane: reviewer MUST verify the fix doesn't regress the
original feature's acceptance criteria (read from `caused_by` change's `requirements.md`).

## Stage 5: Test Writing

Spawn `harness-coder` in testing mode:

```
You are the harness-coder in TESTING MODE.
Read harness/agents/harness-coder.md AND harness/skills/harness-testing/SKILL.md.

WHAT WAS BUILT: Read harness/changes/fix/{slug}/coding-report.md.
ORIGINAL CAUSE (for regression test scope): {paste caused_by entries}

Write tests for the fix. Required:
1. A regression test that reproduces the original bug (must FAIL on the
   pre-fix code; PASS on the current code).
2. A test from the original feature's spec (proves the causing feature
   still works — read its requirements.md acceptance criteria).

If a meaningful test requires touching files OUTSIDE the fix's scope (>2
additional files or crossing a layer boundary), append the Test Scope
Signal block to your coding-report.md per harness-coder.md instructions —
do NOT silently expand scope.

Append test results to: harness/changes/fix/{slug}/coding-report.md
```

After sub-agent returns:
```bash
COD="harness/changes/fix/${SLUG}/coding-report.md"
if grep -q "^- TEST_SCOPE_INFLATION: true" "$COD"; then
  # Fire late-escalation prompt — see "Stage 5/6 Late-Escalation Prompt"
  _fire_late_escalation_prompt 5
fi
```

## Stage 6: Test Review

Spawn `harness-reviewer`:

```
You are the harness-reviewer reviewing tests for a fix.
Read harness/agents/harness-reviewer.md.

REVIEW: tests added in coding-report.md at harness/changes/fix/{slug}/.
CAUSAL CONTEXT: this fix is caused by {paste caused_by entries}. Verify the
tests don't regress those original features (read their acceptance criteria).

Check:
- Regression test would have failed on pre-fix code (assertions are meaningful)
- Original feature's acceptance criteria still pass
- No tests are tautological (asserting the fix's masked behaviour instead of intended)

If the fix is correct given its current scope BUT the scope itself is wrong
(symptom-mask, wrong layer, architectural concern), emit verdict
ESCALATION_REQUIRED with the required Escalation Reason block.

Write review to: harness/changes/fix/{slug}/review-record.md
```

After sub-agent returns:
```bash
REV="harness/changes/fix/${SLUG}/review-record.md"
if grep -q '^\*\*Verdict:\*\* ESCALATION_REQUIRED' "$REV"; then
  _fire_late_escalation_prompt 6
fi
```

## Stage 7: Push (with back-link)

Standard push. Then:

> Variables in scope for all Stage 7 snippets: `SLUG` (this fix's slug, no `fix/` prefix), and the per-entry `CAUSING_SLUG` / `CAUSING_ROLE` / `CAUSING_LOOKUP` parsed from each `caused_by:` block in this fix's `requirements.md`. The orchestrator sets these before executing.

### 7.1 Record own commit

Same as `harness-run` Stage 7 — append row to own pipeline-state.md `## Commits` table. Also self-heal the reverse-lookup cache:

```bash
. harness/hooks/lookup-helpers.sh
_cache_append "$(git rev-parse HEAD)" "fix/${SLUG}" "original"
```

### 7.2 Bidirectional back-link

Iterate each entry in this fix's `caused_by:` YAML list (in `requirements.md` frontmatter). Skip entries where:
- `slug` ∈ {`unknown`, `unknown_squash`} — no destination to write
- entry is a `- note:` overflow marker (no `slug` key at all)

For each remaining entry, run the block below with `CAUSING_SLUG`, `CAUSING_ROLE`, `CAUSING_LOOKUP` bound to that entry's fields.

The orchestrator (Claude) reads the YAML, extracts each entry's fields, and executes the snippet per entry. Pseudocode-shape iteration:

```
for entry in parsed_yaml["caused_by"]:
    if "slug" not in entry: continue                       # note: overflow
    if entry["slug"] in ("unknown", "unknown_squash"): continue
    CAUSING_SLUG  = entry["slug"]
    CAUSING_ROLE  = entry["role"]
    CAUSING_LOOKUP = entry["lookup"]
    # then execute the bash block below
```

```bash
CAUSING_STATE="harness/changes/${CAUSING_SLUG}/pipeline-state.md"
[ ! -f "$CAUSING_STATE" ] && continue

# Ensure section exists (schema: Role + Lookup columns)
if ! grep -q "^## Follow-up Fixes" "$CAUSING_STATE"; then
  cat >> "$CAUSING_STATE" << 'EOF'

## Follow-up Fixes
| Fix Slug | Role | Lookup | Reason | Date |
|----------|------|--------|--------|------|
EOF
fi

# Idempotency: own slug + role together (same slug can legitimately appear as primary and call_path in different fixes)
OWN_SLUG="fix/${SLUG}"
if grep -q "| $OWN_SLUG | $CAUSING_ROLE |" "$CAUSING_STATE"; then
  continue
fi

REASON=$(head -1 harness/changes/fix/${SLUG}/requirements.md | sed 's/^# Bug: //')
DATE=$(date -u +%Y-%m-%d)
echo "| $OWN_SLUG | $CAUSING_ROLE | $CAUSING_LOOKUP | $REASON | $DATE |" >> "$CAUSING_STATE"
```

## Escalation Gates

Four gates: predictive (Stage 1), reactive (Stage 3), test-scope (Stage 5), reviewer-flagged (Stage 6).

### Stage 1 Gate (predictive)
After reqs written, parse for:
| Signal | Threshold | Source |
|--------|-----------|--------|
| Files predicted | > 5 | requirements.md "Files likely touched" if present |
| Layers predicted | > 2 | requirements.md "Layers involved" |
| Data model change | any | grep for "schema", "migration", "model change" |
| New external dep | any | grep "depends on", "requires new" |
| Reporter says "needs redesign" | exact phrase | grep |

### Stage 3 Gate (reactive)
After coder returns:
| Signal | Threshold | Source |
|--------|-----------|--------|
| Files modified + created | > 5 | coding-report.md |
| Layers touched | > 2 | coding-report.md |
| Coder reported "scope creep" | any | coding-report.md notes |
| Build fail crossing modules | any | coding-report.md build status |

### Stage 5 Gate (test scope)
If coding-report.md contains:
```
### Test Scope Signal
- TEST_SCOPE_INFLATION: true
```
→ fire late-escalation prompt.

### Stage 6 Gate (reviewer)
If review-record.md `**Verdict:** ESCALATION_REQUIRED` → fire late-escalation prompt with reviewer's Escalation Reason context.

### Stage 1/3 Prompt (clean migration possible)

```
This bug fix is exceeding fix-lane scope:
Tripped signals:
  - {signal 1}: {actual} (threshold {N})
  - ...

Options:
  1. Escalate to /harness-run (recommended) — rename fix/{slug} → feat/{slug}-fix,
     preserve caused_by + add escalated_from, reset Current Stage to 1.
  2. Continue as fix (override) — document override reason; accept risk.
  3. Abort — leave fix/{slug} as-is, Status: ABORTED.
```

Migration mechanics: `mv harness/changes/fix/{slug} → harness/changes/feat/{slug}-fix`;
mutate frontmatter (`type: feat`, `escalated_from: fix/{slug}`); reset Current Stage; hand off via `/harness-run --resume`.

### Stage 5/6 Late-Escalation Prompt

```
{Stage 5: Test scope inflation | Stage 6: Reviewer flagged ESCALATION_REQUIRED}

Code committed at Stage 3: {SHA} ({files})
{Stage 5: Test sub-agent needs {N} additional files in {layers}}
{Stage 6: Reviewer Escalation Reason: {analysis}}

Options:
  1. Revert Stage 3 commit + abort fix
       → git revert {SHA}; Status: ABORTED_LATE
  2. Late-escalate to feat lane (PRESERVE commit)
       → mv fix/{slug} → feat/{slug}-fix; tombstone left at old slot;
         Stage 3 commit stays on branch; reset Current Stage: 1;
         resume via /harness-run --resume
  3. Ship as partial fix + file root-cause feat
       → Continue to Stage 7; Status: PARTIAL_FIX
       → Auto-create harness/changes/feat/{slug}-root-cause/ skeleton with
         filed_from_partial_fix + inherited caused_by_chain
       → User invokes /harness-run feat: ... later
```

#### Tombstone in old fix slot (option 2 migration only)

```bash
mkdir -p "harness/changes/fix/${SLUG}"
cat > "harness/changes/fix/${SLUG}/TOMBSTONE.md" << EOF
# Tombstone: fix/${SLUG} → feat/${NEW_SLUG}

This fix was escalated late (at Stage ${ESCALATED_STAGE}) and migrated to:
**harness/changes/feat/${NEW_SLUG}/**

All artifacts live there now. This file is a forwarding pointer only.

- Escalated at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
- Reason: ${ESCALATION_REASON}
EOF
```

#### PARTIAL_FIX state (option 3)

Frontmatter:
```yaml
---
type: fix
partial: true
partial_reason: |
  {one-line summary of what's masked vs what root cause is}
root_cause_feat: feat/{slug}-root-cause
caused_by: [...]
---
```

pipeline-state.md Status block:
```markdown
## Status
- Current Stage: 7
- Status: PARTIAL_FIX
- Partial Reason: "{summary}"
- Root Cause Feat: feat/{slug}-root-cause
- Root Cause Status: PENDING (last checked: {date})
```

Auto-skeleton at `harness/changes/feat/{slug}-root-cause/` inherits `caused_by` and adds `filed_from_partial_fix: fix/{slug}`. When that feat completes its own Stage 7, it writes back to the partial fix's pipeline-state.md `## Root Cause Addressed By` table (mechanism in `harness-run` Stage 7).

## Completion

When Stage 7 passes:
- Update own `pipeline-state.md` Status: COMPLETE (or PARTIAL_FIX if option 3).
- Summarize: original cause, fix files, regression tests added.
- Report total rounds and any escalation gates tripped (even if user chose to override).
