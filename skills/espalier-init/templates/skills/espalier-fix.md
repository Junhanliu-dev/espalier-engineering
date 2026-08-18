---
name: espalier-fix
description: Bug-fix orchestrator — 7 stages (0–7, no Stage 2) with auto-link to the change that introduced the bug
---

# Espalier Fix Runner

## When to Use
- "Fix the bug in <file>:<line>"
- "/espalier-fix <bug description>"
- "Bug: NPE at src/payment.ts:42"

Do NOT use for:
- Features ("add X") → use `/espalier feat: …`
- Refactors with no behaviour change → use `/espalier refactor: …`
- Fixes that obviously cross >5 files, multiple layers, or require schema changes → use `/espalier fix: …` directly (full pipeline)

## Pipeline Overview (7 stages (0–7, no Stage 2), vs 10 for /espalier)

| Stage | Name | Skipped from /espalier? |
|-------|------|-------------------------|
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
| `--slug <name>` | Override auto-derived slug (see Slug Derivation below). Literal — no date prefix added. Must match `^[a-z0-9][a-z0-9-]{0,90}$`; prefer `YYYY-MM-DD-<name>` to keep chronological sort. |
| `--caused-by <slug>` | Skip blame, explicit causal link (e.g. `--caused-by feat/bulk-export-endpoint`). |
| `--build-index` | Run `espalier/hooks/rebuild-commit-index.sh`, then continue normally. |
| `--rebuild-index` | Delete `espalier/.commit-index.tsv`, then run rebuild (forces fresh state). |
| `--no-index` | Bypass reverse-lookup cache for this invocation only (debug). |
| `--no-grill` | Skip the Stage 1 diagnosis grill for this invocation. |

Env vars:
- `ESPALIER_CACHE_THRESHOLD_MS=<ms>` — override the auto-build slow-scan threshold (default 1000ms; 0 = never warn). Legacy `HARNESS_CACHE_THRESHOLD_MS` also honored.

### Flag Handling (parsed at invocation entry)

Parse flags from the user's invocation string. Strip them out before deriving the slug from remaining text. Set the corresponding shell variables for Stage 0 / later stages to consume:

```bash
# Pseudo-shell of what the orchestrator must do before Stage 0:
SLUG_OVERRIDE=""
CAUSED_BY_OVERRIDE=""
NO_INDEX="no"
DO_BUILD_INDEX="no"
DO_REBUILD_INDEX="no"
GRILL_DISABLED="no"

# Walk tokens, extract flags
# (Orchestrator parses argv; below is the variable contract — not literal bash)
case "$flag" in
  --slug)          SLUG_OVERRIDE="$next_arg" ;;
  --caused-by)     CAUSED_BY_OVERRIDE="$next_arg" ;;
  --no-index)      NO_INDEX="yes" ;;
  --no-grill)      GRILL_DISABLED="yes" ;;
  --build-index)   DO_BUILD_INDEX="yes" ;;
  --rebuild-index) DO_REBUILD_INDEX="yes" ;;
esac

# Pre-Stage-0 actions
if [ "$DO_REBUILD_INDEX" = "yes" ]; then
  rm -f espalier/.commit-index.tsv
  bash espalier/hooks/rebuild-commit-index.sh
elif [ "$DO_BUILD_INDEX" = "yes" ]; then
  bash espalier/hooks/rebuild-commit-index.sh
fi

# Stage 0 then reads $NO_INDEX, $SLUG_OVERRIDE, $CAUSED_BY_OVERRIDE.
# Source helpers once:
. espalier/hooks/lookup-helpers.sh
```

The remaining (flag-stripped) text becomes the bug description fed to Slug Derivation step 2+.

## Slug & Path

- Slug derivation: see Slug Derivation section below. Summary: sanitize bug input → kebab-case ASCII `{kebab}` (max 80 chars), then date-prefix → `{slug}` = `{YYYY-MM-DD}-{kebab}`; `--slug <name>` overrides literally; collision prompts user.
- Path = `espalier/changes/fix/{slug}/` (e.g. `espalier/changes/fix/2026-06-02-npe-in-cart/`)
- All files inherit from `espalier/changes/_template/`.

## Slug Derivation

Steps 2–10 produce `{kebab}` (the deterministic identity tail). Step 10.5
date-prefixes it into the final `{slug}`. All steps are deterministic except
step 1 (override) and step 11 (collision prompt).

### Step 1: Override check
If user passed `--slug <name>`:
  - The override is **literal** — taken as the full `{slug}` verbatim, no date
    prefix is added (the user owns the whole name). To keep chronological sort,
    prefer passing `--slug YYYY-MM-DD-<name>`.
  - Validate: must match `^[a-z0-9][a-z0-9-]{0,90}$` (≤ 91 chars, kebab, starts
    non-hyphen). The wider cap leaves room for a `YYYY-MM-DD-` prefix.
  - If valid, skip to step 11 (collision check).
  - If invalid, error and exit with message showing the regex.

### Step 2: Strip type prefix
`fix: foo bar` → `foo bar`
`feat: ignored` → error (wrong skill — espalier-fix should only see fix-shape input)

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
If empty after sanitization (e.g., all-symbol input or ASCII-strip-emptied CJK), use
`{kebab}` = `fix-{HHMMSS}` (UTC time, e.g., `fix-143022`). Step 10.5 prepends the
date, giving a final slug like `2026-06-02-fix-143022` (no doubled date).

### Step 9: Reserved-name prefix
If slug ∈ {con, aux, nul, prn, com1..9, lpt1..9} (Windows reserved):
prefix with `fix-`

### Step 10: Leading-hyphen guard
If starts with hyphen (post-sanitization edge case): prefix with `x-`

This completes `{kebab}` (the deterministic identity tail).

### Step 10.5: Date prefix
Prepend the UTC creation date so change folders sort chronologically:

```bash
DATE="$(date -u +%Y-%m-%d)"   # ISO date — lexical sort == chronological sort
SLUG="${DATE}-${kebab}"       # e.g. 2026-06-02-npe-in-cart
```

`{slug}` = `{YYYY-MM-DD}-{kebab}`. The ISO date MUST be a *prefix* (a trailing
date does not sort). Reverse-lookup and the commit index derive their slug from
the folder basename, so the dated slug flows through unchanged.

