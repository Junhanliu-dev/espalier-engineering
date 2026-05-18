# Plan: `harness-fix` Lane + Causal Linking + Escalation

> **Status:** Draft for review. Risk/open questions discussed separately after plan approval.
> **Owner:** Zayhan
> **Estimated effort:** ~6.5 hours single-sitting, or 2 focused sessions.
> **Target version:** harness-engineering v0.2.0

---

## 0. Goals & Non-Goals

### Goals
1. Add a slimmer **`/harness-fix`** orchestrator skill — 5 stages instead of 10, optimized for bug fixes (<20 LOC, <3 files, no schema change).
2. Introduce **typed `harness/changes/{type}/{slug}/`** directory layout (`feat/`, `fix/`, `refactor/`, …) — replaces flat `{slug}/`.
3. **Auto-link** every bug fix back to the commit / harness-change that introduced it, via `git blame` + reverse lookup against `harness/changes/*/*/pipeline-state.md`.
4. **Bidirectional reference**: causing change gets a `## Follow-up Fixes` table row pointing at the fix.
5. **Escalation path**: if a bug fix exceeds bug-shape scope mid-pipeline, promote it from fix-lane to full `harness-run` lane, preserving causal link and migration history.
6. **Squash-merge resilience** (decided at init, not at fix-time): during `/harness-engineering` Phase 10, ask user about merge strategy + optionally install post-merge hook. Decision cached in `harness/.merge-hook-decision`. Fix-time reverse lookup reads the cache silently — no mid-flow prompts.
7. **Reverse-lookup cache** (auto-build + manual override, Path F): `harness/.commit-index.tsv` is a self-healing cache that maps SHA → slug in O(1) grep. Auto-built when a scan exceeds 1s threshold; manually triggered via `--build-index` flag; bypassed via `--no-index` for debug. Rebuild script `harness/hooks/rebuild-commit-index.sh` reconstructs from `pipeline-state.md` files anytime. Source of truth stays in pipeline-state.md; cache is regenerable.
8. Update **pre-push gate** + **validation checklist** to understand the new layout.

### Non-Goals
- No de-escalation (full-lane → fix-lane). Once promoted, sunk cost.
- No retroactive backfill of `caused_by` for changes that pre-date this feature.
- No changes to the discovery / generation flow (`/harness-engineering` itself is untouched in templates it emits, beyond adding the new ones).
- No new external tooling. Pure bash + git + grep.

---

## 1. Pre-flight (do these once, before touching any phase)

1. **Branch off main:**
   ```bash
   git checkout -b feat/harness-fix-lane
   ```
2. **Capture baseline:**
   ```bash
   git rev-parse HEAD > /tmp/harness-fix-baseline.sha
   ```
3. **Bump version stub** in `.claude-plugin/plugin.json`:
   - `"version": "0.1.0"` → `"version": "0.2.0-dev"`
   - Same in `.claude-plugin/marketplace.json` (both top-level and inside `plugins[0]`).
   - Bump back to `"0.2.0"` after Phase 8 passes.
4. **Stub plan.md tracking:**
   - This file. Reference from PR description when phases land.

---

## 2. Phase Order & Dependencies

```
Phase 1: Layout migration                  ← foundation, everything depends on this
Phase 2: Stage 7 commit recording          ← independent of fix-lane, useful even for run-lane
Phase 3: harness-fix skill skeleton        ← needs Phase 1 (uses typed paths)
Phase 4: Stage 0 auto-link                 ← needs Phase 2 (reads commits table)
Phase 4.5: Squash-merge resilience         ← needs Phase 4; extends init wiring
Phase 4.6: Reverse-lookup cache (Path F)   ← needs Phase 4; transparent acceleration layer
Phase 5: Bidirectional back-link           ← needs Phase 4 (writes to causing change)
Phase 6: Escalation path                   ← needs Phase 3, 4, 5
Phase 7: Wiring (.claude/ symlinks + opt-in post-merge hook) ← needs Phase 3, 4.5
Phase 8: Validation                        ← runs last, verifies everything
```

If you need to ship partial work: Phase 1 + 2 + 7 alone are a coherent release (typed layout + commit records, no fix lane yet). Phase 3 alone is also shippable (fix lane without linking — degrades to "manual link via --caused-by flag only").

---

## 3. Phase 1 — Typed Layout Migration

### 3.1 Files touched

| File | Lines (approx) | Action |
|------|----------------|--------|
| `skills/harness-engineering/templates/skills/harness-run.md` | 29, 113 | Edit |
| `skills/harness-engineering/hook-templates/pre-push-gate.sh` | 7, 14 | Edit |
| `skills/harness-engineering/references/wiring.md` | 116–134 | Edit (clarify lazy mkdir) |
| `skills/harness-engineering/references/validation.md` | (add row 12) | Edit |
| `skills/harness-engineering/SKILL.md` | 70, 72 | Edit (layout diagram) |

### 3.2 `harness-run.md` edits

**Edit A — session resumption block (around line 27–35).** Find:
```markdown
### Session Resumption

On every invocation, check:
```
ls harness/changes/ | grep -v _template
```

If a directory exists with an in-progress `pipeline-state.md`:
```

Replace with:
```markdown
### Session Resumption

On every invocation, check:
```
find harness/changes -mindepth 3 -maxdepth 3 -name pipeline-state.md
```

If any state file is found with an in-progress stage marker:
```

**Edit B — Stage Execution Protocol state path (around line 113).** Find:
```markdown
Create `harness/changes/{slug}/pipeline-state.md`:
```

Replace with:
```markdown
Parse `{type}` from the requirement prefix:
- `feat: <text>` → type = `feat`
- `fix: <text>` → type = `fix`
- `refactor: <text>` → type = `refactor`
- `docs: <text>` → type = `docs`
- Anything else → type = `feat` (default)

Then derive `{slug}` from the remainder of the requirement (kebab-case, max 60 chars, strip slashes).

Create `harness/changes/{type}/{slug}/pipeline-state.md`:
```

**Edit C — sub-agent prompts (Stages 3-6, around lines 56–110).** Search and replace every occurrence of:
```
harness/changes/{slug}/
```
with:
```
harness/changes/{type}/{slug}/
```

### 3.3 `pre-push-gate.sh` edits

Replace lines 5–18 with:

```bash
CHANGES_DIR="harness/changes"

# Find most recently modified pipeline-state.md across all typed subdirs.
STATE_FILE=$(find "$CHANGES_DIR" -mindepth 3 -maxdepth 3 -name pipeline-state.md \
             -exec stat -f '%m %N' {} + 2>/dev/null \
             | sort -rn | head -1 | cut -d' ' -f2-)

if [ -z "$STATE_FILE" ] || [ ! -f "$STATE_FILE" ]; then
  echo "WARNING: No harness change record found. Pushing without pipeline tracking."
  exit 0
fi
```

Keep lines 21+ (Current Stage check, build/lint/test gates) unchanged.

> **Note:** `stat -f '%m %N'` is BSD/macOS syntax. For GNU stat (Linux CI), use `stat -c '%Y %n'`. Detect OS:
> ```bash
> STAT_FMT=$([ "$(uname)" = "Darwin" ] && echo '-f %m\ %N' || echo '-c %Y\ %n')
> STATE_FILE=$(find "$CHANGES_DIR" -mindepth 3 -maxdepth 3 -name pipeline-state.md \
>              -exec stat $STAT_FMT {} + 2>/dev/null \
>              | sort -rn | head -1 | cut -d' ' -f2-)
> ```

### 3.4 `wiring.md` edits

Section 10.6 — replace the `mkdir -p harness/changes/_template` block with:

```bash
# Ensure template + typed parent dirs exist (lazy — skills create per-slug subdirs)
mkdir -p harness/changes/_template
mkdir -p harness/changes/feat
mkdir -p harness/changes/fix
mkdir -p harness/changes/refactor

# Pipeline-state template (referenced by both harness-run and harness-fix)
cat > harness/changes/_template/pipeline-state.md << 'EOF'
# Pipeline State: {requirement}

## Status
- Current Stage: 0
- Started: {timestamp}
- Last Updated: {timestamp}
- Total Rollbacks: 0
- Review Rounds: req=0/3, code=0/2, test=0/2

## Stage History
| Stage | Status | Timestamp | Notes |
|-------|--------|-----------|-------|
EOF
```

### 3.5 `SKILL.md` (this repo) edits

In the "Output Structure in Target Project" block (around lines 70–73):

Find:
```
│   ├── changes/_template/          # requirements.md, task-breakdown.md, ...
```

Replace with:
```
│   ├── changes/                    # typed: feat/, fix/, refactor/, …
│   │   ├── _template/              # requirements.md, task-breakdown.md, coding-report.md, review-record.md, pipeline-state.md, ci-result.md
│   │   ├── feat/{slug}/            # full pipeline outputs
│   │   ├── fix/{slug}/             # fix-lane outputs (with caused_by frontmatter)
│   │   └── refactor/{slug}/        # (future)
```

### 3.6 Acceptance criteria for Phase 1

- [ ] `/harness-run feat: dummy` lands state in `harness/changes/feat/dummy/pipeline-state.md`.
- [ ] `/harness-run dummy` (no prefix) lands state in `harness/changes/feat/dummy/pipeline-state.md`.
- [ ] `pre-push-gate.sh` finds that state file and reads `Current Stage:` correctly.
- [ ] `find harness/changes -mindepth 3 -maxdepth 3 -name pipeline-state.md` lists it.
- [ ] No legacy `harness/changes/{slug}/pipeline-state.md` (depth 2) is created.

---

## 4. Phase 2 — Stage 7 Commit Recording

### 4.1 Files touched

| File | Lines (approx) | Action |
|------|----------------|--------|
| `skills/harness-engineering/templates/skills/harness-run.md` | Stage 7 section | Edit |
| `skills/harness-engineering/templates/pipeline.md` | Stage 7 block | Edit (add output) |

### 4.2 `harness-run.md` edit

Find the Stage 7 portion of the Stage Execution Protocol (or in `pipeline.md`). After the push success path, add:

```markdown
**Post-push recording (Stage 7):**

After `git push` succeeds:

```bash
SHA=$(git rev-parse HEAD)
FILES=$(git diff-tree --no-commit-id --name-only -r HEAD | tr '\n' ',' | sed 's/,$//')
```

Then update `harness/changes/{type}/{slug}/pipeline-state.md`:

1. If section `## Commits` does NOT already exist, append:
   ```markdown

   ## Commits
   | Stage | SHA | Files |
   |-------|-----|-------|
   | 7 | {SHA} | {FILES} |
   ```

2. If `## Commits` exists, append one row to the table.

3. **Idempotency:** Before appending, grep the file for `| 7 | {SHA} |` — skip if already present (prevents double-record on re-push).
```

### 4.3 `pipeline.md` edit

In Stage 7 block (currently lines 52–58), append to the bullet list:

```markdown
- **Output:** harness/changes/{type}/{slug}/pipeline-state.md (Commits table updated with SHA + files)
```

### 4.4 Acceptance criteria for Phase 2

- [ ] After a real push from `/harness-run feat: foo`, `pipeline-state.md` has a `## Commits` section with one row.
- [ ] Re-running Stage 7 (e.g., amended commit + force-push) does not duplicate the row.
- [ ] SHA in row matches `git rev-parse HEAD`.
- [ ] Files column lists the actual files changed in that commit.

---

## 5. Phase 3 — `harness-fix` Skill (New)

### 5.1 New file

Create `skills/harness-engineering/templates/skills/harness-fix.md`.

### 5.2 Full skeleton

```markdown
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

Skipped: Stage 2 (standalone reqs review — merged into Stage 4 code review), Stage 8 (CI verify — fix lane defers to repo CI hook), Stage 9 (deploy verify — fix lane assumes same deploy as next normal release), Stage 10 (user confirm — bug reporter confirms via test, not separate gate).

## Slug & Path

- Slug derivation: see §5.5 in plan.md. Summary: sanitize bug input → kebab-case ASCII, max 80 chars; `--slug <name>` overrides; collision prompts user (Risk 4 / Option E).
- Path = `harness/changes/fix/{slug}/`
- All files inherit from `harness/changes/_template/`.

## Before Starting

1. Read `harness/pipeline.md` for stage definitions (Stages 3-7 unchanged).
2. Check session resumption:
   ```bash
   find harness/changes/fix -mindepth 2 -maxdepth 2 -name pipeline-state.md
   ```
   Read each, look for `Current Stage:` < 7 (in-progress).
3. If matching slug found, RESUME from current stage.
4. Otherwise, create new `harness/changes/fix/{slug}/`.

## Stage 0: Auto-Link Discovery (NEW)

[Full content in Phase 4 below — too long for skeleton]

## Stage 1: Bug Requirements (slimmer than feat reqs)

Write `harness/changes/fix/{slug}/requirements.md`:

```yaml
---
type: fix
caused_by:           # populated by Stage 0
  - {slug} ({sha})
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

