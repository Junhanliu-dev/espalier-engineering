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

# Find the best-match source change via the SHARED hardened matcher in
# lookup-helpers.sh (whole-path anchored so a.ts never substring-matches
# a.tsx, space-safe, every ERE metachar escaped) — one heuristic, one
# implementation, instead of a second hand-rolled loop that drifts.
# 30 = the candidate age window in days (unchanged behavior).
HELPERS="espalier/hooks/lookup-helpers.sh"
[ -f "$HELPERS" ] || exit 0
. "$HELPERS"

_fuzzy_scan "$MERGED_SHA" 30
[ -n "$FUZZY_SLUG" ] || exit 0

BEST_STATE="$FUZZY_BEST_STATE"
BEST_COUNT="$FUZZY_BEST_COUNT"
TOTAL_FILES="$FUZZY_TOTAL"

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
