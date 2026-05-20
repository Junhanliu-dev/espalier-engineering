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