**Escalation check (run after writing reqs):** see Stage 1 Escalation Gate in Phase 6.

## Stage 3: Coding

Spawn sub-agent (same as harness-run Stage 3). Prompt:

```
You are the harness-coder.
Read harness/agents/harness-coder.md for full instructions.

REQUIREMENT: {paste requirement summary from Stage 1}
CAUSED BY: {caused_by list — read those changes' requirements + coding-report + review-record}
TASK: Fix the bug described above. Stay within the file(s) identified.

When done, write your coding report to:
harness/changes/fix/{slug}/coding-report.md
```

**Escalation check (run after sub-agent returns):** see Stage 3 Escalation Gate in Phase 6.

## Stage 4: Code Review

Same as harness-run Stage 4. Spawn `harness-reviewer`. Output to
`harness/changes/fix/{slug}/review-record.md`.

Special check for fix lane: reviewer MUST verify the fix doesn't regress the original feature's acceptance criteria (read from `caused_by` change's `requirements.md`).

## Stage 5: Test Writing

Same as harness-run Stage 5. Tests MUST include:
- One test that reproduces the original bug (would have failed before fix).
- One test from the original feature's spec (proves no regression).

## Stage 6: Test Review

Same as harness-run Stage 6.

## Stage 7: Push (with back-link)

Standard push. Then:

1. Record commit SHA in own `pipeline-state.md` (Phase 2 behavior).
2. **Back-link write** (NEW, see Phase 5): append `## Follow-up Fixes` row to each `caused_by` change's `pipeline-state.md`.

## Completion

When Stage 7 passes:
- Update own `pipeline-state.md` status: COMPLETE.
- Summarize: original cause, fix files, regression tests added.
- Report total rounds and any escalation checks tripped (even if user chose to override).
```

### 5.3 Update `SKILL.md` (this repo) Phase 3 table

Find table around lines 142–148 ("Generate Skills"). Add row:

```markdown
| `harness/skills/harness-fix/SKILL.md`         | `templates/skills/harness-fix.md` |
```

Also add to the file layout block (around line 30):

```markdown
│   │   ├── harness-fix/                 ← NEW: bug-fix lane (5-stage)
│   │   │   └── SKILL.md
```

### 5.4 Update `templates/agent.md` Config Index table

Find the table around lines 13–24. Add row:

```markdown
| Fix       | harness/skills/harness-fix/      | Bug-fix orchestrator     | Via /harness-fix |
```

### 5.5 Slug Derivation (Risk 4 resolution — Option E)

Embedded in `harness-fix.md` skeleton as a dedicated section the skill reads at
invocation time. Drop this block into the harness-fix.md template, between
"Slug & Path" and "Before Starting":

```markdown
## Slug Derivation

Slug is produced by this pipeline. All steps are deterministic except step 7 (override) and step 9 (collision prompt).

### Step 1: Override check
If user passed `--slug <name>`:
  - Validate: must match `^[a-z0-9][a-z0-9-]{0,79}$` (≤ 80 chars, kebab, starts non-hyphen)
  - If valid, skip to step 9 (collision check).
  - If invalid, error and exit with message showing the regex.

### Step 2: Strip type prefix
"fix: foo bar" → "foo bar"
"feat: ignored" → error (wrong skill — harness-fix should only see fix-shape input)

### Step 3: Lowercase
"NPE In Cart" → "npe in cart"

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
  - "修复支付错误" → unidecode: "Xiu Fu Zhi Fu Cuo Wu" → continues to step 5
  - "café crash" → unidecode: "cafe crash"
  - With fallback: "修复支付错误" → "" (continues to step 8 → timestamp fallback)

### Step 5: Replace non-[a-z0-9] runs with single hyphen
"npe in cart" → "npe-in-cart"
"bug at src/payment.ts:42" → "bug-at-src-payment-ts-42"
"v2.3.1 broken" → "v2-3-1-broken"

### Step 6: Trim leading/trailing hyphens
"-rf this is joke-" → "rf-this-is-joke"

### Step 7: Truncate to 80 chars at word boundary
- If ≤ 80, keep as-is.
- If > 80, cut at last hyphen ≤ 80. If no hyphen in first 80 chars, hard-cut at 80.

### Step 8: Empty-result fallback
If empty after sanitization (e.g., all-symbol input or unidecode-stripped CJK), use:
  `fix-{YYYYMMDD-HHMMSS}` (UTC timestamp, e.g., `fix-20260518-143022`)

### Step 9: Reserved-name prefix
If slug ∈ {con, aux, nul, prn, com1..9, lpt1..9} (Windows reserved):
  prefix with "fix-"

### Step 10: Leading-hyphen guard
If starts with hyphen (post-sanitization edge case from step 4): prefix with "x-"

### Step 11: Collision detection + prompt
Check `harness/changes/fix/{slug}/` (and tombstones at `harness/changes/fix/{slug}/TOMBSTONE.md`):

| Existing state | Action |
|----------------|--------|
| No directory | Use slug. Done. |
| Directory exists, Status: IN_PROGRESS | Resume that fix. Announce "Resuming fix/{slug} from Stage {N}". |
| Directory exists, Status: COMPLETE / ABORTED / ABORTED_LATE / ESCALATED / ESCALATED_LATE | **Prompt user** (see prompt below) |
| Directory exists, Status: PARTIAL_FIX | **Prompt user** (see prompt below) |
| Only TOMBSTONE.md exists (legacy migration) | Follow tombstone pointer; ask user "fix/{slug} was migrated to feat/{target}. New fix at fix/{slug}-2, or work on feat/{target} instead?" |

Collision prompt body:

```
Slug collision detected.

Existing: harness/changes/fix/{slug}/ — Status: {EXISTING_STATUS}
{If PARTIAL_FIX: Root cause feat: {root_cause_feat}}
{If COMPLETE: Closed on {date}}

Options:
  1. New fix with suffix — use fix/{slug}-2 (or next available -N)
  2. {Only if Status=PARTIAL_FIX or IN_PROGRESS:} Resume / extend the existing fix
  3. {Only if Status=COMPLETE/ABORTED:} Re-open the existing fix (mark Status: REOPENED, restart from Stage 1)
  4. Custom slug — re-prompt for --slug value
  5. Abort
```

(Re-opening overwrites no data; pipeline-state.md gets a new "Reopened at" row.)

### Step 12: Final validation
- Confirm slug matches `^[a-z0-9][a-z0-9-]{0,79}$` one more time.
- Confirm `harness/changes/fix/{slug}/` is now creatable (does not exist OR was user-confirmed for reuse).
```

### 5.6 Acceptance criteria for Phase 3

- [ ] `templates/skills/harness-fix.md` exists with frontmatter and 5-stage structure.
- [ ] `name:` in frontmatter equals `harness-fix` (matches expected folder name).
- [ ] Skeleton references `harness/changes/fix/{slug}/` consistently.
- [ ] Skeleton includes Slug Derivation section (§5.5) with all 12 steps.
- [ ] No copy-paste residue referencing flat `{slug}/` paths.
- [ ] SKILL.md Phase 3 table updated.
- [ ] (Risk 4) `--slug <name>` flag validated against `^[a-z0-9][a-z0-9-]{0,79}$`.
- [ ] (Risk 4) Unicode input transliterated via unidecode; falls back to ASCII-strip without crashing.
- [ ] (Risk 4) 80-char truncation cuts at last hyphen ≤ 80, or hard-cuts if no hyphen.
- [ ] (Risk 4) Empty-result input falls back to `fix-{timestamp}` slug.
- [ ] (Risk 4) Reserved Windows names (con, aux, nul, prn, com1-9, lpt1-9) get `fix-` prefix.
- [ ] (Risk 4) Collision with IN_PROGRESS → silent resume; collision with terminal Status → prompt user with 5 options.
- [ ] (Risk 4) Tombstone-only directory → forwarding prompt.
- [ ] (Risk 4) Reopen path: marks `Status: REOPENED`, appends "Reopened at" row to pipeline-state.md.

---

## 6. Phase 4 — Stage 0 Auto-Link

### 6.1 File touched

`skills/harness-engineering/templates/skills/harness-fix.md` — Stage 0 section.

### 6.2 Full Stage 0 spec (drop into harness-fix.md)

```markdown
## Stage 0: Auto-Link Discovery

Goal: identify the harness change (and commit) that introduced the bug, so Stage 1+
agents have prior-change context.

### 0.1 Parse user input for a bug anchor

Priority order (try each until one succeeds):

| Priority | Source | Example | Extracts |
|----------|--------|---------|----------|
| 1 | Explicit `--caused-by <slug>` flag in invocation | `/harness-fix --caused-by feat/bulk-export NPE...` | slug directly, skip blame |
| 2 | `file:line` pattern in bug text | `src/payment.ts:42` | file, line |
| 3 | Stack trace block | `at handler (src/auth.ts:88:14)` | list of file:line frames |
| 4 | Bare file path | `bug in src/payment.ts` | file only |
| 5 | Symbol name | `bug in processPayment function` | symbol → grep first match → file:line |
| 6 | No anchor at all | "checkout is broken" | trigger user prompt |

### 0.2 Resolution per priority

**Priority 1 (explicit flag):**
- Trust the flag. Set `caused_by = [<slug>]`. Skip steps 0.3–0.5.

**Priorities 2-5 (derive file:line, then blame):**

```bash
# Run blame on the discovered file:line
SHA=$(git blame -w -C -L {LINE},{LINE} {FILE} 2>/dev/null | awk 'NR==1{print $1}')

# Validate SHA isn't all zeros (uncommitted line)
if [ -z "$SHA" ] || [ "$SHA" = "0000000000000000000000000000000000000000" ]; then
  SHA=""
fi
```

For **priority 5 (symbol → grep):**

```bash
SYMBOL="processPayment"  # extracted from bug text
HIT=$(git grep -n "$SYMBOL" -- ':!harness/' ':!tests/' 2>/dev/null | head -1)
# HIT format: path/to/file.ts:42:  function processPayment(...) {
FILE=$(echo "$HIT" | cut -d: -f1)
LINE=$(echo "$HIT" | cut -d: -f2)
# Then proceed with blame above.
```

For **priority 3 (stack trace):** blame each frame, collect SHAs, dedupe. Multiple
SHAs → multiple `caused_by` entries.

**Priority 6 (no anchor):**
Prompt user via AskUserQuestion:

```
Couldn't determine where this bug lives. Choose:
  1. Provide --caused-by <slug>     (you know which feature)
  2. Skip linking, just fix         (lose prior-change context)
  3. Run /harness-bisect first      (find breaking commit via test)
  4. Abort                          (give me more info first)
```

If user picks 2, set `caused_by = []` and continue. If 4, abort skill.

### 0.3 Reverse lookup SHA → harness change slug

Once SHA(s) collected (in stack-trace order — innermost first), run the **tiered
lookup chain**. The mode is governed by `harness/.merge-hook-decision` (written
at init time by Phase 4.5). Build per-entry records carrying both `role` and
`lookup` fields (see §0.5 frontmatter shape).

```bash
DECISION=$(cat harness/.merge-hook-decision 2>/dev/null || echo "ask-later")

# Build entries in order. Index 0 = primary (innermost frame), rest = call_path.
declare -a ENTRIES_SLUG ENTRIES_SHA ENTRIES_ROLE ENTRIES_LOOKUP

# Cap fan-out at 5 — record overflow as a note entry.
TOTAL_FRAMES=${#SHAS[@]}
CAP=5
if [ "$TOTAL_FRAMES" -gt "$CAP" ]; then
  SHAS=("${SHAS[@]:0:$CAP}")
  OVERFLOW_NOTE="$((TOTAL_FRAMES - CAP)) additional frames not linked (cap reached)"
fi

for IDX in "${!SHAS[@]}"; do
  SHA="${SHAS[$IDX]}"
  ROLE=$([ "$IDX" = "0" ] && echo "primary" || echo "call_path")
  # --- Layer 0: cache hit (Phase 4.6 — fast path, always tried first unless --no-index) ---
  if [ "$NO_INDEX" != "yes" ] && [ -f "harness/.commit-index.tsv" ]; then
    CACHE_HIT=$(grep "^$SHA	" harness/.commit-index.tsv 2>/dev/null | head -1)
    if [ -n "$CACHE_HIT" ]; then
      SLUG=$(echo "$CACHE_HIT" | cut -f2)
      KIND=$(echo "$CACHE_HIT" | cut -f3)   # "original" or "squashed_to"
      LOOKUP=$([ "$KIND" = "squashed_to" ] && echo "squash_hook" || echo "exact")
      _push_entry "$SLUG" "$SHA" "$ROLE" "$LOOKUP"
      continue
    fi
  fi

  # --- Layer 1: exact SHA match (scan; self-heals cache on hit) ---
  SCAN_START=$(date +%s%N 2>/dev/null || date +%s)
  SLUG=$(grep -lr "$SHA" harness/changes/*/*/pipeline-state.md 2>/dev/null \
         | head -1 \
         | sed 's|harness/changes/||; s|/pipeline-state.md||')
  _maybe_warn_slow_scan "$SCAN_START"   # Phase 4.6 §6.6.4

  if [ -n "$SLUG" ]; then
    _push_entry "$SLUG" "$SHA" "$ROLE" "exact"
    _cache_append "$SHA" "$SLUG" "original"   # self-heal
    continue
  fi

  # --- Layer 2: hook-recorded squash mapping (if hook installed; self-heals cache) ---
  SCAN_START=$(date +%s%N 2>/dev/null || date +%s)
  SLUG=$(grep -lr "squashed_to: $SHA" harness/changes/*/*/pipeline-state.md 2>/dev/null \
         | head -1 \
         | sed 's|harness/changes/||; s|/pipeline-state.md||')
  _maybe_warn_slow_scan "$SCAN_START"

  if [ -n "$SLUG" ]; then
    _push_entry "$SLUG" "$SHA" "$ROLE" "squash_hook"
    _cache_append "$SHA" "$SLUG" "squashed_to"   # self-heal
    continue
  fi

  # --- Layer 3: dispatch based on cached decision ---
  case "$DECISION" in
    installed)
      SLUG=$(_fuzzy_file_overlap_match "$SHA")
      if [ -n "$SLUG" ]; then
        _push_entry "$SLUG" "$SHA" "$ROLE" "fuzzy_after_hook_miss"
      else
        _push_entry "unknown_squash" "$SHA" "$ROLE" "unknown"
      fi
      ;;
    fuzzy-allowed)
      SLUG=$(_fuzzy_file_overlap_match "$SHA")
      if [ -n "$SLUG" ]; then
        _push_entry "$SLUG" "$SHA" "$ROLE" "fuzzy"
      else
        _push_entry "unknown_squash" "$SHA" "$ROLE" "unknown"
      fi
      ;;
    skip-only|never-ask)
      _push_entry "unknown_squash" "$SHA" "$ROLE" "skipped"
      ;;
    not-needed)
      _push_entry "unknown" "$SHA" "$ROLE" "unknown"
      ;;
    ask-later|"")
      _prompt_user_for_merge_decision
      DECISION=$(cat harness/.merge-hook-decision)
      # Re-loop this SHA with new decision (bounded — prompt writes a terminal value).
      continue
      ;;
  esac
done

# --- Dedupe by slug: primary wins over call_path. ---
_dedupe_entries_preserve_primary

# --- Append overflow note if cap reached. ---
[ -n "$OVERFLOW_NOTE" ] && _push_note_entry "$OVERFLOW_NOTE"
```

Helpers (`_push_entry`, `_push_note_entry`, `_dedupe_entries_preserve_primary`,
`_fuzzy_file_overlap_match`, `_prompt_user_for_merge_decision`) live in
`harness/hooks/lookup-helpers.sh` and are sourced at Stage 0 entry.

Final `caused_by` list is then serialized into requirements.md frontmatter using
the per-entry shape from §0.5.

### 0.4 Multi-cause expansion, ordering, cap (resolves Risk 2)

When the anchor is a **stack trace**, blame each frame and produce one `caused_by`
entry per frame. Rules:

1. **Order = stack-trace order.** Innermost frame (the actual throw site) is index 0
   and gets `role: primary`. All other frames get `role: call_path`.
2. **Fan-out cap = 5 entries.** If the trace has more, take top 5 (innermost
   primary + next 4 frames). Append a marker entry:
   ```yaml
   - note: "{N} additional frames not linked (cap reached)"
   ```
3. **Dedupe by slug.** If two frames blame to the same change, keep the one with
   the more inward role (primary wins over call_path) and drop the duplicate.
4. **No transitive walk.** `feat/X → fix/A → fix/B` does NOT cause `feat/X` to
   list `fix/B`. Only direct cause is recorded. Audit walk is the consumer's job.
5. **Single-anchor inputs** (file:line, --caused-by, symbol-grep) always produce
   exactly one entry, `role: primary`.

### 0.5 Per-entry frontmatter shape

Two orthogonal axes — keep them as separate per-entry fields:

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
  - slug: feat/api
    sha: 789xyz
    role: call_path
    lookup: fuzzy
  - note: "2 additional frames not linked (cap reached)"
---
```

Field meanings:

| Field | Values | Meaning |
|-------|--------|---------|
| `slug` | `{type}/{slug}` or `unknown_squash` or `unknown` | Causing change identifier |
| `sha` | git SHA | The commit blame returned |
| `role` | `primary` \| `call_path` | Stack-trace position (Option B) |
| `lookup` | `exact` \| `squash_hook` \| `fuzzy` \| `fuzzy_after_hook_miss` \| `unknown` \| `skipped` | Which reverse-lookup layer succeeded |

Use these fields in back-link writes (Phase 5) and audit queries.

### 0.6 Write caused_by into requirements.md

Inject frontmatter:

```yaml
---
type: fix
caused_by:
  - feat/bulk-export-endpoint (abc1234)
  - feat/payment-retry (def5678)
---
```

If `CAUSED_BY` array is empty (priority 6 → skip linking):

```yaml
---
type: fix
caused_by: []
caused_by_skipped: true
caused_by_skip_reason: "User chose to skip linking — no file anchor in bug report"
---
```

### 0.7 Load linked context for Stage 1

For each non-`unknown` entry in `caused_by`, before invoking Stage 1 sub-agent, the
orchestrator reads (and includes in Stage 1 agent prompt):

- `harness/changes/{slug}/requirements.md` — original intent
- `harness/changes/{slug}/coding-report.md` — what shipped
- `harness/changes/{slug}/review-record.md` — predicted concerns (especially dismissed P2/P3)

**Token budget:** if combined linked context > 8K tokens, summarize each linked change to
its acceptance-criteria list + open P2/P3 findings only. Full files available via Read
on demand during Stage 3.

### 0.8 Record Stage 0 outcome in pipeline-state.md

Append to Stage History:

```markdown
| 0 | PASSED | {ISO timestamp} | Auto-linked to {N} change(s): {list}. Anchor: {file:line | stack | flag | symbol | skipped} |
```
```

### 6.3 Acceptance criteria for Phase 4

- [ ] `/harness-fix NPE at src/payment.ts:42` writes `caused_by` frontmatter with at least one entry (single-anchor → exactly one entry, `role: primary`).
- [ ] `/harness-fix --caused-by feat/foo "broken"` skips blame, sets `caused_by` with one entry `{slug: feat/foo, role: primary, lookup: exact}`.
- [ ] `/harness-fix "checkout is slow"` (no anchor) triggers user prompt (or routes via cached decision).
- [ ] Stack trace input produces one entry per frame in stack-trace order: index 0 = `role: primary`, all others = `role: call_path`.
- [ ] Fan-out cap: stack trace with >5 frames truncates to top 5 + appends `- note: "{N} additional frames not linked (cap reached)"`.
- [ ] Dedupe: if two frames blame the same slug, single entry retained — `primary` wins over `call_path`.
- [ ] No transitive walk: `fix/A` caused_by `fix/B` does NOT cause `fix/A` to inherit `fix/B`'s causes.
- [ ] Per-entry `lookup` field reflects which layer succeeded: `exact` | `squash_hook` | `fuzzy` | `fuzzy_after_hook_miss` | `unknown` | `skipped`.
- [ ] Linked context appears in Stage 1 sub-agent prompt — primary causes loaded fully, call_path causes summarized to acceptance-criteria + open P2/P3 only.
- [ ] Stage 0 row appended to pipeline-state.md with anchor type + N causes + cap-hit flag.
- [ ] Decision file `harness/.merge-hook-decision` read silently (no prompt) when value ∈ {installed, fuzzy-allowed, skip-only, never-ask, not-needed}.

---

## 6.5. Phase 4.5 — Squash-Merge Resilience

> Resolution of **Risk #1** (squash-merge SHA drift).
> Design principle (cached preference [[feedback-prompt-timing]]):
> **decide at init, cache, never interrupt fix.**

### 6.5.1 Decision states

`harness/.merge-hook-decision` contains exactly one of:

| Value | Meaning | Set when |
|-------|---------|----------|
| `not-needed` | Repo uses rebase or merge-commit; SHA always exact | User picked this at init |
| `installed` | Post-merge hook installed; will record `squashed_to:` mappings | User picked this at init (squash repo) |
| `fuzzy-allowed` | No hook; allow fuzzy file-overlap fallback at fix-time | User picked this at init |
| `skip-only` | No hook, no fuzzy; just mark `unknown_squash` | User picked this at init |
| `never-ask` | Same as skip-only, silent forever | User picked this at init |
| `ask-later` | User deferred; prompt at first fix-time | User skipped init prompt, OR file absent |

### 6.5.2 New file emitted by Phase 7 wiring

`harness/.merge-hook-decision` — single-line text file. Created by Phase 7 (wiring) based on the prompt below. Survives in git (not in .gitignore) so teammates inherit the decision.

### 6.5.3 Init-time prompt (during `/harness-engineering` Phase 10)

Add to `skills/harness-engineering/references/wiring.md` (new section 10.8 — see Phase 7 edits below). Use AskUserQuestion at end of wiring flow:

```
Question: How does this repo merge PRs?

Options:
  1. Rebase-merge or true merge-commit (default for many teams)
       → Original commit SHAs preserved on main
       → `caused_by` auto-link will work exactly
       → DECISION = not-needed
       
  2. Squash-merge (GitHub default)
       → Branch commits collapsed into one new commit on main
       → SHAs recorded by harness become orphan post-merge
       → Need additional handling. Follow-up question follows.
       
  3. Mixed / unknown / decide later
       → Defer; harness will prompt at first /harness-fix
       → DECISION = ask-later
```

If user picks 2 (squash):

```
Question: For squash-merge, how should harness handle SHA drift?

Options:
  1. Install post-merge git hook (recommended)
       → Writes .git/hooks/post-merge (~30 lines bash, harness-signed)
       → After each merge, records `squashed_to: <new-sha>` in matching change
       → Reverse lookup at fix-time is exact and silent
       → DECISION = installed
       
  2. Allow fuzzy file-overlap match at fix-time
       → No hook, no merge-time recording
       → At fix-time, when SHA misses, harness compares squash commit's files
         against Commits tables across all changes; best ≥50% overlap wins
       → Marked `caused_by_confidence: fuzzy`
       → DECISION = fuzzy-allowed
       
  3. Skip linking when SHA misses
       → Safest, no false-positive risk, loses prior-change context
       → Marked `caused_by: unknown_squash (<sha>)`
       → DECISION = skip-only
       
  4. Never ask, always skip
       → Same as 3 but silent. No future prompts in this repo.
       → DECISION = never-ask
```

Write chosen value to `harness/.merge-hook-decision`. If option 1, also install hook (script body below).

### 6.5.4 Fix-time fallback prompt (only fires when DECISION = ask-later)

`_prompt_user_for_merge_decision` (called from Phase 4 §0.3):

```
Heads up — first fix in this repo. Need to decide one thing.

This repo's merge strategy affects bug-to-commit traceability.

Options:  (same 4 options as 6.5.3 squash branch + a 5th for non-squash)
  ...
  5. This repo uses rebase or merge-commit, not squash
       → DECISION = not-needed
```

After user picks, write `harness/.merge-hook-decision` and continue Stage 0 lookup with the new decision.

### 6.5.5 Post-merge hook body (installed when DECISION = installed)

Path: `.git/hooks/post-merge` (or `.husky/post-merge` if husky detected).

Template lives in this repo at `skills/harness-engineering/hook-templates/post-merge-backlink.sh`:

```bash
#!/bin/bash
# HARNESS_BACKLINK_HOOK v1
# Installed by harness-engineering. Records squash-merge SHA mappings
# so /harness-fix can find the source change at lookup time.
# Safe to delete to disable; safe to re-install (idempotent).

MERGED_SHA=$(git rev-parse HEAD)
PARENT_COUNT=$(git log -1 --pretty=%P | wc -w | tr -d ' ')
MSG=$(git log -1 --pretty=%s)

# Squash heuristic: exactly one parent + PR-style message
[ "$PARENT_COUNT" = "1" ] || exit 0
echo "$MSG" | grep -qE '(Merge pull request #[0-9]+|\(#[0-9]+\)$)' || exit 0

# Files touched by the squash commit
FILES=$(git diff-tree --no-commit-id --name-only -r HEAD)
[ -z "$FILES" ] && exit 0

# Find best-match source change by file-name overlap
BEST_STATE=""
BEST_COUNT=0
NOW=$(date +%s)
for state in harness/changes/*/*/pipeline-state.md; do
  [ -f "$state" ] || continue
  # Skip stale (>30 days untouched) to avoid linking unrelated old work
  if [ "$(uname)" = "Darwin" ]; then
    MTIME=$(stat -f %m "$state" 2>/dev/null)
  else
    MTIME=$(stat -c %Y "$state" 2>/dev/null)
  fi
  AGE_DAYS=$(( (NOW - MTIME) / 86400 ))
  [ "$AGE_DAYS" -gt 30 ] && continue
  
  COUNT=0
  for f in $FILES; do
    grep -qF "$f" "$state" 2>/dev/null && COUNT=$((COUNT + 1))
  done
  if [ "$COUNT" -gt "$BEST_COUNT" ]; then
    BEST_COUNT=$COUNT
    BEST_STATE=$state
  fi
done

# Threshold: best match must overlap ≥50% of squash's files
TOTAL_FILES=$(echo "$FILES" | wc -l | tr -d ' ')
THRESHOLD=$(( (TOTAL_FILES + 1) / 2 ))   # ceil(TOTAL/2)
{ [ "$BEST_COUNT" -ge "$THRESHOLD" ] && [ -n "$BEST_STATE" ]; } || exit 0

# Idempotent append
if ! grep -qF "squashed_to: $MERGED_SHA" "$BEST_STATE"; then
  if ! grep -q "^## Squash Merges" "$BEST_STATE"; then
    cat >> "$BEST_STATE" << EOF

## Squash Merges
| Squashed Into | Date | File Overlap |
|---------------|------|--------------|
EOF
  fi
  echo "| squashed_to: $MERGED_SHA | $(date -u +%Y-%m-%d) | ${BEST_COUNT}/${TOTAL_FILES} files |" >> "$BEST_STATE"
fi

exit 0
```

### 6.5.6 Fuzzy lookup function (used at fix-time, DECISION ∈ {fuzzy-allowed, installed})

`_fuzzy_file_overlap_match <sha>` — same logic as hook body's matching loop, but
runs at fix-time on a candidate squash SHA. Returns slug (or empty string).
Slug format: `feat/foo` or `fix/bar`.

Implementation lives in `harness/hooks/lookup-helpers.sh` (new file emitted at wiring).
Sourced by harness-fix skill's Stage 0 logic.

### 6.5.7 Hook install/uninstall logic

Install (Phase 7 wiring runs this when DECISION=installed):

```bash
HOOK_SRC="$(pwd)/skills/harness-engineering/hook-templates/post-merge-backlink.sh"
# Path differs between repo source vs installed plugin — wiring resolves it dynamically
HOOK_DST=".git/hooks/post-merge"

if [ -f "$HOOK_DST" ]; then
  # Pre-existing hook. Don't clobber. Append harness section if not present.
  if ! grep -q "HARNESS_BACKLINK_HOOK" "$HOOK_DST"; then
    echo "" >> "$HOOK_DST"
    cat "$HOOK_SRC" >> "$HOOK_DST"
    echo "  → Appended harness hook to existing $HOOK_DST"
  else
    echo "  → Harness hook already present in $HOOK_DST. Skipping."
  fi
else
  cp "$HOOK_SRC" "$HOOK_DST"
  chmod +x "$HOOK_DST"
  echo "  → Installed $HOOK_DST"
fi
```

Uninstall (manual): user deletes the HARNESS_BACKLINK_HOOK block from `.git/hooks/post-merge` (or the whole file if it's harness-only). No automated uninstaller in v0.2.0.

### 6.5.8 Husky compatibility

If `.husky/` directory exists, install to `.husky/post-merge` instead (husky manages hooks via that dir). Detection:

```bash
if [ -d ".husky" ] && [ -f ".husky/install.mjs" -o -f ".husky/_/husky.sh" ]; then
  HOOK_DST=".husky/post-merge"
else
  HOOK_DST=".git/hooks/post-merge"
fi
```

### 6.5.9 Acceptance criteria for Phase 4.5

- [ ] `/harness-engineering` Phase 10 prompts user about merge strategy at end of wiring.
- [ ] Choosing "rebase/merge-commit" writes `harness/.merge-hook-decision = not-needed`, no hook installed.
- [ ] Choosing "squash → install hook" writes decision = installed AND `.git/hooks/post-merge` exists with HARNESS_BACKLINK_HOOK signature.
- [ ] Choosing "squash → fuzzy" writes decision = fuzzy-allowed, no hook.
- [ ] Choosing "squash → skip / never-ask" writes corresponding decision, no hook.
- [ ] Choosing "defer" writes decision = ask-later, no hook.
- [ ] Hook is idempotent: re-running wiring with same choice does not duplicate hook content.
- [ ] Hook detects squash commits correctly (1 parent + PR message pattern) and ignores true merges.
- [ ] Hook appends `squashed_to:` row to matching pipeline-state.md when file overlap ≥ 50%.
- [ ] `/harness-fix` Stage 0 reads decision file silently; never prompts when decision ∈ {not-needed, installed, fuzzy-allowed, skip-only, never-ask}.
- [ ] `/harness-fix` Stage 0 prompts only when decision = ask-later, and only ONCE per repo (subsequent invocations read the now-written file).
- [ ] Husky-using repo installs hook to `.husky/post-merge`.
- [ ] Fuzzy lookup function returns slug on ≥50% overlap, empty otherwise.
- [ ] `caused_by_confidence` value reflects which layer succeeded: exact | squash_hook | fuzzy | fuzzy_after_hook_miss | unknown | skipped.

---

## 6.6. Phase 4.6 — Reverse-Lookup Cache (Path F)

> Resolution of **Risk #5** (scan-based lookup bottleneck at scale).
> Strategy: zero infrastructure for small repos, auto-build at 1s scan threshold,
> manual override via flags, self-heal on misses, rebuild script as escape hatch.

### 6.6.1 Cache file format

`harness/.commit-index.tsv` — append-only TSV. Tab-separated, one row per (SHA, slug, kind):

```
abc1234	feat/bulk-export-endpoint	original	2026-05-15T10:00:00Z
def5678	feat/payment-retry	original	2026-05-16T14:22:11Z
xyz9876	feat/bulk-export-endpoint	squashed_to	2026-05-18T09:30:00Z
fed4321	fix/npe-payment-cart	original	2026-05-18T11:05:00Z
```

Columns:

| # | Field | Notes |
|---|-------|-------|
| 1 | SHA | git commit SHA (7-40 chars). Lookup key. |
| 2 | slug | `{type}/{slug}` e.g., `feat/bulk-export-endpoint` |
| 3 | kind | `original` (Stage 7 push) \| `squashed_to` (squash-merge mapping) |
| 4 | timestamp | ISO 8601 UTC. Insertion time. |

Same SHA can appear in multiple rows (e.g., original + squashed_to for the same change). Lookup uses `head -1` to take first match.

Source of truth stays in `pipeline-state.md` Commits + Squash Merges tables. Cache is regenerable.

### 6.6.2 Cache life cycle (when written, when read)

**Written:**
- Stage 7 push (`harness-run` AND `harness-fix`) — appends `original` row right after updating own `pipeline-state.md` Commits table.
- Post-merge hook (`harness/hooks/post-merge-backlink.sh`) — appends `squashed_to` row after writing to causing change's pipeline-state.md.
- Self-heal at fix-time — Layer 1/2 scan in §0.3 appends row on hit.
- Rebuild script (§6.6.5) — overwrites whole file.

**Read:**
- Stage 0 Layer 0 (§0.3 of Phase 4) — checked before exact-grep scan. Hit → return. Miss → fall through to scan.

**NOT written for:**
- `unknown` / `unknown_squash` outcomes (no slug to cache).
- Fuzzy/skipped outcomes (low-confidence, don't want to pollute exact-match cache).

### 6.6.3 Helper functions (in `harness/hooks/lookup-helpers.sh`)

```bash
# Append one row to cache, idempotent (skip if SHA+kind already present).
_cache_append() {
  local SHA="$1" SLUG="$2" KIND="$3"
  local CACHE="harness/.commit-index.tsv"
  [ -z "$SHA" ] || [ -z "$SLUG" ] && return 0
  
  # Create cache lazily on first write
  [ ! -f "$CACHE" ] && touch "$CACHE"
  
  # Idempotency: SHA + kind tuple
  grep -qE "^${SHA}\t[^\t]+\t${KIND}\t" "$CACHE" 2>/dev/null && return 0
  
  printf '%s\t%s\t%s\t%s\n' "$SHA" "$SLUG" "$KIND" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$CACHE"
}

# Warn (and maybe auto-build) if scan exceeded threshold.
# Auto-build triggers on first cold scan > 1s when cache doesn't exist yet.
_maybe_warn_slow_scan() {
  local START_NS="$1"
  local END_NS=$(date +%s%N 2>/dev/null || date +%s)
  local NS_PER_SEC=1000000000
  
  # macOS date doesn't support %N; values look like "%N" literal. Fall back to second resolution.
  case "$START_NS" in *N*) START_NS=$(echo "$START_NS" | sed 's/[^0-9]//g'); NS_PER_SEC=1 ;; esac
  case "$END_NS" in *N*) END_NS=$(echo "$END_NS" | sed 's/[^0-9]//g'); NS_PER_SEC=1 ;; esac
  
  local DURATION_MS=$(( (END_NS - START_NS) * 1000 / NS_PER_SEC ))
  local THRESHOLD_MS=1000
  
  [ "$DURATION_MS" -lt "$THRESHOLD_MS" ] && return 0
  
  local CHANGE_COUNT=$(find harness/changes -mindepth 3 -maxdepth 3 -name pipeline-state.md 2>/dev/null | wc -l | tr -d ' ')
  
  echo "WARNING: reverse-lookup scan took ${DURATION_MS}ms across ${CHANGE_COUNT} changes." >&2
  
  # Auto-build cache on first cold scan exceeding threshold
  if [ ! -f "harness/.commit-index.tsv" ]; then
    echo "Building reverse-lookup cache automatically (one-time)..." >&2
    bash harness/hooks/rebuild-commit-index.sh
    echo "Cache built. Future lookups will be O(1)." >&2
  else
    echo "Cache exists but scan still triggered (likely missed entries). Consider:" >&2
    echo "  /harness-fix --rebuild-index   # full rebuild from pipeline-state.md files" >&2
  fi
}
```

### 6.6.4 Threshold rationale + override

Default threshold: **1 second per scan**. Chosen because:
- Below 1s = imperceptible delay in skill output, no user complaint.
- Above 1s = noticeable per-frame (stack trace × 5 = 5s+ multiplier).
- Conservative enough to fire WELL BEFORE pain becomes serious (typical pain starts ~5s).

Override via env var:

```bash
HARNESS_CACHE_THRESHOLD_MS=500 /harness-fix ...   # tighter
HARNESS_CACHE_THRESHOLD_MS=0   /harness-fix ...   # never warn / auto-build
HARNESS_CACHE_THRESHOLD_MS=999999 /harness-fix ... # effectively never trigger
```

Skill reads env at Stage 0 entry; threshold falls back to 1000ms if unset.

### 6.6.5 Rebuild script (`harness/hooks/rebuild-commit-index.sh`)

NEW file emitted by Phase 7 wiring. Always present, runnable anytime. Idempotent (overwrites).

```bash
#!/bin/bash
# Reconstruct harness/.commit-index.tsv from pipeline-state.md files.
# Safe to run anytime — overwrites. Source of truth lives in pipeline-state.md.

set -e
INDEX="harness/.commit-index.tsv"
TMP="${INDEX}.tmp.$$"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
COUNT=0

# Extract from Commits tables (Stage 7 records)
find harness/changes -mindepth 3 -maxdepth 3 -name pipeline-state.md | while read f; do
  SLUG=$(echo "$f" | sed 's|harness/changes/||; s|/pipeline-state.md||')
  
  # Walk lines after "## Commits" header until next "## " header
  awk -v slug="$SLUG" -v now="$NOW" '
    /^## Commits/ {in_commits=1; next}
    /^## [^C]/ {in_commits=0}
    in_commits && /^\| *[0-9]+ *\|/ {
      # Markdown row: | stage | sha | files |
      split($0, cols, "|")
      sha = cols[3]; gsub(/^ +| +$/, "", sha)
      if (length(sha) >= 7) print sha "\t" slug "\toriginal\t" now
    }
    /^## Squash Merges/ {in_squash=1; next}
    in_squash && /squashed_to:/ {
      match($0, /[a-f0-9]{7,40}/)
      if (RSTART) {
        sha = substr($0, RSTART, RLENGTH)
        print sha "\t" slug "\tsquashed_to\t" now
      }
    }
  ' "$f"
done | sort -u > "$TMP"

mv "$TMP" "$INDEX"
COUNT=$(wc -l < "$INDEX" | tr -d ' ')
echo "Rebuilt $INDEX: $COUNT entries"
```

### 6.6.6 Skill flags (harness-fix.md)

Add to skill's argument parsing (at top of harness-fix.md skeleton):

```markdown
## Flags

| Flag | Effect |
|------|--------|
| `--slug <name>` | Override auto-derived slug (see §5.5) |
| `--caused-by <slug>` | Skip blame, explicit causal link (Phase 4) |
| `--build-index` | Run harness/hooks/rebuild-commit-index.sh, then continue normally |
| `--rebuild-index` | Delete harness/.commit-index.tsv, then run rebuild script (forces fresh state) |
| `--no-index` | Bypass cache for this invocation only (debug; falls straight to scan) |
```

`--build-index` and `--rebuild-index` run the rebuild then continue with normal fix flow.

### 6.6.7 git tracking

```bash
# harness/.commit-index.tsv goes in .gitignore — it's a cache, not source of truth.
# Teammates rebuild on demand via /harness-fix --build-index or hitting the auto-build threshold.
echo "harness/.commit-index.tsv" >> .gitignore
```

Rationale: avoids merge conflicts on every fix push, avoids burdening PR diffs with cache churn. Cost = each teammate's first slow scan auto-builds their own cache. Acceptable.

Phase 7 wiring appends this line if `.gitignore` doesn't already have it.

### 6.6.8 Acceptance criteria for Phase 4.6

- [ ] `harness/hooks/rebuild-commit-index.sh` exists, executable, emitted by Phase 7 wiring.
- [ ] Rebuild script reads all `pipeline-state.md` Commits + Squash Merges tables, writes `harness/.commit-index.tsv` with sorted unique rows.
- [ ] Stage 7 push (run AND fix lanes) appends `original` row to cache after updating Commits table.
- [ ] Post-merge hook appends `squashed_to` row to cache after updating causing change's pipeline-state.md.
- [ ] Stage 0 Layer 0 reads cache first; cache hit → no scan; cache miss → falls through to Layer 1.
- [ ] Layer 1/2 scan self-heals: hit → `_cache_append` writes the discovered row.
- [ ] `_cache_append` is idempotent — same (SHA, kind) tuple not duplicated.
- [ ] `_maybe_warn_slow_scan` warns on scan > 1s; auto-builds cache on first cold trigger.
- [ ] `HARNESS_CACHE_THRESHOLD_MS` env var overrides threshold.
- [ ] `--no-index` flag bypasses cache lookup; `--build-index` triggers rebuild then continues; `--rebuild-index` deletes + rebuilds.
- [ ] `harness/.commit-index.tsv` added to `.gitignore` by Phase 7 wiring.
- [ ] Source of truth still lives in `pipeline-state.md` — deleting cache loses no data, only speed.
- [ ] Self-healed entries match what rebuild script would produce (sort + uniq agree).

---

## 7. Phase 5 — Bidirectional Back-Link

### 7.1 File touched

`skills/harness-engineering/templates/skills/harness-fix.md` — Stage 7 section.

### 7.2 Stage 7 Addendum spec

Add after Phase 2's commit-recording block:

```markdown
### Stage 7 Addendum: Bidirectional Back-Link

After own pipeline-state.md gets the new Commits row:

Walk each `caused_by` entry. Skip entries where:
- `slug` ∈ {`unknown`, `unknown_squash`} — no destination to write to
- entry is a `note:` overflow marker — not a real cause

For every remaining entry, write a row into the causing change's
`## Follow-up Fixes` table. The table schema now includes a **Role**
column and a **Lookup** column (so audit queries can filter):

```bash
for ENTRY in "${CAUSED_BY[@]}"; do
  # Parse per-entry fields (slug, sha, role, lookup) from frontmatter
  CAUSING_SLUG=$(_entry_field "$ENTRY" slug)
  CAUSING_SHA=$(_entry_field "$ENTRY" sha)
  CAUSING_ROLE=$(_entry_field "$ENTRY" role)
  CAUSING_LOOKUP=$(_entry_field "$ENTRY" lookup)

  # Skip non-writable destinations
  case "$CAUSING_SLUG" in
    unknown|unknown_squash) continue ;;
    "") continue ;;
  esac

  CAUSING_STATE="harness/changes/${CAUSING_SLUG}/pipeline-state.md"

  if [ ! -f "$CAUSING_STATE" ]; then
    echo "WARNING: caused_by points to $CAUSING_SLUG but state file missing. Skipping back-link."
    continue
  fi

  # Ensure the section exists (new schema: Role + Lookup columns)
  if ! grep -q "^## Follow-up Fixes" "$CAUSING_STATE"; then
    cat >> "$CAUSING_STATE" << 'EOF'

## Follow-up Fixes
| Fix Slug | Role | Lookup | Reason | Date |
|----------|------|--------|--------|------|
EOF
  fi

  # Idempotency: own slug + role together (same slug could legitimately appear as
  # primary in one fix and call_path in another — both rows valid)
  OWN_SLUG="fix/${SLUG}"
  if grep -q "| $OWN_SLUG | $CAUSING_ROLE |" "$CAUSING_STATE"; then
    echo "Back-link already present in $CAUSING_STATE for role=$CAUSING_ROLE; skipping."
    continue
  fi

  REASON=$(head -1 harness/changes/fix/${SLUG}/requirements.md | sed 's/^# Bug: //')
  DATE=$(date -u +%Y-%m-%d)
  echo "| $OWN_SLUG | $CAUSING_ROLE | $CAUSING_LOOKUP | $REASON | $DATE |" >> "$CAUSING_STATE"
done
```

**Audit query examples** the new columns enable:

```bash
# Bug magnets — features with >3 direct causes (role=primary)
for d in harness/changes/feat/*/; do
  count=$(grep -c "| primary |" "$d/pipeline-state.md" 2>/dev/null || echo 0)
  [ "$count" -gt 3 ] && echo "$count  $d"
done | sort -rn

# Noisy call-path linkages (role=call_path) — features that just happened to be on
# stack frames a lot. Lower priority signal but useful for hot-path identification.
grep -c "| call_path |" harness/changes/*/*/pipeline-state.md

# Fixes that relied on fuzzy lookup — worth manual review
grep "| fuzzy " harness/changes/fix/*/pipeline-state.md
```
```

### 7.3 Acceptance criteria for Phase 5

- [ ] After `/harness-fix` completes Stage 7 with `caused_by: [feat/foo]`, `harness/changes/feat/foo/pipeline-state.md` has a `## Follow-up Fixes` row.
- [ ] Re-running Stage 7 does not append duplicate row (idempotent).
- [ ] Missing causing state file logs warning, does not crash.
- [ ] Multi-cause fix writes back-link row to each causing change.

---

## 8. Phase 6 — Escalation Path

### 8.1 Where escalation checks live

Four gates in `harness-fix.md`:

1. **Stage 1 Escalation Gate** — runs after reqs decomposition, BEFORE Stage 3 coding starts. Predictive — based on stated scope. Migration: clean (no code committed yet).
2. **Stage 3 Escalation Gate** — runs after coder sub-agent returns coding-report.md. Reactive — based on what was actually touched. Migration: code committed; can revert+restart or preserve+escalate.
3. **Stage 5 Escalation Gate** (NEW — Risk 3) — runs when test sub-agent returns `TEST_SCOPE_INFLATION` signal. Code already committed at Stage 3. See §8.5.
4. **Stage 6 Escalation Gate** (NEW — Risk 3) — runs when reviewer returns verdict `ESCALATION_REQUIRED`. Tests already written. See §8.5.

### 8.2 Escalation triggers (Stage 1)

After Stage 1 reqs are written, parse the requirements doc:

| Signal | Threshold | Source field |
|--------|-----------|--------------|
| Files predicted to touch | > 5 | requirements.md "Files likely touched" (if section present — fix lane doesn't require it but allows it) |
| Layers predicted | > 2 | requirements.md "Layers involved" |
| Data model change | any mention | grep requirements.md for "schema", "migration", "model change" |
| New external dependency | any | grep "depends on", "requires new" |
| Reporter says "needs redesign" | exact phrase | grep |

### 8.3 Escalation triggers (Stage 3)

After coder sub-agent writes coding-report.md, parse it:

| Signal | Threshold | Source |
|--------|-----------|--------|
| Files modified + created | > 5 | coding-report.md "Files created" + "Files modified" combined count |
| Layers touched | > 2 | coding-report.md "Layers touched" |
| Coder reported "scope creep" or "out of scope" | any | grep coding-report.md notes section |
| Build status fail with linker/type errors crossing modules | any | coding-report.md "Build status" + sub-agent return diagnostics |

### 8.4 Escalation prompt (when ANY trigger fires)

Use `AskUserQuestion` tool:

```
This bug fix is exceeding fix-lane scope:

Stage detected: {1 | 3}
Tripped signals:
  - {signal 1}: {actual value} (threshold {N})
  - {signal 2}: {actual value} (threshold {N})

Recommendation: ESCALATE to /harness-run (full pipeline).

Choose:
  1. Escalate to /harness-run (recommended)
       → Rename fix/{slug} → feat/{slug}-fix
       → Preserve caused_by + add escalated_from
       → Resume from Stage 1 of full pipeline
  2. Continue as fix (override)
       → Document override reason in pipeline-state.md
       → Accept risk of insufficient review depth
  3. Abort
       → Leave fix/{slug} as-is, status = ABORTED
       → Refile as feature request
```

### 8.5 Migration script (when user picks 1)

```bash
OLD_DIR="harness/changes/fix/${SLUG}"
NEW_SLUG="${SLUG}-fix"
NEW_DIR="harness/changes/feat/${NEW_SLUG}"

# 1. Move directory
if [ -e "$NEW_DIR" ]; then
  echo "ERROR: $NEW_DIR already exists. Aborting escalation."
  exit 1
fi
mv "$OLD_DIR" "$NEW_DIR"

# 2. Mutate frontmatter in requirements.md
REQ_FILE="$NEW_DIR/requirements.md"
python3 - << PYEOF
import re, sys
with open("$REQ_FILE") as f: content = f.read()

# Switch type
content = re.sub(r'^type:\s*fix$', 'type: feat', content, flags=re.MULTILINE)

# Add escalated_from line right after type: line
content = re.sub(
  r'(^type:\s*feat$)',
  r'\1\nescalated_from: fix/${SLUG}\nescalated_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)\nescalation_reason: |\n  ${ESCALATION_REASON}',
  content,
  count=1,
  flags=re.MULTILINE,
)

with open("$REQ_FILE", 'w') as f: f.write(content)
PYEOF

# 3. Mutate pipeline-state.md
STATE_FILE="$NEW_DIR/pipeline-state.md"
{
  echo ""
  echo "## Escalation"
  echo "- Escalated from: fix/${SLUG}"
  echo "- Escalated at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- Stages completed in fix lane: ${COMPLETED_STAGES}"
  echo "- Reason: ${ESCALATION_REASON}"
  echo ""
  echo "## Stage History (resumed)"
  echo "| Stage | Status | Timestamp | Notes |"
  echo "|-------|--------|-----------|-------|"
  echo "| ESCALATE | DONE | $(date -u +%Y-%m-%dT%H:%M:%SZ) | Migrated fix/${SLUG} → feat/${NEW_SLUG} |"
} >> "$STATE_FILE"

# Reset Current Stage marker
sed -i '' 's/^- Current Stage:.*$/- Current Stage: 1/' "$STATE_FILE"  # BSD sed; GNU: drop ''

# 4. Hand off
echo "Migration complete. Resuming via /harness-run --resume $NEW_DIR"
```

### 8.6 Hand-off mechanism

`/harness-run` needs a `--resume <dir>` mode if it doesn't already have one. Check
`templates/skills/harness-run.md` session-resumption section — it already does
`find harness/changes` (after Phase 1). The escalation just nudges it to find the
new feat/ entry naturally.

If automatic resume doesn't trigger, fix-lane skill explicitly invokes:

```
After migration, call:
  Skill tool: harness-run, args: "--resume harness/changes/feat/${NEW_SLUG}"
```

(Or, simpler: tell the user `/harness-run` is now ready and let them invoke it themselves. Less automation, less error surface.)

### 8.7 Back-link semantics after escalation

The causing change's `## Follow-up Fixes` row still gets written at Stage 7 of the
NOW-feat-lane pipeline. Row slug must reflect post-migration identity:

```markdown
| feat/{NEW_SLUG} (escalated from fix/{SLUG}) | {bug reason} | {date} |
```

### 8.8 Continue-as-fix override path (user picks 2)

Append to own pipeline-state.md:

```markdown
## Escalation Override
- Override at Stage: {1 | 3}
- Tripped signals: {list}
- User override reason: {prompt user for one-line reason}
- Override at: {ISO timestamp}
- Risk acknowledged: yes
```

Continue with fix lane.

### 8.9 Abort path (user picks 3)

Append to own pipeline-state.md:

```markdown
## Status (UPDATED)
- Current Stage: ABORTED
- Aborted at Stage: {1 | 3}
- Abort reason: Scope exceeded fix-lane; not refiled
```

Stop skill. Leave files for user to inspect / delete manually.

### 8.10 Stage 5/6 Late Escalation (NEW — resolves Risk 3)

Stages 1/3 use **predictive/reactive** gates with clean migration. Stages 5/6 are
different: code is already committed (Stage 3 push) and possibly reviewed (Stage 4).
Late escalation cannot do a clean reset — it must decide what to do with already-merged work.

#### 8.10.1 Stage 5 trigger

Test sub-agent (harness-coder in testing mode) returns a special signal when it
can't write meaningful tests without crossing layers. Coder template gains this
self-report block:

```markdown
## Test Sub-Agent Self-Report Format

When test writing requires scope inflation, write to coding-report.md:

### Test Scope Signal
- TEST_SCOPE_INFLATION: true
- Required additional files: {list}
- Required additional layers: {list}
- Reason: "{one sentence why a meaningful test needs these}"
```

Orchestrator detects `TEST_SCOPE_INFLATION: true` after Stage 5 → fires §8.10.3 prompt.

#### 8.10.2 Stage 6 trigger — new reviewer verdict

Reviewer template (`templates/agents/harness-reviewer.md`) gains a new verdict
value: `ESCALATION_REQUIRED`. Use when:
- Tests pass but reviewer believes fix masks symptoms; root cause is elsewhere
- Fix is correct given current scope but scope itself is wrong
- Architecture-level concern surfaces during test review

When verdict = `ESCALATION_REQUIRED`, reviewer MUST include section:

```markdown
## Escalation Reason
- Type: {symptom-mask | wrong-scope | architectural}
- Analysis: "{2-3 sentence explanation of why scope is wrong}"
- Suggested follow-up: "{what a proper feat-lane fix would address}"
```

Orchestrator detects this verdict after Stage 6 → fires §8.10.3 prompt with
reviewer's reasoning included.

#### 8.10.3 Late-escalation prompt (Stage 5 or 6)

Use `AskUserQuestion`. Note: this IS a mid-flow prompt, but it's **incident
response**, not config — [[feedback-prompt-timing]] doesn't apply because there's
no init-time decision that could have anticipated this specific test/review
finding.

```
{Stage 5: Test scope inflation | Stage 6: Reviewer flagged escalation}

Code committed at Stage 3: {SHA} ({files})
{Stage 5: Test sub-agent reports — needs {N} additional files in {layers} for meaningful test}
{Stage 6: Reviewer (ESCALATION_REQUIRED) — {reviewer's Escalation Reason analysis}}

Options:

  1. Revert Stage 3 commit + abort fix
       → git revert {SHA} (clean working tree)
       → pipeline-state.md → Status: ABORTED_LATE
       → Bug remains unfixed; no audit trail beyond fix/{slug}/
       → Use when: fix attempt was wrong direction; want to start fresh

  2. Late-escalate to feat lane (PRESERVE commit)
       → mv fix/{slug} → feat/{slug}-fix
       → Stage 3 commit STAYS on branch (becomes feat's Stage 3 starting point)
       → Mark Status: ESCALATED_LATE in old slot via tombstone (see 8.10.5)
       → Frontmatter gains: escalated_from: fix/{slug}, escalated_at_stage: {5|6}
       → pipeline-state.md gets migration block + resets Current Stage: 1
       → Resume via /harness-run --resume — full pipeline re-decomposes scope,
         re-reviews existing code under broader spec. May require code changes
         once new spec lands; that's expected and visible in audit history.
       → Use when: fix's direction is right but needs proper requirements + review

  3. Ship as partial fix + file root-cause feat
       → Continue fix/{slug} to Stage 7 (push existing fix as-is)
       → Status: PARTIAL_FIX (new first-class state — see §8.11)
       → Frontmatter gains: partial: true, partial_reason: "...", root_cause_feat: feat/{auto-slug}
       → Auto-create empty harness/changes/feat/{auto-slug}/ skeleton — pre-populated 
         with filed_from_partial_fix: fix/{slug} and inherited caused_by_chain
       → User invokes /harness-run feat: ... later when ready
       → Use when: symptom-masking ship is acceptable now; root cause needs proper feature work
```

#### 8.10.4 Migration mechanics (option 2 — preserve commit)

```bash
OLD_DIR="harness/changes/fix/${SLUG}"
NEW_SLUG="${SLUG}-fix"
NEW_DIR="harness/changes/feat/${NEW_SLUG}"
ESCALATED_STAGE="${CURRENT_STAGE}"   # 5 or 6
COMMITTED_SHA=$(grep -A1 "^## Commits" "$OLD_DIR/pipeline-state.md" | grep "| 7 \|| 3 " | awk '{print $4}' | head -1)

[ -e "$NEW_DIR" ] && { echo "ERROR: $NEW_DIR exists. Abort."; exit 1; }
mv "$OLD_DIR" "$NEW_DIR"

# Mutate requirements.md frontmatter (Python heredoc as in Stage 1/3 migration)
python3 << PYEOF
import re
p = "$NEW_DIR/requirements.md"
with open(p) as f: content = f.read()
content = re.sub(r'^type:\s*fix$', 'type: feat', content, flags=re.M)
content = re.sub(
  r'(^type:\s*feat$)',
  r'\1\nescalated_from: fix/${SLUG}\nescalated_at_stage: ${ESCALATED_STAGE}\nescalated_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)\npreserved_commit: ${COMMITTED_SHA}',
  content, count=1, flags=re.M
)
open(p, 'w').write(content)
PYEOF

# Append late-escalation block to pipeline-state.md
cat >> "$NEW_DIR/pipeline-state.md" << EOF

## Late Escalation
- Escalated from: fix/${SLUG}
- Escalated at stage: ${ESCALATED_STAGE}
- Escalated at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
- Preserved Stage 3 commit: ${COMMITTED_SHA}
- Trigger: {Stage 5 TEST_SCOPE_INFLATION | Stage 6 ESCALATION_REQUIRED verdict}
- Reason: ${ESCALATION_REASON}

## Stage History (resumed)
| Stage | Status | Timestamp | Notes |
|-------|--------|-----------|-------|
| ESCALATE_LATE | DONE | $(date -u +%Y-%m-%dT%H:%M:%SZ) | Migrated fix/${SLUG} → feat/${NEW_SLUG}; commit ${COMMITTED_SHA} preserved |
EOF

sed -i '' 's/^- Current Stage:.*$/- Current Stage: 1/' "$NEW_DIR/pipeline-state.md"

echo "Migrated. Resume via /harness-run --resume $NEW_DIR"
```

#### 8.10.5 Tombstone in old fix slot

When option 2 runs, the old `fix/{slug}/` directory is GONE (moved). Audit
queries looking for the fix slug return nothing — confusing. Solution: leave a
tombstone behind:

```bash
mkdir -p "harness/changes/fix/${SLUG}"
cat > "harness/changes/fix/${SLUG}/TOMBSTONE.md" << EOF
# Tombstone: fix/${SLUG} → feat/${NEW_SLUG}

This fix was escalated late (at Stage ${ESCALATED_STAGE}) and migrated to:
**harness/changes/feat/${NEW_SLUG}/**

All artifacts live there now. This file is a forwarding pointer only.

- Original fix invocation: /harness-fix ${ORIGINAL_INVOCATION}
- Escalated at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
- Reason: ${ESCALATION_REASON}
EOF
```

Tombstones live forever — never delete. Audit queries that grep `harness/changes/fix/*/` should detect TOMBSTONE.md and follow the pointer.

#### 8.10.6 Option 3 mechanics (partial fix + file feat) — see §8.11

### 8.11 PARTIAL_FIX first-class state (NEW)

PARTIAL_FIX is a terminal Status (alongside COMPLETE / ABORTED / ABORTED_LATE / ESCALATED / ESCALATED_LATE) that means: "fix shipped, but it masks symptoms; the root-cause work is filed and tracked separately."

#### 8.11.1 Frontmatter shape

```yaml
---
type: fix
partial: true
partial_reason: |
  Fix masks NPE by null-guarding the cart read. Root cause is missing
  validation contract in payment service (filed as feat/payment-validation-contract).
root_cause_feat: feat/payment-validation-contract
caused_by:
  - slug: feat/bulk-export-endpoint
    sha: abc1234
    role: primary
    lookup: exact
---
```

#### 8.11.2 pipeline-state.md status block

```markdown
## Status
- Current Stage: 7
- Status: PARTIAL_FIX
- Partial Reason: "{one-line summary}"
- Root Cause Feat: feat/payment-validation-contract
- Root Cause Status: PENDING (last checked: 2026-05-18)
```

`Root Cause Status` updated when the linked feat completes (mechanism in 8.11.4).

#### 8.11.3 Auto-skeleton for the root-cause feat

When user picks option 3 at the §8.10.3 prompt, orchestrator creates skeleton:

```bash
SUGGESTED_SLUG="${ORIG_FIX_SLUG}-root-cause"
NEW_FEAT_DIR="harness/changes/feat/${SUGGESTED_SLUG}"
mkdir -p "$NEW_FEAT_DIR"

# Inherit caused_by from the partial fix (the fix's causes are the feat's causes too)
INHERITED_CAUSED_BY=$(awk '/^caused_by:/,/^---$/{print}' "harness/changes/fix/${ORIG_FIX_SLUG}/requirements.md" \
                     | head -n -1 | tail -n +1)

cat > "$NEW_FEAT_DIR/requirements.md" << EOF
---
type: feat
filed_from_partial_fix: fix/${ORIG_FIX_SLUG}
filed_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
${INHERITED_CAUSED_BY}
---

# Feat: {ROOT_CAUSE_TITLE — user fills}

## Origin
Filed during partial-fix shipping of fix/${ORIG_FIX_SLUG}. That fix masked the
symptom; this feature addresses the root cause flagged by the reviewer.

See harness/changes/fix/${ORIG_FIX_SLUG}/review-record.md for the reviewer's
Escalation Reason analysis.

## Requirements
{to be filled by user when they invoke /harness-run feat: ${SUGGESTED_SLUG}}
EOF

cat > "$NEW_FEAT_DIR/pipeline-state.md" << EOF
# Pipeline State: ${SUGGESTED_SLUG}

## Status
- Current Stage: 0
- Status: AWAITING_INVOCATION
- Filed From: fix/${ORIG_FIX_SLUG}
- Filed At: $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
```

#### 8.11.4 Reverse link when root-cause feat completes

Extend harness-run.md Stage 7 logic: when a feat has `filed_from_partial_fix:` in
its frontmatter and completes Stage 7, write back to the partial fix's
pipeline-state.md:

```bash
FILED_FROM=$(grep '^filed_from_partial_fix:' requirements.md | awk '{print $2}')
[ -n "$FILED_FROM" ] || exit 0

PARTIAL_STATE="harness/changes/${FILED_FROM}/pipeline-state.md"
[ -f "$PARTIAL_STATE" ] || exit 0

# Update Root Cause Status line
sed -i '' 's|^- Root Cause Status:.*$|- Root Cause Status: COMPLETE (verified '"$(date -u +%Y-%m-%d)"')|' "$PARTIAL_STATE"

# Append a Root Cause Addressed By table if not present
if ! grep -q "^## Root Cause Addressed By" "$PARTIAL_STATE"; then
  cat >> "$PARTIAL_STATE" << EOF

## Root Cause Addressed By
| Feat | Status | Date |
|------|--------|------|
EOF
fi
echo "| $(basename $(pwd)) | COMPLETE | $(date -u +%Y-%m-%d) |" >> "$PARTIAL_STATE"
```

#### 8.11.5 Audit queries enabled by PARTIAL_FIX

```bash
# Open tech debt = partial fixes whose root cause hasn't shipped yet
grep -l "Status: PARTIAL_FIX" harness/changes/fix/*/pipeline-state.md | while read f; do
  status=$(grep "Root Cause Status:" "$f" | awk -F: '{print $2}' | xargs)
  [ "$status" = "PENDING" ] && echo "$f"
done

# Mean time from partial → root-cause closure (across all closed pairs)
# Joins fix's filed_at with feat's COMPLETE date — left as awk exercise.
```

### 8.12 Acceptance criteria for Phase 6

- [ ] Stage 1 with predicted 6 files triggers escalation prompt (clean migration path).
- [ ] Stage 3 with actual 6 files modified triggers escalation prompt (revert-or-preserve choice).
- [ ] Choosing option 1 at Stage 1/3 successfully renames dir, mutates frontmatter, resets stage.
- [ ] Choosing option 2 appends override block to pipeline-state.md and continues.
- [ ] Choosing option 3 marks ABORTED and stops cleanly.
- [ ] Escalated fix's back-link at Stage 7 names the new feat/ slug, not the old fix/ slug.
- [ ] Migration script is idempotent — re-running on already-migrated dir fails with clear error, no corruption.
- [ ] (Risk 3) Stage 5 test sub-agent reporting `TEST_SCOPE_INFLATION: true` fires §8.10.3 prompt with 3 options.
- [ ] (Risk 3) Stage 6 reviewer returning verdict `ESCALATION_REQUIRED` fires §8.10.3 prompt with reviewer's Escalation Reason context.
- [ ] (Risk 3) Late-escalation option 1: `git revert` runs cleanly; pipeline-state.md → Status: ABORTED_LATE.
- [ ] (Risk 3) Late-escalation option 2: dir renamed, commit preserved on branch, tombstone written at old `fix/{slug}/TOMBSTONE.md`, Current Stage reset to 1.
- [ ] (Risk 3) Late-escalation option 3: fix pushed to Stage 7 with Status: PARTIAL_FIX; auto-skeleton at `harness/changes/feat/{slug}-root-cause/` exists with inherited caused_by; Status: AWAITING_INVOCATION.
- [ ] (Risk 3) When the root-cause feat completes Stage 7, partial fix's `Root Cause Status` updates to COMPLETE and `## Root Cause Addressed By` row appears.
- [ ] (Risk 3) Audit query "find open partial fixes" returns correct list.
- [ ] (Risk 3) Tombstone at `harness/changes/fix/{slug}/TOMBSTONE.md` persists post-migration and contains forwarding pointer.

---

## 9. Phase 7 — Wiring

### 9.1 Files touched

| File | Action |
|------|--------|
| `skills/harness-engineering/references/wiring.md` | Edit §10.2 (add harness-fix symlink); add §10.8 (merge-strategy prompt + hook install) |
| `skills/harness-engineering/hook-templates/post-merge-backlink.sh` | **NEW** (body in Phase 4.5 §6.5.5) |
| `skills/harness-engineering/hook-templates/lookup-helpers.sh` | **NEW** (contains `_fuzzy_file_overlap_match` + `_cache_append` + `_maybe_warn_slow_scan` helpers, sourced by harness-fix) |
| `skills/harness-engineering/hook-templates/rebuild-commit-index.sh` | **NEW** (Phase 4.6 §6.6.5 — reconstructs cache from pipeline-state.md) |

### 9.2 Edit `wiring.md` §10.2 — symlinks

Find the block in 10.2 (lines 19–28). After the harness-run line, add:

```bash
ln -sf "$(pwd)/harness/skills/harness-fix" .claude/skills/harness-fix
```

### 9.3 New §10.8 — Merge-strategy decision + hook install

Append to `wiring.md`:

```markdown
## 10.8 Wire Squash-Merge Resilience

This step decides how `/harness-fix` handles SHA drift when PRs are squash-merged.
Front-loaded here so the fix lane never interrupts users mid-bug.

### Step 1: Detect merge strategy hints

```bash
# Detect husky (changes hook install path)
HUSKY_PRESENT=no
[ -d ".husky" ] && [ -f ".husky/_/husky.sh" -o -f ".husky/install.mjs" ] && HUSKY_PRESENT=yes

# Detect github default merge method (best-effort, requires gh CLI + repo perms)
if command -v gh >/dev/null 2>&1; then
  GH_MERGE_DEFAULT=$(gh api "repos/{owner}/{repo}" --jq '.merge_commit_allowed,.squash_merge_allowed,.rebase_merge_allowed' 2>/dev/null)
fi
```

### Step 2: Prompt user

Use `AskUserQuestion`. See Phase 4.5 §6.5.3 in plan.md for full prompt body.

Branch:
- "rebase/merge-commit" → `echo "not-needed" > harness/.merge-hook-decision`
- "defer" → `echo "ask-later" > harness/.merge-hook-decision`
- "squash" → follow-up prompt (install / fuzzy / skip / never-ask)

### Step 3: If user picked "install hook"

Copy the hook template and install:

```bash
if [ "$HUSKY_PRESENT" = "yes" ]; then
  HOOK_DST=".husky/post-merge"
else
  HOOK_DST=".git/hooks/post-merge"
fi

HOOK_SRC="harness/hooks/post-merge-backlink.sh"
# (Wiring already copied template to harness/hooks/ — see Phase 8 hook copy block below)

if [ -f "$HOOK_DST" ] && ! grep -q "HARNESS_BACKLINK_HOOK" "$HOOK_DST"; then
  echo "" >> "$HOOK_DST"
  cat "$HOOK_SRC" >> "$HOOK_DST"
elif [ ! -f "$HOOK_DST" ]; then
  cp "$HOOK_SRC" "$HOOK_DST"
fi
chmod +x "$HOOK_DST"

echo "installed" > harness/.merge-hook-decision
```

### Step 4: Copy hook + helper templates to harness/hooks/

Always (regardless of decision, so users can switch later without re-installing the plugin):

```bash
cp skills/harness-engineering/hook-templates/post-merge-backlink.sh harness/hooks/post-merge-backlink.sh
cp skills/harness-engineering/hook-templates/lookup-helpers.sh harness/hooks/lookup-helpers.sh
cp skills/harness-engineering/hook-templates/rebuild-commit-index.sh harness/hooks/rebuild-commit-index.sh
chmod +x harness/hooks/post-merge-backlink.sh
chmod +x harness/hooks/rebuild-commit-index.sh
# lookup-helpers.sh is sourced, not executed — no chmod needed
```

(Path `skills/harness-engineering/hook-templates/` is the in-skill path; wiring resolves it via `$CLAUDE_PROJECT_DIR` of the skill repo when running. Plugin install resolves via plugin dir.)

### Step 5: Add `harness/.merge-hook-decision` to git

```bash
git add harness/.merge-hook-decision
# Intentionally NOT in .gitignore — teammates inherit the repo's decision.
```

### Step 6: Add reverse-lookup cache to .gitignore (Phase 4.6)

```bash
# Cache is regenerable; teammates rebuild on first slow scan
grep -qxF "harness/.commit-index.tsv" .gitignore 2>/dev/null || echo "harness/.commit-index.tsv" >> .gitignore
```
```

### 9.4 Validation row already covered

Phase 8 adds validation rows for both the symlink and the new decision file + hook.

### 9.5 Acceptance criteria for Phase 7

- [ ] After Phase 10 wiring, `.claude/skills/harness-fix` exists and resolves to `harness/skills/harness-fix/`.
- [ ] `harness/.merge-hook-decision` exists with one of the 6 valid values.
- [ ] If decision = installed: `.git/hooks/post-merge` (or `.husky/post-merge`) exists with HARNESS_BACKLINK_HOOK signature and is executable.
- [ ] `harness/hooks/post-merge-backlink.sh` and `harness/hooks/lookup-helpers.sh` exist regardless of decision.
- [ ] `harness/hooks/rebuild-commit-index.sh` exists and is executable (Phase 4.6).
- [ ] `.gitignore` contains `harness/.commit-index.tsv` line (Phase 4.6).
- [ ] Re-running wiring with same decision does not duplicate hook content.
- [ ] Re-running wiring with different decision updates the cache file and re-installs/skips hook accordingly.

---

## 10. Phase 8 — Validation

### 10.1 File touched

`skills/harness-engineering/references/validation.md` — add rows + manual tests.

### 10.2 New rows in the verification table

Insert after row 11:

```markdown
| 12 | harness-fix skill present | `ls .claude/skills/harness-fix/SKILL.md` | Symlink resolves |
| 13 | harness-fix folder/name parity | `grep '^name:' .claude/skills/harness-fix/SKILL.md` | `name: harness-fix` |
| 14 | Typed changes layout works | `mkdir -p harness/changes/fix/__test && touch harness/changes/fix/__test/pipeline-state.md && find harness/changes -mindepth 3 -maxdepth 3 -name pipeline-state.md; rmdir harness/changes/fix/__test` | Finds the test file |
| 15 | Pre-push gate finds typed paths | (manual — see test below) | Gate reads correct state file |
| 16 | Commits table format | `grep -A2 '## Commits' harness/changes/*/*/pipeline-state.md` | Header row present |
| 17 | Merge-hook decision cached | `cat harness/.merge-hook-decision` | One of: not-needed, installed, fuzzy-allowed, skip-only, never-ask, ask-later |
| 18 | Hook template copied | `test -f harness/hooks/post-merge-backlink.sh && test -x harness/hooks/post-merge-backlink.sh` | Exit 0 |
| 19 | Lookup helpers present | `test -f harness/hooks/lookup-helpers.sh` | Exit 0 |
| 20 | If decision=installed → hook live | `[ "$(cat harness/.merge-hook-decision)" = "installed" ] && grep -q HARNESS_BACKLINK_HOOK .git/hooks/post-merge .husky/post-merge 2>/dev/null` | Match found (or N/A if decision ≠ installed) |
| 21 | Rebuild script present + executable | `test -x harness/hooks/rebuild-commit-index.sh` | Exit 0 |
| 22 | .gitignore excludes cache | `grep -qxF "harness/.commit-index.tsv" .gitignore` | Exit 0 |
| 23 | Manual rebuild produces valid cache | `bash harness/hooks/rebuild-commit-index.sh && test -f harness/.commit-index.tsv && [ "$(wc -l < harness/.commit-index.tsv)" -ge 0 ]` | All exit 0 |
| 24 | Cache TSV format valid | `awk -F'\t' 'NF != 4 { exit 1 }' harness/.commit-index.tsv` | Exit 0 (all rows have 4 tab-separated fields) |
```

### 10.3 Manual integration tests (append to validation.md)

```markdown
## Integration Test A: Causal link round-trip

1. Bootstrap a fake causing change:
   ```bash
   mkdir -p harness/changes/feat/test-cause
   cat > harness/changes/feat/test-cause/pipeline-state.md << 'EOF'
   # Pipeline State: test-cause

   ## Status
   - Current Stage: 7

   ## Commits
   | Stage | SHA | Files |
   |-------|-----|-------|
   | 7 | DEADBEEF | src/test-cause.ts |
   EOF
   ```
2. Create a real file + commit it so blame returns the (real) SHA:
   ```bash
   echo "// test" > src/test-cause.ts
   git add src/test-cause.ts
   git commit -m "test: bootstrap for harness-fix validation"
   REAL_SHA=$(git rev-parse HEAD)
   ```
3. Patch the bootstrap state file to use the real SHA:
   ```bash
   sed -i '' "s/DEADBEEF/${REAL_SHA}/" harness/changes/feat/test-cause/pipeline-state.md
   ```
4. Invoke `/harness-fix Bug at src/test-cause.ts:1 — test`.
5. Verify Stage 0 writes:
   - `harness/changes/fix/bug-at-src-test-cause/requirements.md` has `caused_by: [feat/test-cause (...)]`.
6. After Stage 7 pushes:
   - `harness/changes/feat/test-cause/pipeline-state.md` has new `## Follow-up Fixes` row pointing at `fix/bug-at-src-test-cause`.
7. Cleanup: `git revert HEAD; rm -rf harness/changes/feat/test-cause harness/changes/fix/bug-at-src-test-cause`.

## Integration Test B: Escalation

1. Invoke `/harness-fix Rewrite payment handling to use new schema with 7-table migration`.
2. Stage 1 should detect:
   - "rewrite" keyword
   - "schema" + "migration" → data model change signal
3. User picks option 1 (escalate).
4. Verify:
   - `harness/changes/fix/rewrite-payment-handling/` no longer exists.
   - `harness/changes/feat/rewrite-payment-handling-fix/` exists.
   - `requirements.md` frontmatter has `type: feat`, `escalated_from: fix/rewrite-payment-handling`.
   - `pipeline-state.md` has `## Escalation` block + reset `Current Stage: 1`.
   - `/harness-run` (or new invocation) resumes from Stage 1.

## Integration Test C: Pre-push gate still works

1. Create `harness/changes/feat/__gate-test/pipeline-state.md` with `Current Stage: 6` (below push threshold).
2. Attempt `git push` (or directly run `harness/hooks/pre-push-gate.sh`).
3. Expect: BLOCKED with "Pipeline is at Stage 6 (need ≥ 7 for push)".
4. Bump Current Stage to 7 in the test file.
5. Re-run. Expect: build/lint/test checks proceed (may fail later but gate's stage check passes).
6. Cleanup: `rm -rf harness/changes/feat/__gate-test`.

## Integration Test D: Squash-merge resilience (decision = installed)

1. Bootstrap a squash-eligible feature change:
   ```bash
   mkdir -p harness/changes/feat/squash-target
   cat > harness/changes/feat/squash-target/pipeline-state.md << 'EOF'
   # Pipeline State: squash-target

   ## Status
   - Current Stage: 7

   ## Commits
   | Stage | SHA | Files |
   |-------|-----|-------|
   | 7 | PLACEHOLDER | src/squash-target.ts |
   EOF
   echo "// squash-target" > src/squash-target.ts
   git checkout -b feature/squash-target
   git add src/squash-target.ts harness/changes/feat/squash-target/
   git commit -m "feat: squash target"
   ORIG_SHA=$(git rev-parse HEAD)
   sed -i '' "s/PLACEHOLDER/${ORIG_SHA}/" harness/changes/feat/squash-target/pipeline-state.md
   git commit -a --amend --no-edit
   ```
2. Ensure decision = installed:
   ```bash
   echo "installed" > harness/.merge-hook-decision
   cp harness/hooks/post-merge-backlink.sh .git/hooks/post-merge
   chmod +x .git/hooks/post-merge
   ```
3. Simulate squash-merge to main:
   ```bash
   git checkout main
   git merge --squash feature/squash-target
   git commit -m "feat: squash target (#42)"
   ```
4. Hook should have fired automatically. Verify:
   - `harness/changes/feat/squash-target/pipeline-state.md` has `## Squash Merges` section with `squashed_to: <new-sha>` row.
5. Invoke `/harness-fix Bug at src/squash-target.ts:1` and verify Stage 0:
   - Reads decision file silently (no prompt).
   - Layer 1 (exact SHA) misses (ORIG_SHA is orphan after squash, blame returns new SHA).
   - Layer 2 (squashed_to lookup) hits.
   - `caused_by_confidence: squash_hook` in fix's requirements.md frontmatter.
6. Cleanup: revert commits + branches + test files.

## Integration Test E: Squash-merge with decision = skip-only

1. Set `echo "skip-only" > harness/.merge-hook-decision`.
2. Remove `.git/hooks/post-merge`.
3. Repeat steps 1-3 of Test D (creating squash + merging).
4. Invoke `/harness-fix Bug at src/squash-target.ts:1`. Verify:
   - No prompt (decision cached).
   - `caused_by: [unknown_squash (<sha>)]` in requirements.md.
   - `caused_by_confidence: skipped`.
   - Fix proceeds normally.
5. Cleanup.

## Integration Test F: ask-later fallback

1. `rm -f harness/.merge-hook-decision`.
2. Invoke `/harness-fix` on any file:line.
3. Verify: skill prompts with merge-strategy question (the fix-time fallback prompt §6.5.4).
4. Pick any option. Verify decision file now exists with chosen value.
5. Invoke `/harness-fix` again on a different file:line. Verify: NO prompt (cache honored).

## Integration Test G: Reverse-lookup cache (Path F)

1. **Bootstrap state**: ensure no cache exists.
   ```bash
   rm -f harness/.commit-index.tsv
   ```
2. **Cold scan + auto-build**: invoke `/harness-fix Bug at src/something.ts:1` on a freshly populated harness/changes/ (use Test A's bootstrap commits). Expect:
   - First scan triggers warning if scan duration > threshold.
   - Auto-build creates `harness/.commit-index.tsv`.
3. **Verify cache shape**:
   ```bash
   awk -F'\t' '{ if (NF != 4) print "BAD ROW:", $0; if (length($1) < 7) print "BAD SHA:", $0 }' harness/.commit-index.tsv
   ```
   Should produce no output.
4. **Cache hit on second invocation**: invoke `/harness-fix Bug at src/something.ts:1` again. Expect:
   - No scan triggered (or much faster — verify via debug log if added).
   - `caused_by` resolution matches cold-scan result.
5. **Stage 7 self-write**: after a fix completes Stage 7, verify cache gained a new row for the fix's commit:
   ```bash
   grep "fix/" harness/.commit-index.tsv | tail -1
   ```
6. **Self-heal on miss**: create a fake change without going through skill (manually mkdir + write pipeline-state.md with a known SHA). Cache won't have it. Invoke `/harness-fix` referencing that SHA. Layer 1 scan succeeds → cache should self-heal. Verify with `grep "^<fake-sha>" harness/.commit-index.tsv`.
7. **--no-index bypass**: invoke `/harness-fix --no-index "trivial"`. Verify cache not consulted (Layer 0 skipped — confirm via log or by deleting cache mid-run; the no-index path should still produce correct results via scan).
8. **--rebuild-index**: invoke `/harness-fix --rebuild-index ...`. Verify:
   - Cache deleted then reconstructed from scratch.
   - Row count matches sum of (Commits rows + Squash Merges rows) across all pipeline-state.md files.
9. **Threshold override**: `HARNESS_CACHE_THRESHOLD_MS=0 /harness-fix ...`. Verify no warning emitted regardless of scan duration.
10. **Cleanup**: revert test commits, `rm -f harness/.commit-index.tsv`.
```

### 10.4 Acceptance criteria for Phase 8

- [ ] All 16 verification table rows pass on a freshly generated harness.
- [ ] All 3 integration tests pass.
- [ ] No row 11 (skill folder/name parity) regression — `harness-fix` follows the invariant.

---

## 11. Final wrap-up

After Phase 8:

1. Bump version from `0.2.0-dev` → `0.2.0` in `.claude-plugin/plugin.json` + `marketplace.json`.
2. Update `README.md`:
   - Mention `/harness-fix` in "When to Use" section (around line 24).
   - Add brief note in "How It Works" about the 5-stage fix lane.
   - Update repo layout block (line 76+) to show `harness-fix.md` in templates dir.
3. Add CHANGELOG.md (new file) if you want versioned history. Suggested entry:
   ```markdown
   # Changelog

   ## 0.2.0
   - **NEW:** `harness-fix` skill — 5-stage bug-fix lane with auto-link to causing change.
   - **NEW:** Typed `harness/changes/{type}/{slug}/` layout (feat/, fix/, refactor/).
   - **NEW:** Stage 7 records commit SHA + files in `pipeline-state.md`.
   - **NEW:** Bidirectional causal links (`caused_by` ↔ `## Follow-up Fixes`).
   - **NEW:** Escalation path from fix lane to full `harness-run` pipeline.
   - **NEW:** Squash-merge resilience — init-time prompt for merge strategy, optional `.git/hooks/post-merge` install, cached decision in `harness/.merge-hook-decision`, tiered reverse-lookup chain (exact SHA → squashed_to → fuzzy file overlap → unknown). Fix-time path is silent unless decision is deferred.
   - **NEW:** Reverse-lookup cache (`harness/.commit-index.tsv`) — self-healing O(1) SHA→slug index. Auto-built on first scan > 1s; manual `--build-index` / `--rebuild-index` / `--no-index` flags; `HARNESS_CACHE_THRESHOLD_MS` env override. Source of truth stays in pipeline-state.md; cache is gitignored.
   - **CHANGE:** `pre-push-gate.sh` now scans typed subdirs.
   - **CHANGE:** `harness-run.md` parses `feat:` / `fix:` / `refactor:` prefix from requirement.
   ```
4. Commit per-phase (8 commits) or one merge commit, your call.
5. Open PR against main, reference this plan.md in description.

---

## 12. Rollback strategy (if implementation half-done)

If you ship Phase 1 but not Phase 3 (typed layout exists, no fix lane yet):
- All existing functionality works; fix lane just doesn't exist.
- Users invoke `/harness-run fix: ...` and get full 10-stage — overkill but functional.

If you ship Phases 1+3 but not Phase 4 (fix lane exists, no auto-link):
- Fix lane runs, `caused_by` frontmatter is empty list.
- User must manually populate or use `--caused-by` flag.

If you need to revert entirely:
```bash
git revert <merge-commit-sha>
```
No state migration needed — typed dirs and flat dirs coexist (find at depth 2 still works for legacy; new depth-3 layout is additive). Existing legacy `harness/changes/{slug}/` directories from pre-feature users are untouched and still readable.

---

## 13. Touched-files inventory (final)

| File | Phase(s) | Change type |
|------|----------|-------------|
| `skills/harness-engineering/SKILL.md` | 1, 3 | Edit (layout diagram, Phase 3 table) |
| `skills/harness-engineering/templates/skills/harness-run.md` | 1, 2 | Edit (paths, Stage 7) |
| `skills/harness-engineering/templates/skills/harness-fix.md` | 3, 4, 5, 6 | **NEW** |
| `skills/harness-engineering/templates/pipeline.md` | 2 | Edit (Stage 7 output) |
| `skills/harness-engineering/templates/agent.md` | 3 | Edit (Config Index table) |
| `skills/harness-engineering/templates/agents/harness-reviewer.md` | 6 | Edit (add `ESCALATION_REQUIRED` verdict + Escalation Reason section template) |
| `skills/harness-engineering/templates/agents/harness-coder.md` | 6 | Edit (add Test Scope Signal self-report block to testing-mode output format) |
| `skills/harness-engineering/hook-templates/pre-push-gate.sh` | 1 | Edit (find recursive) |
| `skills/harness-engineering/hook-templates/post-merge-backlink.sh` | 4.5, 7 | **NEW** (squash-merge hook body) |
| `skills/harness-engineering/hook-templates/lookup-helpers.sh` | 4.5, 4.6, 7 | **NEW** (fuzzy match + cache helpers, sourced by harness-fix) |
| `skills/harness-engineering/hook-templates/rebuild-commit-index.sh` | 4.6, 7 | **NEW** (cache rebuild from pipeline-state.md) |
| `harness/.commit-index.tsv` (in target repos) | 4.6 | NEW cache file; auto-built lazily; in `.gitignore` (regenerable) |
| `skills/harness-engineering/references/wiring.md` | 1, 7 | Edit (typed dirs, harness-fix symlink, new §10.8 merge-strategy prompt + hook install) |
| `skills/harness-engineering/references/validation.md` | 1, 8 | Edit (13 new rows [12-24] + 7 manual tests A–G: A causal-link, B escalation, C pre-push, D-F squash resilience, G cache) |
| `harness/.merge-hook-decision` (in target repos) | 4.5, 7 | NEW file emitted at wiring; one of 6 enum values; committed to git |
| `unidecode` Python dep (optional, for slug transliteration) | 3 (Risk 4) | Soft dep — checked at slug-derivation time; falls back to ASCII-strip if missing. Document in README install section. |
| `.claude-plugin/plugin.json` | wrap-up | Edit (version) |
| `.claude-plugin/marketplace.json` | wrap-up | Edit (version) |
| `README.md` | wrap-up | Edit (mention fix lane + squash-merge behaviour) |
| `CHANGELOG.md` | wrap-up | NEW (optional) |

**Total:** 1 new template, 2 new hook templates, 1 new optional doc, 9 edits. ~280-330 LOC delta.

---

## 14. Risk / Open-Questions Tracker

Walked through one at a time. Update status as discussion progresses.

| # | Risk | Status | Resolution |
|---|------|--------|-----------|
| 1 | Squash-merge SHA drift breaks reverse lookup | **RESOLVED → Phase 4.5** | Init-time decision (`harness/.merge-hook-decision`); tiered chain (exact → squashed_to → fuzzy → unknown); optional post-merge hook with husky compat; no fix-time prompt unless deferred |
| 2 | Multiple `caused_by` entries — fan-out write semantics | **RESOLVED → Option B in Phase 4 §0.4-0.5, Phase 5** | Fan-out all causes; per-entry `role` (primary/call_path) from stack-trace order; per-entry `lookup` from layer that succeeded; back-link table gains Role + Lookup columns; cap=5 frames with overflow note; dedupe primary>call_path; no transitive walk; filter noise at audit query time, not write time |
| 3 | Mid-Stage-5/6 escalation messiness (only gated at 1 & 3 today) | **RESOLVED → Phase 6 §8.10-§8.11** | A+D combo: late-escalation prompt (revert / preserve-commit-and-migrate / ship-as-partial+file-feat); new `ESCALATION_REQUIRED` reviewer verdict; new `TEST_SCOPE_INFLATION` test-agent signal; new `PARTIAL_FIX` first-class Status with reverse link from root-cause feat back to partial fix; tombstone in old fix/ slot preserves audit trail; mid-flow prompt acceptable here because it's incident response, not config |
| 4 | Path sanitization for free-text bug → slug | **RESOLVED → Phase 3 §5.5 (Option E)** | 12-step pipeline: override flag → strip prefix → lowercase → unidecode (with ASCII-strip fallback) → hyphen-collapse → trim → truncate at 80 chars on word boundary → empty-fallback to `fix-{timestamp}` → reserved-name prefix → leading-hyphen guard → collision prompt (5 options including reopen, suffix, custom, abort) → final regex validation. Tombstone-only dirs trigger forwarding prompt. `--slug` flag for power-user override. |
| 5 | When does scan-based reverse lookup become a bottleneck? `.commit-index.tsv` deferral threshold | **RESOLVED → Phase 4.6 (Path F)** | Self-healing `harness/.commit-index.tsv` cache. Stage 0 Layer 0 reads cache first; Layer 1/2 scans self-heal on miss. Auto-build on cold scan > 1s (configurable via `HARNESS_CACHE_THRESHOLD_MS`). Flags: `--build-index`, `--rebuild-index`, `--no-index`. Rebuild script `harness/hooks/rebuild-commit-index.sh` reconstructs from pipeline-state.md anytime. Cache in `.gitignore` (regenerable; per-machine). Source of truth stays in pipeline-state.md. |
