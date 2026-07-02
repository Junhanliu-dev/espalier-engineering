#!/bin/bash
# Reverse-lookup helpers for /espalier-fix Stage 0.
# Sourced (not executed) by the skill. All functions are pure shell so they
# can run in any POSIX-compatible environment.
#
# Provides:
#   _push_entry slug sha role lookup   — accumulate per-frame caused_by entries
#   _push_note_entry "<text>"          — append a `- note: ...` overflow row
#   _dedupe_entries_preserve_primary   — drop dup slugs; primary wins over call_path
#   _fuzzy_file_overlap_match <sha>    — fuzzy slug lookup by file-overlap heuristic
#   _cache_append sha slug kind        — idempotent write to espalier/.commit-index.tsv
#   _maybe_warn_slow_scan <start_ns>   — warn (and maybe auto-build cache) if scan exceeded threshold
#   _prompt_user_for_merge_decision    — fix-time fallback prompt (decision = ask-later)

# Per-fix accumulators. Caller must reset these before Stage 0.
ENTRIES_SLUG=()
ENTRIES_SHA=()
ENTRIES_ROLE=()
ENTRIES_LOOKUP=()
ENTRIES_NOTES=()

_push_entry() {
  ENTRIES_SLUG+=("$1")
  ENTRIES_SHA+=("$2")
  ENTRIES_ROLE+=("$3")
  ENTRIES_LOOKUP+=("$4")
}

_push_note_entry() {
  ENTRIES_NOTES+=("$1")
}

# Dedupe by slug, preserving "primary" over "call_path" when both exist.
# Same-slug-same-role duplicates resolved by keeping the earlier occurrence.
# Operates in place on the ENTRIES_* arrays.
#
# O(N²) worst case (nested loop with early-break) — fine at the Stage 0 fan-out
# cap of 5. C-style for loops + cached array accesses keep per-call overhead under 1ms.
_dedupe_entries_preserve_primary() {
  local -a OUT_SLUG=() OUT_SHA=() OUT_ROLE=() OUT_LOOKUP=()
  local i j keep n=${#ENTRIES_SLUG[@]}
  local i_slug i_role j_slug j_role

  for ((i = 0; i < n; i++)); do
    i_slug="${ENTRIES_SLUG[$i]}"
    i_role="${ENTRIES_ROLE[$i]}"
    keep="yes"
    for ((j = 0; j < n; j++)); do
      [ "$i" = "$j" ] && continue
      j_slug="${ENTRIES_SLUG[$j]}"
      [ "$i_slug" != "$j_slug" ] && continue
      j_role="${ENTRIES_ROLE[$j]}"

      # Drop this entry if:
      #   (a) we are call_path and there's a primary for the same slug, OR
      #   (b) same role and we are the later occurrence (i > j).
      if { [ "$i_role" = "call_path" ] && [ "$j_role" = "primary" ]; } \
         || { [ "$i_role" = "$j_role" ] && [ "$i" -gt "$j" ]; }; then
        keep="no"; break
      fi
    done
    if [ "$keep" = "yes" ]; then
      OUT_SLUG+=("$i_slug")
      OUT_SHA+=("${ENTRIES_SHA[$i]}")
      OUT_ROLE+=("$i_role")
      OUT_LOOKUP+=("${ENTRIES_LOOKUP[$i]}")
    fi
  done

  ENTRIES_SLUG=("${OUT_SLUG[@]}")
  ENTRIES_SHA=("${OUT_SHA[@]}")
  ENTRIES_ROLE=("${OUT_ROLE[@]}")
  ENTRIES_LOOKUP=("${OUT_LOOKUP[@]}")
}

# Fuzzy: given a (squash) SHA, find the Espalier change whose Commits table
# has the largest overlap of file paths with this SHA's tree. Threshold 50%.
# Stdout: slug ("feat/foo") or empty string. Used by Layer 3 fallback when no
# squash hook recorded the mapping.
_fuzzy_file_overlap_match() {
  local SHA="$1"
  local FILES BEST_STATE="" BEST_COUNT=0 TOTAL THRESHOLD COUNT f state SLUG

  FILES=$(git diff-tree --no-commit-id --name-only -r "$SHA" 2>/dev/null)
  [ -z "$FILES" ] && return 0

  for state in espalier/changes/*/*/pipeline-state.md; do
    [ -f "$state" ] || continue
    case "$state" in *_template*) continue ;; esac

    COUNT=0
    # while-read (not `for f in $FILES`) so paths with spaces stay whole.
    # Match a whole-path token in a Commits-table cell, not a bare substring —
    # else `a.ts` spuriously matches `a.tsx` / `dir/a.ts.map` and inflates overlap.
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      grep -qE "(^|[^[:alnum:]_./-])$(printf '%s' "$f" | sed 's/[.[\*^$/]/\\&/g')([^[:alnum:]_./-]|$)" "$state" 2>/dev/null \
        && COUNT=$((COUNT + 1))
    done <<EOF
$FILES
EOF
    if [ "$COUNT" -gt "$BEST_COUNT" ]; then
      BEST_COUNT=$COUNT
      BEST_STATE=$state
    fi
  done

  TOTAL=$(echo "$FILES" | wc -l | tr -d ' ')
  THRESHOLD=$(( (TOTAL + 1) / 2 ))
  if [ "$BEST_COUNT" -ge "$THRESHOLD" ] && [ -n "$BEST_STATE" ]; then
    SLUG=$(echo "$BEST_STATE" | sed 's|espalier/changes/||; s|/pipeline-state.md||')
    echo "$SLUG"
  fi
}

