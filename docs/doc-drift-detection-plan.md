# Espalier Doc-Drift Detection — Implementation Plan

Keeps Espalier-generated project artifacts (rules, wiki, layer specs, hooks) in
sync with the codebase as it evolves after `/espalier-init`.

**Status:** implementation-ready — **revision 5** (consolidated).
**Author:** session analysis 2026-05-20.
**Scope:** ships all seven components (A–I) in one release.
**Supersedes:** revisions 1–4. Four deep-review passes are folded in; their
findings are resolved in the code below, not re-litigated. Where a non-obvious
choice exists, the rationale is inline.

---

## 1. Problem

`/espalier-init` writes a complete set of project-level artifacts at install
time: rules, wiki, layer specs, sub-agents, hooks. After init they are **never
automatically refreshed**. As the codebase evolves — new layers, schema
changes, convention shifts, CI updates — the generated artifacts drift from
reality.

Worst case: rules sit in the **Always** context layer (auto-loaded every
session via `.claude/rules/*` symlinks). A stale rule is active misguidance on
every future agent run — the reviewer reads a stale `coding-standards.md`,
approves wrong-pattern code, drift compounds.

This plan adds detection, surfacing, remediation, and validation — without ever
auto-overwriting a doc, and without a post-merge hook dirtying the working
tree.

---

## 2. Audit of the current skill

### 2.1 Artifact lifecycle

| Artifact | Created | Auto-updated after init | Context layer |
|---|---|---|---|
| `rules/engineering-structure.md` | init Phase 2 | ✗ | Always |
| `rules/coding-standards.md` | init Phase 2 | ✗ | Always |
| `rules/development-process.md` | init Phase 2 | ✗ | Always |
| `wiki/architecture.md` | init Phase 2 (scout 1.2) | ✗ | On-demand |
| `wiki/data-models.md` | init Phase 2 (scout 1.8) | ✗ | On-demand |
| `wiki/critical-paths.md` | init Phase 2 (scout 1.9) | ✗ | On-demand |
| `wiki/external-services.md` | init Phase 2 (scout 1.10) | ✗ | On-demand |
| `skills/espalier-coding/specs/{layer}.md` | init Phase 2 | ✗ | Stage |
| `hooks/check-layer-boundaries.sh` | init Phase 2 (lang-specific) | ✗ | runtime |
| `hooks/pre-push-gate.sh` | init Phase 2 ({build/lint/test}) | ✗ | runtime |
| `agents/harness-coder.md` | init Phase 2 | ✗ | Delegated |
| `agents/harness-reviewer.md` | init Phase 2 | ✗ | Delegated |

Only per-change artifacts under `espalier/changes/` are touched after init.
`post-merge-backlink.sh` writes only the squash-SHA mapping. Phase 11 runs 24
validation checks — all verify presence/format, **none verify currency vs the
codebase**.

### 2.2 Severity by artifact class

| Class | Staleness impact |
|---|---|
| Rules (Always-layer) | **Critical** — loaded every session; stale = active misguidance |
| Layer-boundary hook | **Critical** — new layer → hook silently passes everything |
| Pre-push commands | **High** — runner swap → hook silently passes broken state |
| Layer specs | **High** — Stage 3 coder loads them; stale spec = wrong file template |
| Wiki | **Medium** — on-demand; agent sees real code first |
| Sub-agent definitions | **Low** — reference rules/specs which evolve below them |

---

## 3. Drift taxonomy

Two distinct staleness modes — they need different detectors.

| File type | Describes | Goes stale when |
|---|---|---|
| Rules, layer specs, layer-boundary hook | **HOW** — pattern, convention, boundary | The pattern itself changes |
| Wiki | **WHAT** — inventory, map | A new thing is added (even with an old pattern) |

A new feature using existing patterns leaves **rules** accurate but can leave
**wiki** stale (a new entity/route/service is now missing from the inventory).
Drift actually occurs on:

