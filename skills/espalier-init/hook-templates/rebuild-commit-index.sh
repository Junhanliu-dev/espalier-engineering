#!/bin/bash
# Reconstruct espalier/.commit-index.tsv from pipeline-state.md files.
#
# Safe to run anytime — overwrites in place. Idempotent.
# Source of truth lives in pipeline-state.md Commits + Squash Merges tables;
# this script just denormalizes those into a fast-lookup TSV.
#
# Triggered by:
#   /espalier-fix --build-index      (continue normally after)
#   /espalier-fix --rebuild-index    (delete cache first, then rebuild)
#   Auto-build on first cold scan > ESPALIER_CACHE_THRESHOLD_MS (default 1000ms)

# NOTE: no `set -e` — awk failures on a single malformed pipeline-state.md
# should not crash the whole rebuild. Errors are best-effort logged.
INDEX="espalier/.commit-index.tsv"
TMP="${INDEX}.tmp.$$"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

if [ ! -d "espalier/changes" ]; then
  echo "ERROR: espalier/changes/ not found. Run from project root." >&2
  exit 1
fi

# Clean tmp on exit
trap 'rm -f "$TMP"' EXIT

# Walk every pipeline-state.md at depth 3 (espalier/changes/{type}/{slug}/)
find espalier/changes -mindepth 3 -maxdepth 3 -name pipeline-state.md 2>/dev/null | while read -r f; do
  SLUG=$(echo "$f" | sed 's|espalier/changes/||; s|/pipeline-state.md||')

  # Extract from Commits table (Stage 7 push records).
  # Markdown row format: | stage | sha | files |
  awk -v slug="$SLUG" -v now="$NOW" '
    /^## Commits/ {in_commits=1; in_squash=0; next}
    /^## Squash Merges/ {in_squash=1; in_commits=0; next}
    /^## [^CS]/ {in_commits=0; in_squash=0}

    in_commits && /^\| *[0-9]+ *\|/ {
      n = split($0, cols, "|")
      sha = cols[3]
      gsub(/^[ \t]+|[ \t]+$/, "", sha)
      if (length(sha) >= 7) print sha "\t" slug "\toriginal\t" now
    }

    in_squash && /squashed_to:/ {
      where = match($0, /[a-f0-9]{7,40}/)
      if (where) {
        sha = substr($0, RSTART, RLENGTH)
        print sha "\t" slug "\tsquashed_to\t" now
      }
    }
  ' "$f"
done | sort -u > "$TMP"

mv "$TMP" "$INDEX"
COUNT=$(wc -l < "$INDEX" | tr -d ' ')
echo "Rebuilt $INDEX: $COUNT entries"