### Step 11: Collision detection + prompt
Match by `{kebab}` **tail**, not exact `{slug}` — re-deriving on a later day
yields a new date prefix, so an exact match would miss an in-progress fix from a
prior day. Glob existing dirs and compare the part after the `YYYY-MM-DD-`:

```bash
shopt -s nullglob
matches=(espalier/changes/fix/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-"${kebab}")
```

For each match read its `pipeline-state.md` Status (and tombstones at
`<match>/TOMBSTONE.md`):

| Existing state | Action |
|----------------|--------|
| No tail match | Use `{slug}` (today's date + kebab). Done. |
| Match exists, Status: IN_PROGRESS | Resume that fix. Announce "Resuming fix/{matched-slug} from Stage {N}". |
| Match exists, terminal Status (COMPLETE / ABORTED / ABORTED_LATE / ESCALATED / ESCALATED_LATE) | **Prompt user** (below) — a same-name fix on a new day is usually a *new* dated folder, but confirm intent. |
| Match exists, Status: PARTIAL_FIX | **Prompt user** (below) |
| Match exists, Status: FILED | Offer to adopt/start it — the skeleton was filed by a partial fix; adopting = set `- Status: IN_PROGRESS` and begin at Stage 1 with its inherited frontmatter. |
| Only `TOMBSTONE.md` exists (legacy migration) | Follow tombstone pointer; ask user "fix/{matched-slug} was migrated to feat/{target}. New fix at fix/{slug}, or work on feat/{target} instead?" |

Collision prompt (use `AskUserQuestion`):

```
Slug collision detected.

Existing: espalier/changes/fix/{slug}/ — Status: {EXISTING_STATUS}
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

**Cross-branch slug collisions (merge-time).** The glob above sees only THIS
checkout's branch: two branches can mint the same dated slug independently
and collide only when the second PR merges — git surfaces it as add/add
conflicts under `espalier/changes/`. The resolution recipe lives in
`espalier/pipeline.md` → "Slug collisions across branches" (rename one dir to
the next free `-N` suffix, run `espalier/hooks/rebuild-commit-index.sh`, and
rewrite that slug in every `## Follow-up Fixes` table — all in one commit).

### Step 12: Final validation
- Confirm the dated slug matches `^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9][a-z0-9-]{0,79}$`
  (a `--slug` literal override that omits the date is instead allowed by the
  step-1 regex `^[a-z0-9][a-z0-9-]{0,90}$`).
- Confirm `espalier/changes/fix/{slug}/` is now creatable (does not exist OR was user-confirmed for reuse).

## Before Starting

1. Read `espalier/pipeline.md` for stage definitions (Stages 3-7 unchanged from /espalier).
2. Check session resumption:
   ```bash
   find espalier/changes/fix -mindepth 2 -maxdepth 2 -name pipeline-state.md
   ```
   Resume is status-driven, not stage-driven: Resume any change whose
   `- Status:` is `IN_PROGRESS`, at whatever stage its `Current Stage:`
   records — including a crash mid-Stage-7. Statuses `COMPLETE`, `ABORTED`,
   `ABORTED_LATE`, `ESCALATED`, `ESCALATED_LATE` are terminal — never resumed.
   `PARTIAL_FIX` keeps its existing prompt ('Resume / extend' offer — see the
   collision table, step 11). `FILED` skeletons are not resumed here; they are
   adopted by the full lane's FILED-skeleton scan.
3. If a matching `IN_PROGRESS` slug found, RESUME from its recorded stage.
4. Otherwise, derive slug (above) and create new `espalier/changes/fix/{slug}/`
   from `espalier/changes/_template/`. On creation, write `- Current Stage: 0`
   and `- Status: IN_PROGRESS` to the Status block — this is what the collision
   check (step 11) and Session Resumption read.

## Stage State Protocol (MANDATORY — every stage)

The fix lane uses the SAME per-stage state discipline as `/espalier` (its Stage
Execution Protocol). At the START of each stage below, before doing the stage's
work: write `- Current Stage: {N}` to this fix's pipeline-state.md and append a
Stage History row (timestamps via `date -u +%Y-%m-%dT%H:%M:%SZ` — full seconds,
so the stats duration report can measure spans; bookkeeping steps with no agent
in flight may batch into one bash invocation). This is not optional bookkeeping — the **Stage 7 push gate
blocks unless `Current Stage:` ≥ 7**, so a lane that never updates the stage
number cannot push its own clean work. `Status:` stays `IN_PROGRESS` from
creation until a terminal state (COMPLETE / ABORTED / ABORTED_LATE / ESCALATED /
PARTIAL_FIX) is written at the end. Stage numbers in this lane: 0, 1, 3, 4, 5,
6, 7 (2/8/9/10 are skipped — see the overview table; the gate only requires ≥ 7).

## Stage 0 Pre-Flight (drift + conventions + doctor)

Run this BEFORE Stage 0 Auto-Link Discovery. Source the drift helpers:

```bash
. espalier/hooks/drift-helpers.sh
```

Gather all three signals BEFORE prompting:
1. **STALE** — `stale_files()` lists flagged files; `tier_counts()` buckets them
   into fresh / aging / stale / critical / expired.
2. **CONV** — `conv_fold` (in `drift-helpers.sh`) folds the legacy
   `espalier/.conventions.tsv` AND any `espalier/conventions/*.tsv` per-key
   files into `key<TAB>diverges_count<TAB>status` lines; every key with status
   `diverges` and `diverges_count` >= 3 is a promotion candidate. Do not parse
   the files yourself.
3. **DOCTOR** — `doctor_due()`. Skip if `/espalier-doctor` is not installed.

If all three are empty/false → no prompt, continue to Stage 0 Auto-Link Discovery.
Otherwise issue ONE `AskUserQuestion` summarising all three:

```
Pre-flight found:
  - {N} stale doc(s): {tier breakdown}
  - {M} convention(s) over the promotion threshold
  - doctor scan due ({cadence})
Options:
  1. Handle now — run /espalier-prune + review conventions, then resume
  2. Proceed    — continue the pipeline with current docs
  3. Abort
```

Default: **"Proceed"**, with a one-line pointer in the prompt — "weekly
maintenance handles this (gardener rota — see /espalier-prune's
Multi-Developer Discipline)". "Handle now" stays available and becomes the
default ONLY when a critical/expired flag is present — the drift sidecar is
per-clone, so a critical/expired row here is YOUR OWN flag (the prune
escape-hatch case). If only fresh (<14d) stale docs and no conv/doctor
signal → treat as empty.

**Unattended runs (never prompt here):** when `interactivity_mode` (in
`drift-helpers.sh`) returns `unattended`, do NOT issue the pre-flight
question. Write the three-signal summary to `espalier/.drift-report.md`,
print ONE line, and continue to THIS LANE's own **Stage 0 Auto-Link
Discovery** below (not Stage 1 — that is the full pipeline's next stage, not
the fix lane's). Never prune, never promote, never run a doctor scan
unattended.

For a `pattern_key` at the promotion threshold (>= 3 deduped `diverges`
observations per `conv_fold`), handle it per the `espalier` skill's Convention
Promotion section — the same four options (promote / reject / exception /
wait), the same branch lane (deciding on your feature branch is fine, as its
own isolated `docs:` commit — CODEOWNERS routes the rules PR to the owner at
merge), and the same fetch race guard run before the prompt.

## Stage 0: Auto-Link Discovery (NEW)

Self-contained below — this skill ships into the target project and cannot read
any external plan. Stage 0 turns the bug input into a set of blamed commit SHAs
(`SHAS` array), then resolves each to the change that introduced it.

### 0.1 Parse user input for a bug anchor

Priority order (try each until one succeeds):

| Priority | Source | Example | Extracts |
|----------|--------|---------|----------|
| 1 | `--caused-by <slug>` flag | `/espalier-fix --caused-by feat/bulk-export NPE...` | slug directly, skip blame |
| 2 | `file:line` pattern in bug text | `src/payment.ts:42` | file, line |
| 3 | Stack trace block | `at handler (src/auth.ts:88:14)` | list of file:line frames |
| 4 | Bare file path | `bug in src/payment.ts` | file only |
| 5 | Symbol name | `bug in processPayment function` | symbol → grep matches → file:line |
| 6 | No anchor at all | "checkout is broken" | prompt user |

### 0.1a Resolve anchors to blamed SHAs (`SHAS` array)

The `SHAS` array (index 0 = primary, consumed by 0.2) is built as follows. If
`--caused-by` was given, skip blame entirely: `SHAS=()` and use the flag slug.

```bash
SHAS=()   # blamed commit SHAs, primary first

_blame_line() {   # file, line -> append the commit that last touched that line
  local file="$1" line="$2"
  [ -f "$file" ] || return 0
  local sha
  sha=$(git blame -L "${line},${line}" --porcelain -- "$file" 2>/dev/null | awk 'NR==1{print $1}')
  # skip an uncommitted line (all-zero SHA) — nothing to link
  case "$sha" in ""|0000000*) return 0 ;; esac
  SHAS+=("$sha")
}

# Priority 2 — file:line
_blame_line "$FILE" "$LINE"

# Priority 3 — stack trace: blame each frame in order (primary = top frame)
#   FRAMES is an array of "file:line" parsed from the trace block.
for frame in "${FRAMES[@]}"; do
  _blame_line "${frame%%:*}" "${frame##*:}"
done

# Priority 4 — bare file (no line): blame the file's most recent commit
if [ -n "$FILE" ] && [ -z "$LINE" ]; then
  sha=$(git log -1 --format=%H -- "$FILE" 2>/dev/null)
  [ -n "$sha" ] && SHAS+=("$sha")
fi

# Priority 5 — symbol: grep the repo; blame EACH match (not just the first — a
# first-match-only guess silently mislinks). Cap at the Stage-0 fan-out of 5.
if [ -n "$SYMBOL" ]; then
  while IFS=: read -r mfile mline _; do
    [ -n "$mfile" ] && _blame_line "$mfile" "$mline"
    [ "${#SHAS[@]}" -ge 5 ] && break
  done < <(grep -rnI --exclude-dir=.git -e "$SYMBOL" . 2>/dev/null | head -5)
fi
```

De-duplicate `SHAS` preserving order (primary wins) before 0.2 consumes it. If
`SHAS` is empty after all anchors AND no `--caused-by`, this is the priority-6
"no anchor" case — prompt the user (or proceed with an empty `caused_by` list on
a headless run; a fix with no causal link is valid, just unlinked).

### 0.2 Tiered reverse-lookup chain

Per-SHA lookup runs through Layers 0-3. `espalier/.merge-hook-decision`
(written at `/espalier-init` time) governs Layer 3.

> Prerequisite: source helpers once before this block runs (also done by Flag Handling section):
> `. espalier/hooks/lookup-helpers.sh`

Resolve `ask-later` UPFRONT so the inner loop never hits a prompt. The bash
below only DETECTS the decision (same pattern as the Stage 5/6 detectors —
bash detects, the orchestrator prompts). If it reads `ask-later` (or the file
is absent) AND `interactivity_mode` (from `drift-helpers.sh`) is NOT
`unattended`, YOU (the orchestrator) ask via `AskUserQuestion` — the same
choices the init-time question offers (options: `installed` /
`fuzzy-allowed` / `skip-only` / `not-needed`; keeping `ask-later` stays
available via Other) — then write the answer to
`espalier/.merge-hook-decision` yourself and re-run this resolution block. On
an unattended run, keep the `ask-later` behavior (dispatch as `skip-only`, so
entries link as `unknown_squash`) and log one line that the decision was
deferred. (The legacy stderr prompt helper stays in `lookup-helpers.sh` for
unattended/non-Claude use — it is no longer called from this flow.)

```bash
DECISION=$(cat espalier/.merge-hook-decision 2>/dev/null || echo "ask-later")

# ask-later on an unattended run: dispatch conservatively as skip-only.
# Interactive runs never reach here with ask-later — the orchestrator resolved
# it via AskUserQuestion and rewrote the file before re-running this block.
if [ "$DECISION" = "ask-later" ] || [ -z "$DECISION" ]; then
  echo "merge decision still ask-later (unattended) — linking conservatively; entries mark unknown_squash" >&2
  DECISION="skip-only"
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

  # Layer 0: cache hit (fast path)
  if [ "$NO_INDEX" != "yes" ] && [ -f "espalier/.commit-index.tsv" ]; then
    CACHE_HIT=$(grep "^$SHA	" espalier/.commit-index.tsv 2>/dev/null | head -1)
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
  SLUG=$(grep -lr "$SHA" espalier/changes/*/*/pipeline-state.md 2>/dev/null \
         | head -1 | sed 's|espalier/changes/||; s|/pipeline-state.md||')
  _maybe_warn_slow_scan "$SCAN_START"
  if [ -n "$SLUG" ]; then
    _push_entry "$SLUG" "$SHA" "$ROLE" "exact"
    _cache_append "$SHA" "$SLUG" "original"
    continue
  fi

  # Layer 2: hook-recorded squash mapping (self-heal cache)
  SCAN_START=$(date +%s%N 2>/dev/null || date +%s)
  SLUG=$(grep -lr "squashed_to: $SHA" espalier/changes/*/*/pipeline-state.md 2>/dev/null \
         | head -1 | sed 's|espalier/changes/||; s|/pipeline-state.md||')
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
`_fuzzy_file_overlap_match`, `_cache_append`, `_maybe_warn_slow_scan`) live in
`espalier/hooks/lookup-helpers.sh` and are sourced at Stage 0 entry.

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
- Read `espalier/changes/{slug}/requirements.md` (original intent)
- Read `espalier/changes/{slug}/coding-report.md` (what shipped)
- Read `espalier/changes/{slug}/review-record.md` (predicted concerns — especially dismissed P2/P3)

If combined linked context > 8K tokens, summarize each linked change to acceptance-criteria + open P2/P3 findings only. Full files available via Read on demand during Stage 3.

### 0.5 Record Stage 0 outcome

Append to pipeline-state.md Stage History:

```markdown
| 0 | PASSED | {ISO timestamp} | Auto-linked to {N} change(s): {list}. Anchor: {file:line|stack|flag|symbol|skipped}{; cap reached if applicable} |
```

## Stage 1: Bug Requirements (slimmer than feat reqs)

Write `espalier/changes/fix/{slug}/requirements.md`:

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

## Root Cause
{the confirmed cause — file:line and why. Populated by the Stage 1 grill
(diagnosis mode); use "unconfirmed — <hypothesis>" only if grilling could not
verify it against the code}

## Files likely touched
- {bulleted paths — best pre-code estimate}

## Layers involved
- {list of layers the fix will touch}

## Expected behaviour
{what should happen instead}

## Acceptance criteria
- [ ] Bug no longer reproduces with steps above
- [ ] Regression test added in tests/{matching path}
- [ ] Original feature (per caused_by) still works

## Out of scope
{anything reporter asked for that isn't this specific bug}
```

Fill `## Files likely touched` and `## Layers involved` from the diagnosis —
they are the Stage 1 predictive escalation gate's inputs (Files predicted /
Layers predicted), so a best pre-code estimate is mandatory, not optional.

**Grill the diagnosis.** Unless the invocation passed `--no-grill`
(`GRILL_DISABLED=yes`), invoke the `espalier-grill` skill in `diagnosis` mode once
the draft above is written. Grill interrogates the root cause and reproduction
(adaptive depth — a well-anchored bug with a clean repro is skipped), verifies the
claimed cause against the code, and writes its findings into the `## Root Cause`
and `## Reproduction` sections. Record its verdict for pipeline-state.md.

**Escalation Gate (Stage 1):** see "Escalation Gates" section below.

## Requirements Approval Gate (BLOCKING — before Stage 3 Coding)

MANDATORY. After Stage 1 writes `requirements.md` and the diagnosis grill
resolves the root cause, STOP. Do NOT chain straight into Stage 3 coding — that
is the bug this gate closes. No code has been written yet; get explicit user
sign-off first.

**Order:** run the Stage 1 Escalation Gate FIRST (it may migrate the fix to the
feat lane). Only if the fix stays in-lane does this approval gate fire.

1. Present a concise summary: the one-line bug, confirmed root cause (file:line),
   reproduction, and acceptance criteria.
2. Ask with `AskUserQuestion`:

   ```
   Bug diagnosed and requirements written. Nothing has been coded yet.
   Approve to start Stage 3 (Coding)?

   Options:
     1. Approve — proceed to the fix.
     2. Edit    — tell me what to change; I revise requirements.md and re-ask.
     3. Abort   — stop here; leave requirements.md as a draft (Status: ABORTED).
   ```

3. In the SAME `AskUserQuestion` call, add a second question collecting the
   Stage 7 push authorization (mirror of the full lane's gate): pre-authorize
   `{current branch} → {default remote}`, specify another target, or "Ask me
   again at Stage 7". Record it as `- Push-Target: {target | ASK}` in
   pipeline-state.md. Stage 7 then pushes a pre-authorized target without
   re-prompting — every programmatic gate, the pre-push hook, and the
   certificate check still apply; `ASK` or a missing line prompts at Stage 7
   as before.

4. Advance to Stage 3 ONLY on **Approve**. On **Edit**, revise and re-ask. On
   **Abort**, write Status: ABORTED and stop.

**Non-interactive exception:** auto-approve ONLY when EXPLICITLY unattended —
`interactivity_mode` (in `drift-helpers.sh`) returns `unattended` (`CI` /
`ESPALIER_UNATTENDED` / `ESPALIER_LOOP` / `ESPALIER_HEADLESS` set). Do NOT use a
bash TTY test: stdin has no TTY inside Claude Code even with the user present, so
a TTY check would auto-approve every interactive fix — defeating the gate. If you
can call `AskUserQuestion`, you ARE interactive and MUST prompt. Only a genuinely
headless run auto-approves (record it in the Stage History).

## Stage 3: Coding

**Context pack (first entry only):** before the first coder spawn, write
`espalier/changes/fix/{slug}/context-pack.md` — the fix-lane version is
small: the requirement path, the layers involved and their spec paths (both
already in requirements.md's `## Layers involved` / `## Files likely
touched`), the four rules files, 1-2 reference files per touched layer, and
the discovered build/lint/test commands. Paths and facts only, never
conclusions — every Stage 3-6 spawn below is pointed at it so no sub-agent
re-derives the same discovery; agents verify against current code (see the
espalier skill → "Stage 3 Entry: Context Pack" for the format).

**Baseline (first entry only):** before spawning the coder, record
`Base-Ref: $(git rev-parse HEAD)` as a line in this fix's pipeline-state.md. Never
overwrite it on a coder re-spawn — it anchors the Stage 4/6 review fingerprint,
the push gate, AND the Stage 5 regression-test verification against pre-fix code.

Spawn sub-agent. Prompt:

```
You are the harness-coder.
Read espalier/agents/harness-coder.md for full instructions.

CONTEXT PACK: espalier/changes/fix/{slug}/context-pack.md — read it first;
paths and facts only, verify against current code.
REQUIREMENT: {paste requirement summary from Stage 1}
CAUSED BY: {caused_by list — read those changes' requirements + coding-report + review-record}
TASK: Fix the bug described above. Stay within the file(s) identified.

When done, write your coding report to:
espalier/changes/fix/{slug}/coding-report.md
```

**Stage 3 exit gate (PROGRAMMATIC):** after the coder returns (first pass and
every re-spawn), re-run the discovered build + lint yourself; both must exit 0
before the panel spawns. The coder's self-reported status is a claim, not the
gate. A failure returns to the coder without a panel round.

**Escalation Gate (Stage 3):** see "Escalation Gates" section below.

## Stage 4: Code Review (fixpoint loop — a two-agent panel, re-review after EVERY fix)

Run Stage 4 as a loop, not a single pass. Every round runs TWO fresh agents on the
CURRENT diff, spawned concurrently — `harness-reviewer` (correctness / conventions /
production readiness, → review-record.md) and `harness-security` (trust boundary —
never trust frontend data, → security-record.md). BOTH records are OVERWRITTEN each
round and end with a `VERDICT:` sentinel line. Before every panel spawn, run the
Stage 3 programmatic gate: re-run the discovered build + lint commands yourself —
the coder's self-report is a claim, not the gate; a failure goes back to the coder
without spawning the panel and without counting a P0 round.

1. **Baseline BOTH records** (`espalier/changes/fix/{slug}/review-record.md` and
   `.../security-record.md` — exists? size/mtime), then spawn the FRESH panel on
   the CURRENT diff in ONE message. Pass each agent the `CONTEXT PACK:` line
   (`espalier/changes/fix/{slug}/context-pack.md` — read first; paths and
   facts only, verify against current code), `ROUND: {n}`, AND the
   `CAUSAL CONTEXT` line (the `caused_by` slugs + "verify the fix does not
   regress these features' acceptance criteria — read their requirements.md")
   so the regression check reaches the reviewer at Stage 4, not only at Stage 6.
   On a re-review round, also hand each agent the "changed since last review" set
   (the fix's files from the latest coding-report.md) — the panel re-reviews in
   DELTA SCOPE (fix files + prior findings + direct dependents as required
   reads; a floor, not a ceiling — expand on any suspicion; security runs
   delta mode when its own prior round was clean — see each agent's
   "Re-review Rounds" section). Both agents still return fresh current-round
   sentinels and still own the whole-change verdict: every line of the final
   diff got a fresh review in the round it last changed, build/lint re-runs
   before every round, and the fingerprint blocks unreviewed edits at push.
2. **Completion check — BOTH files.** Each record must exist, differ from its
   baseline, and end with a `VERDICT:` sentinel carrying `round={n}`. A missing,
   unchanged, or sentinel-less record means that agent did NOT complete —
   re-spawn that agent (once; a second failure → escalate). Never treat a
   missing/stale record as a pass.
3. **Gate read (deterministic).** From EACH record:
   `V=$(grep '^VERDICT:' <record> | tail -1)`. Parse the verdict WORD and the counts.
   - `ESCALATION_REQUIRED` (either agent, either lane, any stage) → do NOT
     advance and do NOT re-spawn: snapshot the sentinel, then run the escalation
     protocol (fix lane: the late-escalation prompt; full lane: escalate to the
     human with the agent's Escalation Reason block). An `ESCALATION_REQUIRED`
     with `p0=0` is still an escalation.
   - Verdict word `FAIL`, or `p0=` > 0, or `p1=` > 0 → re-spawn `harness-coder`
     with the combined findings and loop (counter + `max-code-rounds` cap
     unchanged): snapshot both sentinels into pipeline-state.md Stage History,
     re-spawn with the combined findings, then **return to step 1 and re-review
     the new diff with the whole panel.** Never advance to Stage 5 on the
     coder's fix report alone — a fix is never the last action before the gate;
     a clean panel is. Each non-PASS round increments the counter. Check the cap
     BEFORE re-spawning: if the counter already equals `max-code-rounds`
     (default 3, read from `espalier/.espalier-config` via
     `grep '^max-code-rounds:' espalier/.espalier-config | grep -oE '[0-9]+'`;
     fall back to 3 if unset), escalate to the human immediately — the coder is
     NOT re-spawned and no further panel round runs. Before stopping, set
     `- Status: ESCALATED` and add a Stage History row
     `| 4 | ESCALATED | {ts} | {reason, round count} |` in pipeline-state.md.
     Otherwise re-spawn, increment the counter, and loop. (A security P0/P1
     shares this counter.)
   - Advance ONLY when EVERY record's last sentinel has verdict word `PASS` or
     `PASS_WITH_FIXES` AND `p0=0` AND `p1=0` on the current code.
4. **Both last sentinels PASS/PASS_WITH_FIXES with p0=0 p1=0 on a fresh review
   of the current code →** PASS. Snapshot
   the sentinels into Stage History, then record the certificate: `git add -A`
   (so new files count), then overwrite `Reviewed-Diff` in pipeline-state.md with
   `Reviewed-Diff: $(git diff <Base-Ref> -- . ':(exclude)espalier/' | git hash-object --stdin)`
   (`<Base-Ref>` = the Stage 3 SHA). The Stage 7 push gate blocks unless this still matches.

Special check for fix lane: reviewer MUST verify the fix doesn't regress the
original feature's acceptance criteria (read from `caused_by` change's `requirements.md`).
A bug fix is a prime place to REINTRODUCE a trust-boundary hole — `harness-security`
treats the fix diff as hostile-input surface exactly as it would a feature, and
emits the `## Security-Sensitive Fields` abuse-test contract for Stage 5/6.

### Stage 4 Post-Review: Drift & Convention Index

After Stage 4 PASSES (step 4 above — BOTH sentinels p0=0, certificate written),
parse `review-record.md` for Convention Drift blocks (see `harness-reviewer.md`)
and flag the affected rule files. Run this BEFORE Stage 6 (which overwrites
review-record.md). Do NOT run it on a P0 round.

> Variable in scope: `SLUG` is this fix's slug (no `fix/` prefix).

```bash
. espalier/hooks/drift-helpers.sh
REV="espalier/changes/fix/${SLUG}/review-record.md"
[ -f "$REV" ] || exit 0
SHA=$(git rev-parse HEAD)

python3 espalier/hooks/parse-drift-blocks.py "$REV" \
| while IFS=$'\t' read -r KIND RULE_FILE COUPLED; do
  case "$KIND" in
    DRIFT)
      mark_stale "$RULE_FILE" "$SHA" "convention drift flagged in fix/${SLUG} review"
      LINE="convention_drift: $RULE_FILE"
      [ -n "$COUPLED" ] && LINE="$LINE (coupled_with: $COUPLED)"
      echo "$LINE" >> "espalier/changes/fix/${SLUG}/pipeline-state.md"
      ;;
    MALFORMED)
      echo "convention_drift_malformed: $RULE_FILE (reviewer bundled blocks — drift NOT indexed)" \
        >> "espalier/changes/fix/${SLUG}/pipeline-state.md"
      ;;
  esac
done
```

A `MALFORMED` line means the reviewer bundled unrelated drifts into one block.
Stage 4 has already PASSED when this parse runs — record it in pipeline-state.md
and surface one line to the user; never write a fake P0 into review-record.md
(it would contaminate the Stage 6 gate read).

**Convention Observations → the convention index.** The reviewer also emits
lower-bar Convention Observations (see `harness-reviewer.md`) — one per
divergence, with NO aggregation key. The orchestrator assigns the key. For each
Observation in `review-record.md`:

1. Read existing keys: `. espalier/hooks/drift-helpers.sh && conv_fold | cut -f1`
   (folds the legacy file AND the per-key files — never parse them yourself).
2. Map the Observation's `description` to an existing `pattern_key`, or mint a
   new kebab-case key.
3. Append the row:

```bash
. espalier/hooks/drift-helpers.sh
append_convention "fix/${SLUG}" "$PATTERN_KEY" "$LOCATION"
```

`append_convention` sanitizes every field and de-dupes on
(change_slug, pattern_key, location). Convention state is tracked and
row-append-only — columns `date · change_slug · pattern_key · location · status`.
When a `pattern_key` reaches 3 deduped `diverges` observations (per `conv_fold`)
it is a promotion candidate, surfaced at the next Stage 0 pre-flight.

## Stage 5: Test Writing

Spawn `harness-coder` in testing mode:

```
You are the harness-coder in TESTING MODE.
Read espalier/agents/harness-coder.md AND espalier/skills/espalier-testing/SKILL.md.

CONTEXT PACK: espalier/changes/fix/{slug}/context-pack.md — read it first;
paths and facts only, verify against current code.
WHAT WAS BUILT: Read espalier/changes/fix/{slug}/coding-report.md.
ORIGINAL CAUSE (for regression test scope): {paste caused_by entries}

Write tests for the fix. Required:
1. A regression test that reproduces the original bug (must FAIL on the
   pre-fix code; PASS on the current code — the orchestrator verifies the
   FAIL half mechanically against Base-Ref after you return).
2. A test from the original feature's spec (proves the causing feature
   still works — read its requirements.md acceptance criteria).
3. For EVERY entry in espalier/changes/fix/{slug}/security-record.md's
   `## Security-Sensitive Fields` contract (if present), the negative abuse
   test it names: tamper the value → assert rejected → assert store unchanged.
4. For every NEW external-call path the fix introduced, a failure-mode test
   (dependency times out / errors → decided failure behaviour, no partial
   write) per espalier/rules/production-standards.md.

If a meaningful test requires touching files OUTSIDE the fix's scope (>2
additional files or crossing a layer boundary), append the Test Scope
Signal block to your coding-report.md per harness-coder.md instructions —
do NOT silently expand scope.

Append test results to: espalier/changes/fix/{slug}/coding-report.md
```

After sub-agent returns, run the detector:
```bash
COD="espalier/changes/fix/${SLUG}/coding-report.md"
if grep -q "^- TEST_SCOPE_INFLATION: true" "$COD"; then
  echo "LATE_ESCALATION_GATE: stage=5 (test scope inflation)"
fi
```

A `LATE_ESCALATION_GATE:` line on stdout means STOP and run the
"Stage 5/6 Late-Escalation Prompt" (below) with that stage's context. The
prompt is an `AskUserQuestion` the orchestrator issues — a human gate, not a
shell helper; the bash above only detects, it never prompts.

### Stage 5 regression verification (PROGRAMMATIC — proves the test earns its keep)

A regression test that passes on BOTH the fixed and the pre-fix code proves
nothing — and a test that merely ERRORS at `Base-Ref` (missing deps in a fresh
worktree, unresolvable import, bad invocation) proves nothing either: "could
not run" is not "captured the bug". Verify in two steps, both SCOPED to only
the new regression test file(s):

1. Run the scoped invocation on the FIXED tree. It must pass — this validates
   the command itself (runner found, deps resolve, file loads) before any
   pre-fix conclusion is drawn.
2. Run the same scoped invocation at `Base-Ref` in a detached worktree. A
   genuine assertion failure there → `true`. A harness error there → `skipped`
   (the reviewer verifies the assertions by reading), NEVER `true`.

Set `REG_RUN` to the project's test runner limited to exactly `$REG_TESTS` —
most runners accept file paths directly; npm-style runners need `--`
(e.g. `npx jest <files>`, `pytest <files>`, `npm test -- <files>`,
`go test ./path/to/pkg/`). Record the result in coding-report.md; the reviewer
reads it at Stage 6.

```bash
BASE_REF=$(grep '^Base-Ref:' "espalier/changes/fix/${SLUG}/pipeline-state.md" | tail -1 | awk '{print $2}')
COD="espalier/changes/fix/${SLUG}/coding-report.md"
REG_TESTS="{the regression test file(s) the coder just wrote}"   # from coding-report.md
REG_RUN="{the project's test runner scoped to ONLY $REG_TESTS — see above}"

# Harness failure (couldn't run) vs assertion failure (ran and failed) —
# conflating them is how a test that never executed gets certified.
_reg_harness_error() {   # <output-file> → exit 0 if the run failed to RUN at all
  grep -qiE 'cannot find module|module ?not ?found|no such file or directory|command not found|ENOENT|ImportError|ModuleNotFoundError|SyntaxError|failed to (resolve|load|collect)|no tests? (found|ran)' "$1"
}

if [ -z "$BASE_REF" ]; then
  echo "- REGRESSION_VERIFIED: skipped — no Base-Ref recorded" >> "$COD"
else
  # Step 1 — scoped run on the FIXED tree validates the invocation itself.
  OUT_NOW=$(mktemp)
  $REG_RUN > "$OUT_NOW" 2>&1
  RC_NOW=$?
  if [ $RC_NOW -ne 0 ] && _reg_harness_error "$OUT_NOW"; then
    echo "- REGRESSION_VERIFIED: skipped — scoped invocation could not run on the fixed tree: $(grep -m1 . "$OUT_NOW")" >> "$COD"
  elif [ $RC_NOW -ne 0 ]; then
    echo "- REGRESSION_VERIFIED: false — regression test FAILS on the FIXED code (broken test or unfixed bug) (P0 at Stage 6)" >> "$COD"
  else
    # Step 2 — same scoped run at the pre-fix commit, in a detached worktree.
    WT=$(mktemp -d)
    if git worktree add --detach "$WT" "$BASE_REF" >/dev/null 2>&1; then
      for t in $REG_TESTS; do mkdir -p "$WT/$(dirname "$t")"; cp "$t" "$WT/$t"; done
      # Link installed dep dirs — a fresh worktree has none, and a bare run
      # would fail for that reason alone and fake a 'true'.
      for dep in node_modules .venv venv vendor; do
        [ -e "$dep" ] && [ ! -e "$WT/$dep" ] && ln -s "$(pwd)/$dep" "$WT/$dep"
      done
      ( cd "$WT" && $REG_RUN ) > "$WT/.reg.out" 2>&1
      RC_PRE=$?
      if [ $RC_PRE -eq 0 ]; then
        echo "- REGRESSION_VERIFIED: false — test PASSES on pre-fix code; it does not capture the bug (P0 at Stage 6)" >> "$COD"
      elif _reg_harness_error "$WT/.reg.out"; then
        echo "- REGRESSION_VERIFIED: skipped — could not RUN at Base-Ref (harness error, not an assertion failure): $(grep -m1 . "$WT/.reg.out")" >> "$COD"
      else
        echo "- REGRESSION_VERIFIED: true (test fails on pre-fix $BASE_REF, passes on fix)" >> "$COD"
      fi
      git worktree remove --force "$WT" >/dev/null 2>&1
    else
      echo "- REGRESSION_VERIFIED: skipped — could not create worktree at $BASE_REF" >> "$COD"
      rm -rf "$WT"
    fi
  fi
  rm -f "$OUT_NOW"
fi
```

A `REGRESSION_VERIFIED: false` is a P0 the Stage 6 reviewer must catch — the
"regression test" does not reproduce the bug (or fails on the fixed code) and
would not catch a recurrence. `skipped` keeps its existing Stage 6 meaning:
the reviewer verifies the assertions capture the bug by reading them. (One
deliberate bias: a bug whose pre-fix symptom IS a load-time error — e.g. the
fix repairs a syntax error — classifies as `skipped`, not `true`; the check
errs toward human eyes, never toward false certification.)

## Stage 6: Test Review

Spawn `harness-reviewer`:

```
You are the harness-reviewer reviewing tests for a fix.
Read espalier/agents/harness-reviewer.md.

CONTEXT PACK: espalier/changes/fix/{slug}/context-pack.md — read it first;
paths and facts only — your verdict comes from the tests you read.
REVIEW: tests added in coding-report.md at espalier/changes/fix/{slug}/.
CAUSAL CONTEXT: this fix is caused by {paste caused_by entries}. Verify the
tests don't regress those original features (read their acceptance criteria).
ROUND: {n} — put round={n} in your VERDICT sentinel line.
{On round ≥ 2 add:} CHANGED SINCE LAST REVIEW: {the test files the Stage 5
fix re-spawn touched, from the latest coding-report.md}. Re-review in delta
scope per your "Re-review Rounds" section.

Check:
- Regression test would have failed on pre-fix code. The orchestrator recorded
  `- REGRESSION_VERIFIED: {true|false|skipped}` in coding-report.md from a
  Base-Ref worktree run. `false` → P0 (the test does not capture the bug).
  `skipped` → verify the assertions capture the bug by reading them. Your job is
  that the ASSERTIONS are meaningful, not tautological.
- Original feature's acceptance criteria still pass
- No tests are tautological (asserting the fix's masked behaviour instead of intended)
- Security coverage: every field in security-record.md's `## Security-Sensitive
  Fields` contract has a passing abuse test (tamper → rejected → store unchanged).
  A missing one is a P0 → back to Stage 5.
- Failure-mode coverage: every NEW external-call path has a dependency-failure
  test (per espalier/rules/production-standards.md). A missing one is a P1.

If the fix is correct given its current scope BUT the scope itself is wrong
(symptom-mask, wrong layer, architectural concern), emit verdict
ESCALATION_REQUIRED with the required Escalation Reason block.

Write (OVERWRITE) review to: espalier/changes/fix/{slug}/review-record.md
End the file with your VERDICT sentinel line.
```

After sub-agent returns (sentinel first; legacy `**Verdict:**` kept as fallback):
```bash
REV="espalier/changes/fix/${SLUG}/review-record.md"
if grep -qE '^VERDICT: ESCALATION_REQUIRED|^\*\*Verdict:\*\* ESCALATION_REQUIRED' "$REV"; then
  echo "LATE_ESCALATION_GATE: stage=6 (reviewer flagged ESCALATION_REQUIRED)"
fi
```

Same contract as Stage 5: a `LATE_ESCALATION_GATE:` line means STOP and run the
"Stage 5/6 Late-Escalation Prompt" (below) via `AskUserQuestion`, handing it the
reviewer's Escalation Reason block. Detection is bash; the prompt is yours.

**Fixpoint + certificate.** Stage 6 is a loop like Stage 4: freshness-check
review-record.md against its baseline each round, snapshot each round's
sentinel into Stage History.

**Gate read (deterministic).** From EACH record:
`V=$(grep '^VERDICT:' <record> | tail -1)`. Parse the verdict WORD and the counts.
- `ESCALATION_REQUIRED` (either agent, either lane, any stage) → do NOT advance
  and do NOT re-spawn: snapshot the sentinel, then run the escalation protocol
  (fix lane: the late-escalation prompt; full lane: escalate to the human with
  the agent's Escalation Reason block). An `ESCALATION_REQUIRED` with `p0=0` is
  still an escalation.
- Verdict word `FAIL`, or `p0=` > 0, or `p1=` > 0 → send the tests back to
  Stage 5 (re-spawn `harness-coder`) with the combined findings and loop
  (counter + `max-test-rounds` cap unchanged), then **re-review** — never exit
  on the fix report alone.
- Advance ONLY when EVERY record's last sentinel has verdict word `PASS` or
  `PASS_WITH_FIXES` AND `p0=0` AND `p1=0` on the current code.

Check the cap BEFORE re-spawning: if the counter already equals
`max-test-rounds` (default 3), escalate to the human immediately — the coder is
NOT re-spawned and no further panel round runs. Before stopping, set
`- Status: ESCALATED_LATE` (the fix's code is already committed at Stage 3, so
a Stage 6 escalation is the late-escalation path) and add a Stage History row
`| 6 | ESCALATED | {ts} | {reason, round count} |` in pipeline-state.md.
Otherwise re-spawn, increment the counter, and loop. On a clean PASS
(per the gate read above), refresh `Reviewed-Diff` in pipeline-state.md (same
`git add -A` + fingerprint command as Stage 4) so it now covers the added
tests; the push gate compares against this.

## Stage 7: Push (with back-link)

### 7.0 Stage the convention index

If this run appended an observation (Stage 4) or flipped a status, stage the
per-key files BEFORE the push commit so the tracked state lands in this fix's
commit and the Stage 7 clean-tree gate stays green:

```bash
[ -d espalier/conventions ] && git add espalier/conventions/
```

(The legacy `espalier/.conventions.tsv` is read-only to this plugin version —
never written, nothing to stage.)

Standard push. Then:

> Variables in scope for all Stage 7 snippets: `SLUG` (this fix's slug, no `fix/` prefix), and the per-entry `CAUSING_SLUG` / `CAUSING_ROLE` / `CAUSING_LOOKUP` parsed from each `caused_by:` block in this fix's `requirements.md`. The orchestrator sets these before executing.

### 7.1 Record own commit

Same as `/espalier` Stage 7 — append row to own pipeline-state.md `## Commits` table. Also self-heal the reverse-lookup cache:

```bash
. espalier/hooks/lookup-helpers.sh
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
# This block runs ONCE PER ENTRY as its own bash invocation (the loop lives in
# the orchestrator, above) — so early-outs are `exit 0`, never `continue`
# (bare `continue` outside a loop is a no-op warning and execution falls through).
CAUSING_STATE="espalier/changes/${CAUSING_SLUG}/pipeline-state.md"
[ ! -f "$CAUSING_STATE" ] && exit 0

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
  exit 0
fi

# The title line sits BELOW the YAML frontmatter — grep it; head -1 would read `---`.
REASON=$(grep -m1 '^# Bug:' "espalier/changes/fix/${SLUG}/requirements.md" | sed 's/^# Bug: //')
[ -z "$REASON" ] && REASON="fix/${SLUG}"
DATE=$(date -u +%Y-%m-%d)
echo "| $OWN_SLUG | $CAUSING_ROLE | $CAUSING_LOOKUP | $REASON | $DATE |" >> "$CAUSING_STATE"
```

## Escalation Gates

Four gates: predictive (Stage 1), reactive (Stage 3), test-scope (Stage 5), reviewer-flagged (Stage 6).

### Stage 1 Gate (predictive)
After reqs written, parse for:
| Signal | Threshold | Source |
|--------|-----------|--------|
| Files predicted | > 5 | requirements.md "## Files likely touched" (mandatory Stage 1 section) |
| Layers predicted | > 2 | requirements.md "## Layers involved" (mandatory Stage 1 section) |
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
  1. Escalate to /espalier (recommended) — rename fix/{slug} → feat/{slug}-fix,
     preserve caused_by + add escalated_from, reset Current Stage to 1.
  2. Continue as fix (override) — document override reason; accept risk.
  3. Abort — leave fix/{slug} as-is, Status: ABORTED.
```

Migration mechanics: `mv espalier/changes/fix/{slug} → espalier/changes/feat/{slug}-fix`;
mutate frontmatter (`type: feat`, `escalated_from: fix/{slug}`); reset Current Stage; hand off via `/espalier --resume`.

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
         resume via /espalier --resume
  3. Ship as partial fix + file root-cause feat
       → Continue to Stage 7; Status: PARTIAL_FIX
       → AFTER Stage 7's push completes, auto-create the
         espalier/changes/feat/{slug}-root-cause/ skeleton with
         filed_from_partial_fix + inherited caused_by, `- Status: FILED`
       → User invokes /espalier feat: ... later (or the full lane's
         FILED-skeleton scan adopts it)
```

If the run is unattended (the prompt cannot fire) or the user declines all
three options and hands the problem to a human, stop the lane: before
stopping, set `- Status: ESCALATED_LATE` and add a Stage History row
`| {stage} | ESCALATED | {ts} | late-escalation unresolved — human takeover |`
in pipeline-state.md.

#### Tombstone in old fix slot (option 2 migration only)

```bash
mkdir -p "espalier/changes/fix/${SLUG}"
cat > "espalier/changes/fix/${SLUG}/TOMBSTONE.md" << EOF
# Tombstone: fix/${SLUG} → feat/${NEW_SLUG}

This fix was escalated late (at Stage ${ESCALATED_STAGE}) and migrated to:
**espalier/changes/feat/${NEW_SLUG}/**

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

Auto-skeleton at `espalier/changes/feat/{slug}-root-cause/` inherits `caused_by`
and adds `filed_from_partial_fix: fix/{slug}`. Create the skeleton only after
the partial fix's push has gone through — an in-flight skeleton would become
the gate's most-recent active change and block the push. The skeleton's
pipeline-state.md gets `- Status: FILED` (a non-active status: the push gate
ignores it and neither lane resumes it; the full lane's FILED-skeleton scan or
an explicit `/espalier feat: …` adopts it). When that feat completes its own
Stage 7, it writes back to the partial fix's pipeline-state.md
`## Root Cause Addressed By` table (mechanism in `/espalier` Stage 7).

## Completion

When Stage 7 passes:
- Update own `pipeline-state.md` Status: COMPLETE (or PARTIAL_FIX if option 3).
- Commit the espalier bookkeeping (`git add espalier/changes/fix/{slug}
  && git commit -m 'chore(espalier): close {slug}'`) so the next change starts
  from a clean tree.
- Summarize: original cause, fix files, regression tests added.
- Report total rounds and any escalation gates tripped (even if user chose to override).