1. New folder/layer — `engineering-structure` + boundary hook
2. Schema/model/migration change — `data-models` wiki
3. New entry-point/route — `critical-paths` wiki
4. New external SDK/env var — `external-services` wiki
5. CI/build/branch-config change — `development-process` rules + pre-push-gate
6. **A convention evolving in review** ("we now return `Result<T>` instead of
   throwing") — `coding-standards`; invisible to file-diff detection

Cases 1 & 5 are rare; 2–4 happen on most feature work; **case 6 is the hardest
— a file diff cannot see it.** The architecture covers each: mechanical file
diffs (A), reviewer judgment (B), cross-PR aggregation (G), periodic re-scout
(C).

---

## 4. Architecture

Seven components plus a shared helper library. Defense-in-depth: auto where
mechanical, gated where risky, **never overwrites a doc without explicit user
accept**.

```
        DETECTION                          STATE                  ACTION
┌──────────────────────────┐   ┌────────────────────────┐
│ A  post-merge file diff   │──▶│ .drift-state.tsv        │
│    (drift-detect.sh)      │   │   (gitignored sidecar)  │
│ B  reviewer Convention    │──▶│ .drift.log  (audit)     │──▶ D  Stage 0
│    Drift blocks           │   │ .conventions.tsv (G,    │     pre-flight
│ G  reviewer Convention    │──▶│   tracked)              │       │
│    Observations           │   └────────────────────────┘       ▼
│ C  /espalier-doctor       │──────────────┘             E  /espalier-prune
│    periodic re-scout      │                            (only doc editor)
└──────────────────────────┘
   I  drift-helpers.sh — shared bash, sourced by all of the above
   F  validation checks 25–28      H  Stage 8.5 — notify-only
```

### 4.0 Core decision — gitignored sidecar, not file frontmatter

**All drift state lives in `espalier/.drift-state.tsv`** — a gitignored,
upsert TSV. Detectors never write YAML frontmatter into rule/wiki files.

Why: a post-merge hook that edits *tracked* files dirties the working tree on
every `git pull` and trips the pipeline's own Stage 7 "clean working tree"
gate. A gitignored sidecar does not. It also gives one writer, one reader, one
fixed schema — no field-name drift.

**Invariant — no automation writes a tracked file outside a deliberate,
committed step.** Honored throughout (see §5).

**Trade:** drift state is not git-shared. A fresh clone starts with an empty
sidecar; it re-converges as that clone runs the same `drift-detect.sh` on the
same merges (same model as the existing `.commit-index.tsv`). Pre-clone drift
is caught by `/espalier-doctor` (§4.C). Documented limit (§8.7), not a hole.

**Sidecar schema** — `espalier/.drift-state.tsv`, 4 tab-separated columns:

```
file                          stale_since_sha  stale_first_seen      stale_reason
espalier/wiki/data-models.md  a1b2c3d          2026-05-20T14:00:00Z  schema/model touched
```

- `file` — repo-relative path; unique key (one row per file).
- `stale_since_sha` — most recent SHA that flagged it; updated each re-flag.
- `stale_first_seen` — ISO-8601 UTC; **write-once**, set on first flag, never
  overwritten. Policy 3 (§4.F) ages against this.
- `stale_reason` — most recent human-readable reason; updated each re-flag.

`/espalier-prune` and `/espalier-doctor` **delete** a file's row when they
refresh (or confirm-current) it.

### 4.I — `drift-helpers.sh` (shared library)

One new file, `hook-templates/drift-helpers.sh` → installed at
`espalier/hooks/drift-helpers.sh`. **Sourced, never executed.** Every consumer
begins its bash with `. espalier/hooks/drift-helpers.sh`:
`drift-detect.sh`, `pre-push-gate.sh`, and the Stage-0/Stage-4/prune/doctor
bash snippets in the skills.

> The helpers are **pure bash** (bash-3.2 safe — macOS default — no
> associative arrays). Actions that need an LLM ("run a scout", "diff and
> prompt") are **not** shell functions; they appear in the skill markdown as
> orchestrator instructions. The bash is only mechanical glue.

```bash
#!/bin/bash
# espalier/hooks/drift-helpers.sh — sourced, never executed.
# Pure-bash drift-state helpers. bash-3.2 safe (no associative arrays).

# Absolute paths resolved once at source time — every helper then works
# regardless of the caller's cwd.
_DS_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
DRIFT_STATE="$_DS_ROOT/espalier/.drift-state.tsv"
DRIFT_LOG="$_DS_ROOT/espalier/.drift.log"
CONVENTIONS="$_DS_ROOT/espalier/.conventions.tsv"
DOCTOR_CADENCE="$_DS_ROOT/espalier/.doctor-cadence"     # tracked — choice only
DOCTOR_LASTRUN="$_DS_ROOT/espalier/.doctor-last-run"    # gitignored — stamp

_ds_now()      { date -u +%Y-%m-%dT%H:%M:%SZ; }
_ds_sanitize() { printf '%s' "$1" | tr -d '\t\n\r'; }   # make a value TSV-safe

# Parse an ISO-8601 UTC stamp to epoch seconds (BSD vs GNU date).
_ds_epoch() {
  if [ "$(uname)" = "Darwin" ]; then
    date -juf %Y-%m-%dT%H:%M:%SZ "$1" +%s 2>/dev/null
  else
    date -d "$1" +%s 2>/dev/null
  fi
}

# In-place sed, BSD vs GNU.
sed_inplace() {
  if [ "$(uname)" = "Darwin" ]; then sed -i '' "$@"; else sed -i "$@"; fi
}

# mark_stale FILE SHA REASON — upsert a sidecar row. stale_first_seen is
# WRITE-ONCE (kept if the row exists). The temp file is co-located with the
# sidecar so `mv` is a same-filesystem atomic rename, never a cross-FS copy.
mark_stale() {
  local file="$1" sha="$2" reason; reason=$(_ds_sanitize "$3")
  [ -f "$_DS_ROOT/$file" ] || return 0
  touch "$DRIFT_STATE"
  local first_seen
  first_seen=$(awk -F'\t' -v f="$file" '$1==f {print $3; exit}' "$DRIFT_STATE")
  [ -z "$first_seen" ] && first_seen=$(_ds_now)
  local tmp; tmp=$(mktemp "${DRIFT_STATE}.XXXXXX") || return 1
  awk -F'\t' -v f="$file" '$1!=f' "$DRIFT_STATE" > "$tmp" 2>/dev/null
  printf '%s\t%s\t%s\t%s\n' "$file" "$sha" "$first_seen" "$reason" >> "$tmp"
  mv "$tmp" "$DRIFT_STATE"
  printf '%s\t%s\t%s\t%s\n' "$(_ds_now)" "$sha" "$file" "$reason" >> "$DRIFT_LOG"
}

# clear_stale FILE — remove a file's row (prune/doctor on refresh-or-current).
clear_stale() {
  local file="$1"
  [ -f "$DRIFT_STATE" ] || return 0
  local tmp; tmp=$(mktemp "${DRIFT_STATE}.XXXXXX") || return 1
  awk -F'\t' -v f="$file" '$1!=f' "$DRIFT_STATE" > "$tmp"
  mv "$tmp" "$DRIFT_STATE"
  printf '%s\t%s\t%s\t%s\n' "$(_ds_now)" "-" "$file" "row cleared" >> "$DRIFT_LOG"
}

# stale_files — print every flagged file (empty if none).
stale_files() { [ -f "$DRIFT_STATE" ] && cut -f1 "$DRIFT_STATE"; return 0; }

# classify_tier FILE — echo fresh|aging|stale|critical|expired (empty if absent).
classify_tier() {
  local file="$1" fs ts now age
  [ -f "$DRIFT_STATE" ] || return 0
  fs=$(awk -F'\t' -v f="$file" '$1==f {print $3; exit}' "$DRIFT_STATE")
  [ -z "$fs" ] && return 0
  ts=$(_ds_epoch "$fs"); [ -z "$ts" ] && { echo fresh; return 0; }
  now=$(date -u +%s); age=$(( (now - ts) / 86400 ))
  if   [ "$age" -lt 14 ]; then echo fresh
  elif [ "$age" -lt 30 ]; then echo aging
  elif [ "$age" -lt 60 ]; then echo stale
  elif [ "$age" -lt 90 ]; then echo critical
  else echo expired; fi
}

# tier_counts — echo "fresh=N aging=N stale=N critical=N expired=N".
tier_counts() {
  local f t fresh=0 aging=0 stale=0 critical=0 expired=0
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    t=$(classify_tier "$f")
    case "$t" in
      fresh) fresh=$((fresh+1)) ;; aging) aging=$((aging+1)) ;;
      stale) stale=$((stale+1)) ;; critical) critical=$((critical+1)) ;;
      expired) expired=$((expired+1)) ;;
    esac
  done < <(stale_files)
  echo "fresh=$fresh aging=$aging stale=$stale critical=$critical expired=$expired"
}

# classify_file FILE — echo wiki|rule|layer_spec|hook|agent|other.
classify_file() {
  case "$1" in
    espalier/wiki/*)                          echo wiki ;;
    espalier/rules/*)                         echo rule ;;
    espalier/skills/espalier-coding/specs/*)  echo layer_spec ;;
    espalier/hooks/*)                         echo hook ;;
    espalier/agents/*|espalier/agent.md)      echo agent ;;
    *)                                        echo other ;;
  esac
}

# append_convention SLUG KEY LOCATION [COUPLED] — append a `diverges` row to
# .conventions.tsv. Sanitizes every field. De-dupes on (slug,key,location) so a
# Stage-4 review re-run does not inflate the promotion count.
append_convention() {
  local slug key loc coupled date
  slug=$(_ds_sanitize "$1"); key=$(_ds_sanitize "$2")
  loc=$(_ds_sanitize "$3"); coupled=$(_ds_sanitize "${4:-}")
  date=$(date -u +%Y-%m-%d)
  touch "$CONVENTIONS"
  awk -F'\t' -v s="$slug" -v k="$key" -v l="$loc" \
    '$2==s && $3==k && $4==l {f=1} END{exit !f}' "$CONVENTIONS" && return 0
  if [ -n "$coupled" ]; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$date" "$slug" "$key" "$loc" "diverges" "$coupled" >> "$CONVENTIONS"
  else
    printf '%s\t%s\t%s\t%s\t%s\n'     "$date" "$slug" "$key" "$loc" "diverges" >> "$CONVENTIONS"
  fi
}

# doctor_due — exit 0 if a doctor scan is due. Cadence from the tracked
# .doctor-cadence; last-run from the gitignored .doctor-last-run. Unknown/empty
# cadence → not due.
doctor_due() {
  [ -f "$DOCTOR_CADENCE" ] || return 1
  local cadence interval last last_sec now_sec
  cadence=$(grep '^cadence:' "$DOCTOR_CADENCE" | awk '{print $2}')
  case "$cadence" in
    manual)       return 1 ;;
    every-change) return 0 ;;
    weekly)       interval=604800 ;;
    monthly)      interval=2592000 ;;
    *)            return 1 ;;
  esac
  [ -f "$DOCTOR_LASTRUN" ] || return 0
  last=$(grep '^last_run:' "$DOCTOR_LASTRUN" | awk '{print $2}')
  [ -z "$last" ] && return 0
  last_sec=$(_ds_epoch "$last"); [ -z "$last_sec" ] && return 0
  now_sec=$(date -u +%s)
  [ $(( now_sec - last_sec )) -ge "$interval" ]
}

# doctor_stamp SHA — record a completed doctor run in the gitignored stamp file.
doctor_stamp() {
  printf 'last_run: %s\nlast_run_sha: %s\n' "$(_ds_now)" "$1" > "$DOCTOR_LASTRUN"
}

# detect_run_mode — attended | unattended | ambiguous.
detect_run_mode() {
  [ -n "${CI:-}" ]                  && { echo unattended; return; }
  [ -n "${ESPALIER_UNATTENDED:-}" ] && { echo unattended; return; }
  [ -n "${ESPALIER_LOOP:-}" ]       && { echo unattended; return; }
  [ ! -t 0 ]                        && { echo unattended; return; }
  [ -t 0 ] && [ -t 1 ]              && { echo attended;   return; }
  echo ambiguous
}
```

### 4.A — Post-merge file-diff detector (`drift-detect.sh`)

A standalone hook, installed **unconditionally** (independent of the
squash-merge decision), separate from `post-merge-backlink.sh` — that script is
squash-gated and only installed for one merge decision, whereas drift detection
must run on every merge.

New file `hook-templates/drift-detect.sh`:

```bash
#!/bin/bash
# ESPALIER_DRIFT_DETECT_HOOK v1
# Post-merge drift detector. Installed unconditionally. Runs on every
# merge/pull. Flags Espalier docs that may have drifted by writing
# espalier/.drift-state.tsv. NEVER edits a rule/wiki file. Idempotent.

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$ROOT" || exit 0
[ -f espalier/hooks/drift-helpers.sh ] || exit 0   # not an Espalier repo
. espalier/hooks/drift-helpers.sh

MERGED_SHA=$(git rev-parse HEAD)

# Pre-merge HEAD. git merge/pull set ORIG_HEAD; fall back to HEAD~1. A real
# diff base is required — `git diff-tree HEAD` is empty on a true merge commit.
PRE=$(git rev-parse --verify --quiet ORIG_HEAD) \
  || PRE=$(git rev-parse --verify --quiet HEAD~1)
[ -z "$PRE" ] && exit 0   # initial commit — nothing to diff

# -M enables rename detection (else renames show as delete+add).
TOUCHED=$(git diff --name-only           -M "$PRE" HEAD)
ADDED=$(git diff   --name-only --diff-filter=A -M "$PRE" HEAD)
DELETED=$(git diff --name-only --diff-filter=D -M "$PRE" HEAD)
RENAMED=$(git diff --name-status --diff-filter=R -M "$PRE" HEAD \
          | awk -F'\t' '$1 ~ /^R/ { print $2 "\t" $3 }')

# Every ancestor directory prefix of the added / deleted files.
ADDED_DIRS=$(printf '%s\n' "$ADDED" | awk -F/ '
  { p=""; for (i=1;i<NF;i++){ p=(p=="")?$i:p"/"$i; print p } }' | sort -u)
DELETED_DIRS=$(printf '%s\n' "$DELETED" | awk -F/ '
  { p=""; for (i=1;i<NF;i++){ p=(p=="")?$i:p"/"$i; print p } }' | sort -u)

is_layer_dir() {  # depth-1 or depth-2 dir under a known source root
  case "$1" in
    src|app|internal|pkg|cmd|lib|server|client|apps|packages|services|modules) return 0 ;;
    src/*|app/*|internal/*|pkg/*|cmd/*|lib/*|server/*|client/*|apps/*|packages/*|services/*|modules/*)
      [ "$(printf '%s' "$1" | awk -F/ '{print NF}')" -le 2 ] && return 0 ;;
  esac
  return 1
}

# dir_is_new DIR — true only if DIR had no tree entry at the pre-merge HEAD.
# Gates out "file added to an already-existing dir" (else the detector fires
# on every PR).
dir_is_new() { ! git cat-file -e "$PRE:$1" 2>/dev/null; }

# --- New layer / workspace (only genuinely new dirs). while-read, not
#     `for d in $...` — directory names may contain spaces. ---
printf '%s\n' "$ADDED_DIRS" | while IFS= read -r d; do
  [ -z "$d" ] && continue
  is_layer_dir "$d" || continue
  dir_is_new   "$d" || continue
  mark_stale espalier/rules/engineering-structure.md  "$MERGED_SHA" "new layer/dir: $d"
  mark_stale espalier/hooks/check-layer-boundaries.sh "$MERGED_SHA" "new layer/dir: $d"
  mark_stale espalier/wiki/architecture.md            "$MERGED_SHA" "new layer/dir: $d"
done

# --- Layer / workspace deletion (dir gone from the worktree now) ---
printf '%s\n' "$DELETED_DIRS" | while IFS= read -r d; do
  [ -z "$d" ] && continue
  is_layer_dir "$d" || continue
  [ -d "$d" ] && continue
  mark_stale espalier/rules/engineering-structure.md  "$MERGED_SHA" "layer removed: $d"
  mark_stale espalier/hooks/check-layer-boundaries.sh "$MERGED_SHA" "layer removed: $d"
  mark_stale espalier/wiki/architecture.md            "$MERGED_SHA" "layer removed: $d"
done

# --- Cross-layer move (rename crossing a top-level dir) ---
printf '%s\n' "$RENAMED" | while IFS=$'\t' read -r OLD NEW; do
  [ -z "$OLD" ] && continue
  OLD_TOP=$(printf '%s' "$OLD" | cut -d/ -f1-2)
  NEW_TOP=$(printf '%s' "$NEW" | cut -d/ -f1-2)
  [ "$OLD_TOP" != "$NEW_TOP" ] && {
    mark_stale espalier/wiki/architecture.md   "$MERGED_SHA" "cross-layer move: $OLD -> $NEW"
    mark_stale espalier/wiki/critical-paths.md "$MERGED_SHA" "cross-layer move: $OLD -> $NEW"
  }
done

ALL_PATHS=$(printf '%s\n%s\n' "$TOUCHED" "$DELETED")

# --- Inventory drift (wiki). Anchored regexes so `domain.ts` ≠ `main.`. ---
printf '%s\n' "$ALL_PATHS" | grep -qE '(^|/)(schema\.(prisma|sql|graphql)|.*\.entity\.[a-z]+)$|(^|/)migrations/|(^|/)models/' \
  && mark_stale espalier/wiki/data-models.md "$MERGED_SHA" "schema/model touched"

printf '%s\n' "$ALL_PATHS" | grep -qE '(^|/)(main|index|app)\.(ts|js|py|go)$|(^|/)(routes|handlers|controllers)/' \
  && mark_stale espalier/wiki/critical-paths.md "$MERGED_SHA" "entry/route touched"

# external-services keys off env files + dependency manifests, NOT src/services/
# (which is usually internal).
printf '%s\n' "$TOUCHED" | grep -qE '(^|/)\.env(\.example|\.sample)?$|(^|/)(package\.json|requirements\.txt|go\.mod|Cargo\.toml|Gemfile)$' \
  && mark_stale espalier/wiki/external-services.md "$MERGED_SHA" "deps/env touched"

# --- CI / process drift (rules) ---
printf '%s\n' "$TOUCHED" | grep -qE '(^|/)\.github/workflows/|(^|/)\.husky/|(^|/)(Makefile|justfile|Jenkinsfile)$' \
  && mark_stale espalier/rules/development-process.md "$MERGED_SHA" "ci/process config touched"

# --- Build / module-resolution config → engineering-structure ---
printf '%s\n' "$TOUCHED" | grep -qE '(^|/)(tsconfig\.json|nx\.json|pnpm-workspace\.yaml|lerna\.json|turbo\.json)$|(^|/)(vite|webpack|rollup)\.config\.' \
  && mark_stale espalier/rules/engineering-structure.md "$MERGED_SHA" "build/module config changed"

# --- Lint / format config → coding-standards (mechanical rules only) ---
printf '%s\n' "$TOUCHED" | grep -qE '(^|/)\.(eslintrc|prettierrc|golangci)|(^|/)(\.ruff\.toml|biome\.json|rustfmt\.toml|pyproject\.toml)$' \
  && mark_stale espalier/rules/coding-standards.md "$MERGED_SHA" "lint/format config changed"

# --- Pre-push command drift — package.json scripts section changed ---
git diff "$PRE" HEAD -- package.json 2>/dev/null \
  | grep -qE '^\+.*"(test|build|lint)"[[:space:]]*:' \
  && mark_stale espalier/hooks/pre-push-gate.sh "$MERGED_SHA" "test/build/lint script changed"

exit 0
```

**Design:** auto-flag (write a sidecar row), **never auto-rewrite a doc**.
Regexes are heuristic — they can over-flag (harmless: a surfaced-and-dismissed
row) or under-flag (the doctor backstops). A cheap first net, not a proof.

#### Hook installation — dispatcher

Git allows one `post-merge` hook file. Two Espalier scripts want it:
`drift-detect.sh` (every merge, unconditional) and `post-merge-backlink.sh`
(squash merges, only when `MERGE_DECISION=installed`). They share the slot via
a stable dispatcher; the real logic stays in `espalier/hooks/*.sh` (recopied
every bootstrap, so it never goes stale):

```bash
#!/bin/bash
# >>> ESPALIER_POSTMERGE_DISPATCH v1 >>>
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$ROOT" || exit 0
[ -f espalier/hooks/drift-detect.sh ] && bash espalier/hooks/drift-detect.sh
if [ "$(cat espalier/.merge-hook-decision 2>/dev/null)" = "installed" ]; then
  [ -f espalier/hooks/post-merge-backlink.sh ] && bash espalier/hooks/post-merge-backlink.sh
fi
# <<< ESPALIER_POSTMERGE_DISPATCH v1 <<<
exit 0
```

- The dispatcher never changes → never goes stale. (It also fixes a
  pre-existing bug: the current bootstrap *inlines a copy* of
  `post-merge-backlink.sh` into the hook file, so plugin updates never reach
  it. The dispatcher calls by path — updates propagate.)
- `drift-detect.sh` runs every merge; `post-merge-backlink.sh` is gated at
  runtime by `.merge-hook-decision` — flipping that file toggles backlink with
  no hook reinstall.
- POSIX-only body (`[ ]`, `cat`, `if`) so it is safe even if husky runs it
  under `sh`.

### 4.B — Reviewer-time pattern-drift capture

A file diff cannot see a convention shift; only the reviewer can. Add to
`templates/agents/harness-reviewer.md`:

```markdown
## Convention Drift Reporting

If during review you observe one OR MORE recurring code patterns that differ
from project rules and are now used in 2+ places, emit a Convention Drift
block for EACH distinct drift.

## Convention Drift
- Rule file: espalier/rules/coding-standards.md (or specs/{layer}.md)
- Old convention: "{quoted from the rule}"
- New convention observed: "{what the code does now}"
- Evidence files: {2+ files showing the new pattern}
- Recommendation: update rule | document exception | reject this code
- coupled_with: {optional — another rule file whose drift depends on this one}

Constraints:
- DO NOT silently approve code that violates a rule — emit the block first.
- DO NOT use Convention Drift for one-off exceptions. 2+ evidence files required.
- DO NOT bundle unrelated drifts. One drift = one block. A block with two
  `- Rule file:` lines is malformed and will be rejected.
- Checking 2+ occurrences is a bounded grep over the layer you are already
  reviewing — NOT a whole-codebase audit. If you cannot confirm 2+ from files
  in scope, emit a Convention Observation (§4.G) instead.
```

**Multi-block parser** — new file `hook-templates/parse-drift-blocks.py`:

```python
# Invoked by the orchestrator at Stage 4: python3 .../parse-drift-blocks.py REVIEW
import sys, re

review_md = open(sys.argv[1]).read()
blocks = re.split(r'^## Convention Drift\s*$', review_md, flags=re.M)[1:]

for raw in blocks:
    body = re.split(r'^## ', raw, flags=re.M)[0]          # stop at next heading
    fields = {}
    for k, v in re.findall(r'^- ([\w ]+?):\s*(.+)$', body, flags=re.M):
        fields[k.strip().lower().replace(' ', '_')] = v.strip()
    rule_files = re.findall(r'^- Rule file:\s*(.+)$', body, flags=re.M)
    if len(rule_files) != 1:
        print(f"MALFORMED\t{len(rule_files)} rule files in one block")
        continue
    print(f"DRIFT\t{rule_files[0].strip()}\t{fields.get('coupled_with', '')}")
```

**Stage 4 glue** — add to the Stage 4 section of **both**
`templates/skills/espalier.md` **and** `templates/skills/espalier-fix.md`
(both lanes spawn the reviewer; both can surface drift):

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

`coupled_with` blocks are surfaced together at the next Stage 0 pre-flight
(promote-together / reject-together / split — split warns but is allowed).
Recorded in the optional 6th column of `.conventions.tsv`.

### 4.G — Cross-file convention index

A convention emerges across many PRs — no single review can spot it. The
reviewer also emits **Observations** (lower bar than §4.B — no "2+ places"
needed). Add to `templates/agents/harness-reviewer.md`:

```markdown
## Convention Observations

Any time code diverges from a rule, emit an Observation. Do NOT assign a key —
emit only what you can see locally:

## Convention Observations
- description: "controllers return Result<T,E> instead of throwing"
  location: src/controllers/userController.ts:42
  rule_file: espalier/rules/coding-standards.md
```

**Key canonicalization — orchestrator, not reviewer.** Each reviewer is a
fresh isolated sub-agent; if it coined the aggregation key, three reviews of
one pattern would coin three slugs and the count would never reach the
threshold. So the **orchestrator** assigns it — it reads `.conventions.tsv`
and has the full key list. At Stage 4, for each Observation, the orchestrator:

1. Reads existing `pattern_key`s from `.conventions.tsv`.
2. LLM-maps `description` → an existing key, or mints a new kebab-case key.
3. Appends the row: `append_convention "$slug" "$key" "$location"` (§4.I —
   sanitizes every field, and de-dupes on (slug,key,location) so a Stage-4
   review re-run does not inflate the count).

This Stage-4 step lives in **both** `espalier.md` and `espalier-fix.md`.

`.conventions.tsv` — tracked, append-only. Columns:
`date · change_slug · pattern_key · location · status` + optional 6th
`coupled_with`. `status` ∈ `diverges | promoted | rejected | exception`.

**Promotion** — when one `pattern_key` has ≥ 3 `diverges` rows, the Stage 0
pre-flight (§4.D) surfaces it:

```
1. Promote   — orchestrator edits the rule file directly to bless the new
               pattern + deprecate the old, then flips those rows → promoted.
               (NOT /espalier-prune: prune re-runs a scout, which re-derives
               the rule from a code base that is now a MIX of old + new — it
               reports the mix, it cannot make the decision. Promotion is a
               deliberate edit.)
2. Reject    — flip those rows → rejected. The threshold counts only
               `diverges`, so a rejected pattern stops counting.
3. Exception — append under the rule's "## Exceptions"; flip rows → exception.
4. Wait      — leave rows `diverges`; re-prompt at next occurrence.
```

The status flip edits `.conventions.tsv` (tracked) and is committed by the
same Stage 0 → Stage 7 run that surfaced the prompt (§5). Retention: keep
forever (grows < ~100 rows/year); hand-trim old `promoted`/`rejected` rows if
it ever exceeds ~5k.

### 4.C — Periodic doctor (`/espalier-doctor`)

Catches what A+B miss: silent refactors that change no file structure;
pre-clone drift the sidecar never saw. New skill
`templates/skills/espalier-doctor.md` → `espalier/skills/espalier-doctor/SKILL.md`.

```
Trigger: /espalier-doctor [--quick | --full | --since <sha>]
  --quick (default): re-scout architecture / CI / data-models / critical-paths
                     / external-services (~3 min)
  --full:            all init-Phase-1 scouts (~8 min)
  --since <sha>:     only re-scout layers touched since <sha>

Per artifact: re-run the matching scout, two-way diff the scout output vs the
current file. If materially different:
  mark_stale "$artifact" "$(git rev-parse HEAD)" "doctor: scout drift"
On completion: doctor_stamp "$(git rev-parse HEAD)".
Output: espalier/.drift-report.md (gitignored, timestamped human summary).
```

**Scout-prompt provenance.** `/espalier-doctor` and `/espalier-prune` are
installed into the *target* project and cannot read the plugin's
`references/discovery-checklist.md`. The scout prompts they need are therefore
**embedded directly in the two skill templates** at authoring time — a copy,
not a reference.

**Cadence — local-file activity-gating, no CI cron.** Portable to any provider.
User picks at init via Phase 0 Q3:

```
Phase 0 Q3 — Doctor cadence
  1. Every change   → cadence = every-change
  2. Weekly         → cadence = weekly   (recommended default)
  3. Monthly        → cadence = monthly
  4. On-demand only → cadence = manual
```

Bootstrap writes `espalier/.doctor-cadence` — **tracked, cadence line only**,
written once, never auto-rewritten:

```
cadence: weekly
```

The last-run stamp lives in the separate **gitignored** `espalier/.doctor-last-run`
(written by `doctor_stamp`). `doctor_due()` reads cadence from the tracked
file, the stamp from the gitignored one — checked at events that already fire:
`/espalier` Stage 0, `/espalier-fix` Stage 0, `pre-push-gate.sh` (one-line
non-blocking echo). Doctor fires on the next activity after the interval
elapses; an idle repo never fires it (no commits = no drift).

### 4.D — Reader-side gate (consolidated Stage 0 pre-flight)

One batched pre-flight — never three separate prompts. Add the same block to
the Stage 0 section of **both** `templates/skills/espalier.md` and
`templates/skills/espalier-fix.md`, after each skill's "Before Starting":

```markdown
### Stage 0 Pre-Flight (drift + conventions + doctor)

  . espalier/hooks/drift-helpers.sh

Gather all three signals BEFORE prompting:
  1. STALE  — stale_files() lists flagged files; tier_counts() buckets them.
  2. CONV   — if espalier/.conventions.tsv exists, scan for any pattern_key
              with >= 3 `diverges` rows (promotion candidates).
  3. DOCTOR — doctor_due(). Skip if /espalier-doctor is not installed.

If all three are empty/false → no prompt, proceed to Stage 1.
Otherwise issue ONE AskUserQuestion summarising all three:

  "Pre-flight found:
     - {N} stale doc(s): {tier breakdown}
     - {M} convention(s) over the promotion threshold
     - doctor scan due ({cadence})
   Options:
     1. Handle now — run /espalier-prune + review conventions, then resume
     2. Proceed    — continue to Stage 1 with current docs
     3. Abort"

Default: "Handle now" if any stale doc is critical/expired, else "Proceed".
If only fresh (<14d) stale docs and no conv/doctor signal → treat as empty.
```

Coder/reviewer sub-agents also consult the sidecar (state is not in the files
themselves):

`harness-coder.md`, in "Before Writing ANY Code":

```markdown
- Stale-doc check: `cut -f1 espalier/.drift-state.tsv 2>/dev/null` lists every
  flagged file (repo-relative). If a rule/spec you rely on is listed, note it
  in coding-report.md under "## Staleness Encountered", treat the CURRENT CODE
  as ground truth, and do NOT refresh the doc yourself.
```

`harness-reviewer.md`, a pre-flight note (a summary note, **not** a verdict —
do not overload `ESCALATION_REQUIRED`):

```markdown
0. Pre-flight: if a rule/wiki file material to this review is listed in
   espalier/.drift-state.tsv, add to your review summary:
   "STALE CONTEXT: {file} flagged stale — findings checked against current
   code, not the stale doc." Do not change the PASS/FAIL verdict for staleness.
```

### 4.E — Refresh primitive (`/espalier-prune`)

New skill `templates/skills/espalier-prune.md` →
`espalier/skills/espalier-prune/SKILL.md`. **The only component that edits a
doc.** Interactive, per-file, always gated.

```
Trigger: /espalier-prune <path> | --all-stale

Per file (LLM-orchestrated — each step is a real tool action, not bash):
  1. Look up the scout(s) for the file (mapping below).
  2. Spawn the scout(s) — prompts embedded in this skill. For a file with two
     scouts (coding-standards ← 1.3 + 1.6), merge the two outputs into ONE
     proposed file before diffing.
  3. TWO-WAY diff: current file vs proposed scout output. (Not three-way — the
     init template is full of {placeholders} and useless as a diff base.)
  4. If the diff is empty / immaterial (a teammate already refreshed it):
     `clear_stale <file>`, report "already current", move on — no prompt.
     (Under the per-clone sidecar a teammate's fix leaves a phantom row on
     your clone; this retires it instead of nagging forever.)
  5. Else render the unified diff and gate by file class (AskUserQuestion):
       Wiki  — apply / review / skip                      (default: apply)
       Rules — apply / keep-old / show-full-diff / edit    (no default)
       Specs — apply / keep-old / edit                     (no default)
       Hooks — apply / keep-old / edit + dry-run validate  (no default)
  6. On apply: overwrite the file, then `clear_stale <file>`.
  7. On skip: leave the row (re-surfaces next pre-flight).

After all files: report applied / already-current / kept-old / skipped.
Suggest a commit: "docs: refresh stale espalier artifacts" — commit it BEFORE
resuming a pipeline so the refresh is not bundled into a feature commit.

If invoked unattended (detect_run_mode → unattended) with --all-stale: do not
prompt — write the proposed diffs to espalier/.drift-report.md and exit,
leaving the rows. Refresh is never silent.
```

**Scout mapping:**

```
rules/engineering-structure.md            ← scout 1.2
rules/coding-standards.md                 ← scout 1.3 + 1.6  (merge before diff)
rules/development-process.md              ← scout 1.5
wiki/architecture.md                      ← scout 1.2
wiki/data-models.md                       ← scout 1.8
wiki/critical-paths.md                    ← scout 1.9
wiki/external-services.md                 ← scout 1.10
skills/espalier-coding/specs/{layer}.md   ← per-layer scout (Phase 2 batch)
hooks/check-layer-boundaries.sh           ← scout 1.2 + regenerate case-block
hooks/pre-push-gate.sh                    ← scout 1.5 + re-substitute commands
```

### 4.F — Validation checks (#25–28)

Added to `references/validation.md` and `bootstrap-espalier.sh` Stage 11. The
stage's hardcoded total `24` becomes `28` in all three places it appears (the
"N checks" log line, the `[$n/NN]` per-check format, the pass/fail summary).
Checks 26–28 are ordinary parallel `run_check` calls. Check #25 is **not** —
the standard harness runs each check with `>/dev/null 2>&1`, which would
swallow the tier table that is #25's whole value; it is invoked directly:
`run_check_25 || failed=$((failed+1))`.

| # | Check | Exit |
|---|---|---|
| 25 | Stale-artifact tiers (Policy 3) — read `.drift-state.tsv`, classify each row, loud-WARN on `critical`, FAIL on `expired` | 0 unless `expired` > 0 |
| 26 | `.drift-state.tsv` structural — `awk -F'\t' 'NF!=4{exit 1}'` (date validity is already WARNed per-row by #25) | 0 unless malformed |
| 27 | `.conventions.tsv` structural — every row 5 or 6 tab fields | 0 unless malformed |
| 28 | `.doctor-cadence` valid — `cadence:` ∈ {every-change, weekly, monthly, manual} | 0 unless malformed |

**Policy 3 — tiered stale tolerance.** Hardcoded thresholds (v1):

| Tier | Age of `stale_first_seen` | Action |
|---|---|---|
| fresh | < 14 days | silent |
| aging | 14–30 days | INFO line |
| stale | 30–60 days | WARN; Stage 0 default → "Handle now" |
| critical | 60–90 days | loud WARN |
| expired | > 90 days | check #25 fails hard |

```bash
# bootstrap-espalier.sh — invoked directly, NOT via the run_check harness.
run_check_25() {
  [ -f espalier/.drift-state.tsv ] || { echo "[25/28] OK   stale-tiers: no drift"; return 0; }
  local NOW; NOW=$(date -u +%s)
  local fresh=0 aging=0 stale=0 critical=0 expired=0
  while IFS=$'\t' read -r FILE SHA FIRST_SEEN REASON; do
    [ -z "$FILE" ] && continue
    local TS_SEC
    if [ "$(uname)" = "Darwin" ]; then
      TS_SEC=$(date -juf %Y-%m-%dT%H:%M:%SZ "$FIRST_SEEN" +%s 2>/dev/null)
    else
      TS_SEC=$(date -d "$FIRST_SEEN" +%s 2>/dev/null)
    fi
    [ -z "$TS_SEC" ] && { echo "  WARN bad stale_first_seen: $FILE"; continue; }
    local AGE=$(( (NOW - TS_SEC) / 86400 ))
    if   [ "$AGE" -lt 14 ]; then fresh=$((fresh+1))
    elif [ "$AGE" -lt 30 ]; then aging=$((aging+1));       echo "  [aging]    ${AGE}d  $FILE"
    elif [ "$AGE" -lt 60 ]; then stale=$((stale+1));       echo "  [stale]    ${AGE}d  $FILE"
    elif [ "$AGE" -lt 90 ]; then critical=$((critical+1)); echo "  [critical] ${AGE}d  $FILE"
    else expired=$((expired+1));                           echo "  [expired]  ${AGE}d  $FILE"
    fi
  done < espalier/.drift-state.tsv
  echo "[25/28] stale-tiers: fresh=$fresh aging=$aging stale=$stale critical=$critical expired=$expired"
  [ "$critical" -gt 0 ] && echo "  WARN: $critical artifact(s) 60-90d stale"
  if [ "$expired" -gt 0 ] && [ "${IGNORE_DRIFT:-no}" != "yes" ]; then
    echo "  FAIL: $expired expired (>90d) — run /espalier-prune --all-stale"
    return 1
  fi
  return 0
}
```

**Override** — `bash bootstrap-espalier.sh --validate-only --ignore-drift` sets
`IGNORE_DRIFT=yes`, skips #25's hard fail, and appends an audit row to the
gitignored `espalier/.drift-overrides.log` (`<ts>  <user.email>  expired=N
reason=...`; reason prompted unless `--ignore-drift-reason="..."`).

### 4.H — Stage 8.5 (notify-only)

Inserts between Stage 8 (CI verify) and Stage 9 (deploy). A pure
read-and-notify step — it edits no doc, prompts nothing, blocks nothing.

```markdown
### Stage 8.5 — Doc Drift Check (notify-only)
- . espalier/hooks/drift-helpers.sh
- STALE=$(stale_files). If empty → record "no drift", advance to Stage 9.
- Else append a table to espalier/changes/{type}/{slug}/doc-patches.md:

  ## Stage 8.5 Doc Drift (notify-only)
  | File | Tier | Reason |
  |------|------|--------|
  | wiki/data-models.md       | fresh | schema/model touched |
  | rules/coding-standards.md | stale | lint/format config changed |

- Surface ONE line: "Stage 8.5: {N} stale doc(s) — run /espalier-prune to
  refresh. (Not blocking; pipeline continues.)"
- Advance to Stage 9.
```

`doc-patches.md` is a per-change artifact created on demand under
`espalier/changes/{slug}/` — like `ci-result.md` (also written post-Stage-7).
Stage 8.5 touches no rule/wiki/spec file, so it cannot dirty a project-level
doc. In-pipeline auto-apply is a v2 item (it must first solve the commit story
— its own commit, or run pre-Stage-7).

Stage 8.5 is a label, not a numeric stage value: `pipeline-state.md`
`Current Stage:` never holds `8.5` (the orchestrator runs it as a sub-step of
8 → 9 and records it in the Stage History notes), so `pre-push-gate.sh`'s
integer stage parse stays correct.

---

## 5. State files

**Invariant: no automation writes a tracked file outside a deliberate,
committed step.**

| File | Tracked? | Written by | Commit story |
|---|---|---|---|
| `espalier/.drift-state.tsv` | ✗ gitignored | A, B-glue, C via `mark_stale`; cleared by `/espalier-prune` | — |
| `espalier/.drift.log` | ✗ gitignored | `mark_stale` / `clear_stale` | — |
| `espalier/.drift-report.md` | ✗ gitignored | `/espalier-doctor`, unattended `/espalier-prune` | — |
| `espalier/.doctor-last-run` | ✗ gitignored | `doctor_stamp` | — |
| `espalier/.drift-overrides.log` | ✗ gitignored | `--ignore-drift` | — |
| `espalier/.conventions.tsv` | ✓ tracked | Stage 4 (G) via `append_convention` | Committed by the pipeline's own Stage 7 commit — the orchestrator stages it with `espalier/changes/{slug}/*`. |
| `espalier/.doctor-cadence` | ✓ tracked | bootstrap, **once** at init | Committed when the user commits the `espalier/` scaffold; never auto-rewritten. |

Bootstrap Stage 10 appends to `.gitignore`: `espalier/.drift-state.tsv*`
(glob — also covers `mktemp` temp files), `espalier/.drift.log`,
`espalier/.drift-report.md`, `espalier/.doctor-last-run`,
`espalier/.drift-overrides.log` — alongside the existing
`espalier/.commit-index.tsv` entry.

The two tracked files are written only by deliberate, committed steps above —
never by a hook — so no `git pull` and no pipeline stage is left with a dirty
tree.

---

## 6. Pipeline integration

| Event | Action |
|---|---|
| `/espalier` & `/espalier-fix` Stage 0 | D — one consolidated pre-flight (stale + conventions + doctor-due) |
| `/espalier` & `/espalier-fix` Stage 3 (coder) | D — coder consults the sidecar, notes staleness in coding-report.md |
| `/espalier` & `/espalier-fix` Stage 4 (reviewer) | B — Convention Drift blocks; G — Convention Observations |
| `/espalier` & `/espalier-fix` Stage 4 done | orchestrator parses blocks → `mark_stale`; canonicalizes keys → `append_convention` |
| `/espalier` Stage 7 | orchestrator stages `.conventions.tsv` into the change's commit |
| `/espalier` Stage 8.5 | H — notify-only: read sidecar, write doc-patches.md, surface one line |
| post-merge (every merge/pull) | A — `drift-detect.sh` writes `.drift-state.tsv` |
| post-merge (squash, if installed) | unchanged — `post-merge-backlink.sh` SHA mapping (via the dispatcher) |
| `git push` | `pre-push-gate.sh` — one-line `doctor_due` reminder (non-blocking) |
| `bootstrap --validate-only` | F — checks #25–28 |

Refresh is never automatic — only `/espalier-prune` (E) or `/espalier-doctor`
(C) edit a doc, both interactive/gated.

---

## 7. Implementation plan

Ships as one release. Build in dependency order; everything lands together.

### 7.1 File manifest

**New files (5):**

| File | Purpose |
|---|---|
| `hook-templates/drift-helpers.sh` | §4.I shared bash library |
| `hook-templates/drift-detect.sh` | §4.A post-merge detector |
| `hook-templates/parse-drift-blocks.py` | §4.B Convention Drift parser |
| `templates/skills/espalier-prune.md` | §4.E refresh skill (embed scout prompts) |
| `templates/skills/espalier-doctor.md` | §4.C periodic skill (embed scout prompts) |

**Modified files (10):**

| File | Change |
|---|---|
| `scripts/bootstrap-espalier.sh` | Stage 2 `mkdir` espalier-prune + espalier-doctor; Stage 3 `cp` both skill templates; Stage 4 copy list += `drift-detect.sh`, `drift-helpers.sh`, `parse-drift-blocks.py`; Stage 5 symlink loop += both new skills; Stage 9 → install **dispatcher** (unconditional; strip any legacy inlined backlink block); Stage 10 gitignore the 5 sidecar paths; Stage 11 total 24→28, add `run_check_25` (direct) + checks 26/27/28 (`run_check`); write `espalier/.doctor-cadence` from Phase 0 Q3 |
| `references/validation.md` | document checks 25–28 |
| `templates/skills/espalier.md` | Stage 0 pre-flight; Stage 4 drift-glue + convention canonicalization; Stage 7 stages `.conventions.tsv`; Stage 8.5 notify block |
| `templates/skills/espalier-fix.md` | Stage 0 pre-flight; Stage 4 drift-glue + convention canonicalization |
| `templates/agents/harness-coder.md` | stale-doc check in "Before Writing ANY Code" |
| `templates/agents/harness-reviewer.md` | Convention Drift Reporting; Convention Observations; STALE CONTEXT pre-flight note |
| `templates/pipeline.md` | insert Stage 8.5 between 8 and 9 |
| `templates/skills/espalier-coding/...` specs | none — listed for completeness; specs are read by prune, not edited here |
| `skills/espalier-init/SKILL.md` | Phase 0 Q3 (doctor cadence); Output Structure diagram += 2 skills; skill-name-parity invariant += 2 skills |
| `hook-templates/pre-push-gate.sh` | append a guarded `doctor_due` one-line reminder (sources drift-helpers.sh if present) |

### 7.2 Build order

1. **I** — `drift-helpers.sh`. Foundation; everything sources it.
2. **A** — `drift-detect.sh`.
3. **F + bootstrap wiring** — Stage 2/3/4/5/9/10/11 edits, `run_check_25`,
   checks 26–28, `validation.md`, the dispatcher, gitignore. Installs A + I.
4. **D** — Stage 0 pre-flight (espalier.md + espalier-fix.md), coder/reviewer
   stale checks.
5. **B** — reviewer Convention Drift protocol, `parse-drift-blocks.py`, Stage 4
   glue (both skills).
6. **G** — reviewer Observations, orchestrator key canonicalization +
   `append_convention` (both skills), Stage 7 staging of `.conventions.tsv`.
7. **E** — `espalier-prune.md` (embed scout prompts) + bootstrap skill wiring.
8. **C** — `espalier-doctor.md` (embed scout prompts) + Phase 0 Q3 +
   `.doctor-cadence` write + `pre-push-gate.sh` reminder + bootstrap skill wiring.
9. **H** — Stage 8.5 in `pipeline.md` + `espalier.md`.

Estimate ~1600–1800 LOC across 15 files.

### 7.3 Verification (post-implementation)

- **A** — in a scratch repo with Espalier installed: `mkdir src/newlayer &&
  touch src/newlayer/x.ts`, commit, `git merge` a branch → assert
  `engineering-structure.md` appears in `.drift-state.tsv`; add a file to an
  *existing* `src/` dir → assert it does **not** re-flag (R12 gate).
- **A merge-commit** — create a true merge commit (`--no-ff`) → assert the
  detector still sees the diff (`ORIG_HEAD` base).
- **dispatcher** — `git merge` on a non-`installed` repo → drift-detect runs,
  backlink does not.
- **F** — hand-write a `.drift-state.tsv` row dated 100d ago → `bootstrap
  --validate-only` exits non-zero; `--ignore-drift` makes it pass + logs.
- **B** — feed a `review-record.md` with two `## Convention Drift` blocks →
  `parse-drift-blocks.py` emits two `DRIFT` lines; a block with two
  `- Rule file:` lines → one `MALFORMED`.
- **E** — flag a wiki file, `/espalier-prune <file>`, accept → file rewritten,
  row gone; run again → "already current", row stays gone.
- **bash-3.2** — run `drift-helpers.sh` functions under `/bin/bash` on macOS.

### 7.4 Deferred to v2

| Item | v1 stopgap |
|---|---|
| `espalier/.drift-policy` config (tunable thresholds) | thresholds hardcoded |
| Stage 8.5 in-pipeline auto-apply | notify-only; refresh via `/espalier-prune` |
| `pattern_key` fuzzy clustering | orchestrator assigns against the existing key list |
| `flock` on the sidecar upsert | atomic `mktemp`+`mv`; a lost update re-flags next merge |
| `post-rewrite` hook (rebase-pull detection) | `post-merge` only; doctor backstops |
| Git-shared drift state | per-clone sidecar; doctor backstops pre-clone drift |
| Cross-project rule propagation | per-project only |

---

## 8. Known limits

1. **Refactor PRs that consolidate an existing pattern** — no new occurrence;
   the reviewer emits nothing. Doctor (C) catches it via re-scout.
2. **Framework upgrades that change idioms** (React 17→18, etc.) — if no
   engineer flags it, no index entry. Doctor (C) catches it.
3. **A convention falling out of use** — `.conventions.tsv` tracks `diverges`
   events, never "old pattern gone." Doctor (C) only.
4. **Cross-project propagation** — drift in one project does not reach another
   sharing a rule canon. Out of scope.
5. **Semantic pre-push drift** — §4.A catches a `package.json` script *name*
   change, not a runner swap behind the same name. Doctor (C) catches it.
6. **In-layer renames** — renames within one top-level layer do not flag wiki
   (below wiki granularity). Deliberate.
7. **Drift state not git-shared** — a fresh clone starts with an empty sidecar;
   pre-clone drift is invisible until `/espalier-doctor` runs. Accepted trade
   for a clean working tree (§4.0).
8. **Detector regexes are heuristic** — they over-flag (harmless) or under-flag
   (doctor backstops). A cheap first net, not a proof.
9. **Convergence needs the hook installed per-clone** — `.husky/` is tracked
   (hook clones with the repo); `.git/hooks/` is not. A plain-git teammate who
   never runs bootstrap has no `drift-detect.sh` firing. Doctor backstops.
10. **Rebase-pulls** — `drift-detect.sh` is a `post-merge` hook, which does not
    fire after a rebase. A `pull.rebase=true` repo misses drift detection on
    pull (still gets it on local `git merge`). `post-rewrite` → v2.

---

## 9. Resolved design decisions

Folded in from four review passes; recorded so they are not re-opened.

- **Drift state is a gitignored sidecar, not file frontmatter** — a
  hook-written tracked file dirties the tree and trips the Stage 7 gate.
- **`drift-detect.sh` is its own hook, installed unconditionally** —
  `post-merge-backlink.sh` is squash-gated and conditionally installed.
- **One dispatcher owns the `post-merge` slot** — both scripts called by path;
  also fixes the pre-existing inline-copy staleness bug.
- **Stage 8.5 is notify-only in v1** — auto-apply after Stage 7's push has an
  unsolved commit story.
- **The orchestrator (not the reviewer) assigns `pattern_key`** — isolated
  reviewers cannot share a vocabulary; exact-match aggregation would never fire.
- **Promotion is a targeted rule edit, not a scout refresh** — a scout
  re-derives from mixed code; it cannot make the decision.
- **Doctor cadence is local-file activity-gated, not CI cron** — portable.
- **Only `.conventions.tsv` and `.doctor-cadence` are tracked** — each with an
  explicit commit story (§5); everything else is gitignored.
- **Promotion threshold fixed at 3**, tier thresholds hardcoded 14/30/60/90 —
  configurability is a v2 `.drift-policy`.
- **Concurrency: accept lost-update for v1** — `mktemp`+`mv` co-located is
  atomic (no corruption); a lost update re-flags next merge. `flock` → v2.

---

## 10. Implementation checklist

- [ ] I — `hook-templates/drift-helpers.sh`
- [ ] A — `hook-templates/drift-detect.sh`
- [ ] F — `bootstrap-espalier.sh` (Stages 2/3/4/5/9/10/11) + `references/validation.md`
- [ ] D — Stage 0 pre-flight in `espalier.md` + `espalier-fix.md`; `harness-coder.md` + `harness-reviewer.md` stale checks
- [ ] B — `harness-reviewer.md` Convention Drift; `parse-drift-blocks.py`; Stage 4 glue in `espalier.md` + `espalier-fix.md`
- [ ] G — `harness-reviewer.md` Observations; Stage 4 canonicalization + `append_convention`; Stage 7 stages `.conventions.tsv`
- [ ] E — `templates/skills/espalier-prune.md` + bootstrap skill wiring
- [ ] C — `templates/skills/espalier-doctor.md`; Phase 0 Q3; `.doctor-cadence`; `pre-push-gate.sh` reminder; bootstrap skill wiring
- [ ] H — Stage 8.5 in `pipeline.md` + `espalier.md`
- [ ] `skills/espalier-init/SKILL.md` — Phase 0 Q3, Output Structure, skill-name-parity
- [ ] Verification §7.3 — all checks pass