# Append one row to reverse-lookup cache, idempotent (skip if SHA+kind already present).
_cache_append() {
  local SHA="$1" SLUG="$2" KIND="$3"
  local CACHE="espalier/.commit-index.tsv"

  [ -z "$SHA" ] || [ -z "$SLUG" ] && return 0
  [ ! -f "$CACHE" ] && touch "$CACHE"

  grep -qE "^${SHA}	[^	]+	${KIND}	" "$CACHE" 2>/dev/null && return 0
  printf '%s\t%s\t%s\t%s\n' "$SHA" "$SLUG" "$KIND" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$CACHE"
}

# Warn if scan exceeded threshold; auto-build cache on first cold trigger.
# Argument: scan start time. Format depends on platform — caller used:
#   START=$(date +%s%N 2>/dev/null || date +%s)
# We tolerate both ns (Linux) and second (BSD) resolutions.
_maybe_warn_slow_scan() {
  local START="$1"
  local END THRESHOLD_MS DURATION_MS CHANGE_COUNT

  # ESPALIER_CACHE_THRESHOLD_MS preferred; HARNESS_CACHE_THRESHOLD_MS honored for legacy callers.
  THRESHOLD_MS="${ESPALIER_CACHE_THRESHOLD_MS:-${HARNESS_CACHE_THRESHOLD_MS:-1000}}"
  [ "$THRESHOLD_MS" = "0" ] && return 0

  END=$(date +%s%N 2>/dev/null || date +%s)

  # Strip any literal "%N" (BSD date doesn't support %N — returns "1715000000%N").
  # After strip, values are either:
  #   ns precision  → 19 digits (Linux GNU date)
  #   s precision   → 10 digits (BSD/macOS or fallback `date +%s`)
  START=$(echo "$START" | sed 's/[^0-9]//g')
  END=$(echo   "$END"   | sed 's/[^0-9]//g')

  if [ "${#START}" -ge 16 ]; then
    # nanosecond precision — divide by 1e6 to get ms
    DURATION_MS=$(( (END - START) / 1000000 ))
  else
    # second precision — multiply by 1000 to get ms
    DURATION_MS=$(( (END - START) * 1000 ))
  fi

  [ "$DURATION_MS" -lt "$THRESHOLD_MS" ] && return 0

  CHANGE_COUNT=$(find espalier/changes -mindepth 3 -maxdepth 3 -name pipeline-state.md 2>/dev/null | wc -l | tr -d ' ')
  echo "WARNING: reverse-lookup scan took ${DURATION_MS}ms across ${CHANGE_COUNT} changes." >&2

  if [ ! -f "espalier/.commit-index.tsv" ]; then
    echo "Building reverse-lookup cache automatically (one-time)..." >&2
    if [ -x "espalier/hooks/rebuild-commit-index.sh" ]; then
      bash espalier/hooks/rebuild-commit-index.sh
      echo "Cache built. Future lookups will be O(1)." >&2
    else
      echo "Cache builder not found at espalier/hooks/rebuild-commit-index.sh — skipping auto-build." >&2
    fi
  else
    echo "Cache exists but scan still triggered (likely missed entries). Consider:" >&2
    echo "  /espalier-fix --rebuild-index   # full rebuild from pipeline-state.md files" >&2
  fi
}

# Fix-time prompt (only fires when DECISION=ask-later). Writes user's choice
# to espalier/.merge-hook-decision, then caller re-reads + re-loops the SHA.
# This is the rescue path for when init-time decision was deferred. After this
# fires once, all future invocations are silent.
_prompt_user_for_merge_decision() {
  cat >&2 << 'EOF'

Heads up — first fix in this repo. Need to decide one thing.

This repo's merge strategy affects bug-to-commit traceability.

Options (write your choice to espalier/.merge-hook-decision):

  not-needed    — Repo uses rebase or merge-commit; SHAs preserved on main
  installed     — Install post-merge git hook to record squash mappings (recommended for squash repos)
  fuzzy-allowed — No hook; allow fuzzy file-overlap match at fix-time
  skip-only     — No hook, no fuzzy; mark unknown_squash and continue (safest)
  never-ask     — Same as skip-only, silent forever

EOF

  # In an interactive skill, the orchestrator calls this and then uses
  # AskUserQuestion to capture the choice. In a non-interactive run, default
  # to skip-only to avoid hanging. ESPALIER_NONINTERACTIVE preferred;
  # HARNESS_NONINTERACTIVE honored for legacy callers.
  if [ -z "${ESPALIER_NONINTERACTIVE:-${HARNESS_NONINTERACTIVE:-}}" ]; then
    # Placeholder — actual espalier-fix skill uses AskUserQuestion and writes the file.
    # If you're running this directly, edit the decision file by hand:
    #   echo "fuzzy-allowed" > espalier/.merge-hook-decision
    :
  else
    echo "skip-only" > espalier/.merge-hook-decision
    echo "Non-interactive mode: defaulted to skip-only." >&2
  fi
}
