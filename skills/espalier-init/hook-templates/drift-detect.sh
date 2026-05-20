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

# --- Inventory drift (wiki). Anchored regexes so `domain.ts` != `main.`. ---
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

# --- Build / module-resolution config -> engineering-structure ---
printf '%s\n' "$TOUCHED" | grep -qE '(^|/)(tsconfig\.json|nx\.json|pnpm-workspace\.yaml|lerna\.json|turbo\.json)$|(^|/)(vite|webpack|rollup)\.config\.' \
  && mark_stale espalier/rules/engineering-structure.md "$MERGED_SHA" "build/module config changed"

# --- Lint / format config -> coding-standards (mechanical rules only) ---
printf '%s\n' "$TOUCHED" | grep -qE '(^|/)\.(eslintrc|prettierrc|golangci)|(^|/)(\.ruff\.toml|biome\.json|rustfmt\.toml|pyproject\.toml)$' \
  && mark_stale espalier/rules/coding-standards.md "$MERGED_SHA" "lint/format config changed"

# --- Pre-push command drift — package.json scripts section changed ---
git diff "$PRE" HEAD -- package.json 2>/dev/null \
  | grep -qE '^\+.*"(test|build|lint)"[[:space:]]*:' \
  && mark_stale espalier/hooks/pre-push-gate.sh "$MERGED_SHA" "test/build/lint script changed"

exit 0
