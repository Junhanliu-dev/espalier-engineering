#!/bin/bash
# ESPALIER_BACKLINK_HOOK v1
# (Legacy marker HARNESS_BACKLINK_HOOK also recognized by /espalier-migrate for
#  v0.3 installs.)
#
# Installed by /espalier-init Phase 9 when user picks "install hook".
# Records squash-merge SHA mappings so /espalier-fix Stage 0 can reverse-look-up
# bugs back to the original change.
#
# Safe to delete to disable. Safe to re-install (idempotent).
# Runs after `git merge` / `git pull`. Detects squash commits (single parent +
# PR-style message), finds source Espalier change by file overlap, appends
# `squashed_to:` row to that change's pipeline-state.md.

MERGED_SHA=$(git rev-parse HEAD)
PARENT_COUNT=$(git log -1 --pretty=%P | wc -w | tr -d ' ')
MSG=$(git log -1 --pretty=%s)

# Squash heuristic: exactly one parent + PR-style message
[ "$PARENT_COUNT" = "1" ] || exit 0
echo "$MSG" | grep -qE '(Merge pull request #[0-9]+|\(#[0-9]+\)$)' || exit 0

# Files touched by the squash commit
FILES=$(git diff-tree --no-commit-id --name-only -r HEAD)
[ -z "$FILES" ] && exit 0

# Find best-match source change by file-name overlap, ignoring stale (>30d) candidates
BEST_STATE=""
BEST_COUNT=0
NOW=$(date +%s)
for state in espalier/changes/*/*/pipeline-state.md; do
  [ -f "$state" ] || continue

  # Skip _template
  case "$state" in *_template*) continue ;; esac

  # Age guard
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

# Threshold: best match must overlap >=50% of squash's files
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

  # Also update reverse-lookup cache if present
  if [ -f "espalier/.commit-index.tsv" ]; then
    SLUG=$(echo "$BEST_STATE" | sed 's|espalier/changes/||; s|/pipeline-state.md||')
    if ! grep -qE "^${MERGED_SHA}	[^	]+	squashed_to	" espalier/.commit-index.tsv; then
      printf '%s\t%s\t%s\t%s\n' "$MERGED_SHA" "$SLUG" "squashed_to" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> espalier/.commit-index.tsv
    fi
  fi
fi

exit 0
