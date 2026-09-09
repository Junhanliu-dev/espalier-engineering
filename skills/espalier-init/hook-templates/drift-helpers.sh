#!/bin/bash
# espalier/hooks/drift-helpers.sh — sourced, never executed.
# Pure-bash drift-state helpers. bash-3.2 safe (no associative arrays).

# Absolute paths resolved once at source time — every helper then works
# regardless of the caller's cwd.
_DS_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
DRIFT_STATE="$_DS_ROOT/espalier/.drift-state.tsv"
DRIFT_LOG="$_DS_ROOT/espalier/.drift.log"
CONVENTIONS="$_DS_ROOT/espalier/.conventions.tsv"          # legacy — read forever, written by pre-v0.17 plugins only
CONVENTIONS_DIR="$_DS_ROOT/espalier/conventions"           # per-key files (k-<slug>.tsv, same row format)
DOCTOR_CADENCE="$_DS_ROOT/espalier/.doctor-cadence"     # tracked — choice only
DOCTOR_LASTRUN="$_DS_ROOT/espalier/.doctor-last-run"    # gitignored — this clone's stamp
DOCTOR_STAMP="$_DS_ROOT/espalier/.doctor-stamp"         # tracked — ONE line, shared team stamp

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

# conv_slug KEY — the canonical per-key filename stem: every character outside
# [A-Za-z0-9._-] maps to `_`; an empty result becomes `_`. The fixed `k-`
# prefix on the FILE name (k-<slug>.tsv) is load-bearing: it keeps keys like
# `aux`/`con`/`nul` from producing Windows-reserved filenames and rules out
# leading-dot/dash surprises. The filename is ROUTING ONLY — rows carry the
# real pattern_key in column 3 and conv_fold folds by column value, so two
# keys sharing a slug merely share a file (cosmetic; counts stay correct).
# One implementation — writer, race guard, and any future reader all call it.
conv_slug() {
  local s
  s=$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_')
  [ -n "$s" ] || s=_
  printf '%s' "$s"
}

# append_convention SLUG KEY LOCATION [COUPLED] — append a `diverges` row to
# the key's file under espalier/conventions/ (created on first write — no
# .gitkeep, no migration artifact). Sanitizes every field. De-dupes on
# (slug,key,location) against the key file AND the legacy .conventions.tsv,
# so a Stage-4 re-run — or an old-plugin branch's earlier legacy append —
# never inflates the promotion count. v0.17+ writers NEVER write the legacy
# file (it stays read-forever via conv_fold).
append_convention() {
  local slug key loc coupled date kf f
  slug=$(_ds_sanitize "$1"); key=$(_ds_sanitize "$2")
  loc=$(_ds_sanitize "$3"); coupled=$(_ds_sanitize "${4:-}")
  date=$(date -u +%Y-%m-%d)
  kf="$CONVENTIONS_DIR/k-$(conv_slug "$key").tsv"
  for f in "$kf" "$CONVENTIONS"; do
    [ -f "$f" ] || continue
    awk -F'\t' -v s="$slug" -v k="$key" -v l="$loc" \
      '$2==s && $3==k && $4==l {found=1} END{exit !found}' "$f" && return 0
  done
  mkdir -p "$CONVENTIONS_DIR"
  if [ -n "$coupled" ]; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$date" "$slug" "$key" "$loc" "diverges" "$coupled" >> "$kf"
  else
    printf '%s\t%s\t%s\t%s\t%s\n'     "$date" "$slug" "$key" "$loc" "diverges" >> "$kf"
  fi
}

# _conv_rows — internal: emit every well-formed convention row from BOTH
# sources, normalized to 7 tab fields:
#   source(legacy|perkey) date slug key location status coupled_with
# Width guard: only NF==5 or NF==6 rows pass; anything else is skipped, never
# fatal. Empty-glob safe: bash 3.2 iterates the literal *.tsv pattern when the
# per-key dir has no files — the -f test drops it.
_conv_rows() {
  local _cf
  if [ -f "$CONVENTIONS" ]; then
    awk -F'\t' 'NF==5 || NF==6 { print "legacy\t" $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6 }' \
      "$CONVENTIONS"
  fi
  if [ -d "$CONVENTIONS_DIR" ]; then
    for _cf in "$CONVENTIONS_DIR"/*.tsv; do
      [ -f "$_cf" ] || continue
      awk -F'\t' 'NF==5 || NF==6 { print "perkey\t" $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6 }' \
        "$_cf"
    done
  fi
  return 0
}

# conv_fold — the single source of truth for reading convention state. Folds
# the legacy espalier/.conventions.tsv AND every espalier/conventions/*.tsv
# (same 5/6-col row format) and emits, per pattern_key:
#   key<TAB>diverges_count<TAB>current_status
# Folding is by COLUMN VALUE (column 3), never by filename — two keys that
# sanitize to the same per-key filename still fold correctly.
# - Observation dedupe on (slug,key,location) ACROSS both sources: an
#   old-plugin branch appending to the legacy file and a new-plugin branch
#   appending the same observation to the key file must count once.
# - Status precedence, clock-free: any per-key-file status row (non-diverges)
#   wins; a legacy status is honored only when the key file has no decision
#   (v0.17+ writers never touch the legacy file, so its status can only be an
#   older decision). No rows at all for a key → status reads `diverges`.
conv_fold() {
  _conv_rows | awk -F'\t' '
    {
      src=$1; slug=$3; key=$4; loc=$5; status=$6
      if (!(key in known)) { known[key]=1; keys[++nk]=key }
      if (status == "diverges") {
        okey = slug SUBSEP key SUBSEP loc
        if (!(okey in obs)) { obs[okey]=1; dcount[key]++ }
      } else if (src == "perkey") {
        pstat[key] = status
      } else {
        lstat[key] = status
      }
    }
    END {
      for (i=1; i<=nk; i++) {
        k = keys[i]
        s = (k in pstat) ? pstat[k] : ((k in lstat) ? lstat[k] : "diverges")
        print k "\t" dcount[k]+0 "\t" s
      }
    }'
}

# conv_observations KEY — print the deduped `diverges` evidence rows for one
# key (date slug key location status [coupled_with]) — the promotion prompt
# needs rows, not counts.
conv_observations() {
  _conv_rows | awk -F'\t' -v k="$1" '
    $4 == k && $6 == "diverges" {
      okey = $3 SUBSEP $4 SUBSEP $5
      if (okey in seen) next
      seen[okey] = 1
      row = $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6
      if ($7 != "") row = row "\t" $7
      print row
    }'
}

# doctor_due — exit 0 if a doctor scan is due. Cadence from the tracked
# .doctor-cadence. Two stamps can satisfy it:
#   - the TRACKED shared .doctor-stamp — team-wide, but ONLY when its result
#     is `clean`: a shared stamp must never mean "scan complete" while the
#     findings sit untracked on one clone, so a `dirty:<N>` stamp satisfies
#     nobody here;
#   - the gitignored local .doctor-last-run — this clone only (the doctor
#     keeps writing it, so the clone that ran a dirty scan is satisfied).
# A shared stamp dated beyond now + 25h skew is rejected with a warning and
# reads as absent (a future-dated stamp must not stay permanently freshest).
# Unknown/empty cadence → not due.
doctor_due() {
  [ -f "$DOCTOR_CADENCE" ] || return 1
  local cadence interval last last_sec now_sec s_ts s_result s_sec
  cadence=$(grep '^cadence:' "$DOCTOR_CADENCE" | awk '{print $2}')
  case "$cadence" in
    manual)       return 1 ;;
    every-change) return 0 ;;
    weekly)       interval=604800 ;;
    monthly)      interval=2592000 ;;
    *)            return 1 ;;
  esac
  now_sec=$(date -u +%s)
  if [ -f "$DOCTOR_STAMP" ]; then
    s_ts=$(awk -F'\t' 'NR==1 {print $1}' "$DOCTOR_STAMP")
    s_result=$(awk -F'\t' 'NR==1 {print $4}' "$DOCTOR_STAMP")
    s_sec=$(_ds_epoch "$s_ts")
    if [ -n "$s_sec" ]; then
      if [ "$s_sec" -gt $(( now_sec + 90000 )) ]; then
        echo "WARN: espalier/.doctor-stamp is future-dated ($s_ts) — rejected; treating as absent" >&2
      elif [ "$s_result" = "clean" ] && [ $(( now_sec - s_sec )) -lt "$interval" ]; then
        return 1
      fi
    fi
  fi
  [ -f "$DOCTOR_LASTRUN" ] || return 0
  last=$(grep '^last_run:' "$DOCTOR_LASTRUN" | awk '{print $2}')
  [ -z "$last" ] && return 0
  last_sec=$(_ds_epoch "$last"); [ -z "$last_sec" ] && return 0
  [ $(( now_sec - last_sec )) -ge "$interval" ]
}

# doctor_stamp SHA — record a completed doctor run in the gitignored LOCAL
# stamp file (this clone only — keeps a dirty-scanning clone satisfied).
doctor_stamp() {
  printf 'last_run: %s\nlast_run_sha: %s\n' "$(_ds_now)" "$1" > "$DOCTOR_LASTRUN"
}

# doctor_stamp_shared SHA RESULT — write the TRACKED shared stamp: ONE line,
# `ts<TAB>sha<TAB>writer<TAB>result`, result = clean | dirty:<N>. Whole-file
# last-writer-wins — deliberately NOT append-only and NEVER union-merged
# (union on a single-line file corrupts it into two; no .gitattributes entry
# may ever be added for it). The doctor is the only writer, at the END of the
# maintenance session, and commits it as its own commit in the weekly
# maintenance PR lane. The stamp records the state at session END: if the
# session's prune cleared every finding, re-run the doctor and restamp
# `clean` — a dirty:N stamp whose findings were fixed in the same PR would
# keep doctor_due firing team-wide forever.
doctor_stamp_shared() {
  local sha="$1" result="$2" writer
  case "$result" in
    clean) ;;
    dirty:*)
      case "${result#dirty:}" in
        ''|*[!0-9]*) echo "doctor_stamp_shared: invalid result '$result' (want clean | dirty:<N>)" >&2; return 1 ;;
      esac
      ;;
    *) echo "doctor_stamp_shared: invalid result '$result' (want clean | dirty:<N>)" >&2; return 1 ;;
  esac
  writer=$(git config user.email 2>/dev/null); [ -n "$writer" ] || writer=unknown
  printf '%s\t%s\t%s\t%s\n' "$(_ds_now)" "$(_ds_sanitize "$sha")" "$(_ds_sanitize "$writer")" "$result" > "$DOCTOR_STAMP"
}

# detect_run_mode — attended | unattended | ambiguous.
#
# DEPRECATED — kept only so pre-v0.9.2 installed skills that source this file
# keep working. A bare `[ -t 0 ]` TTY test reports "unattended" inside an
# interactive Claude Code session (the harness attaches no TTY to tool stdin),
# so gating ANY behavior on this silently degrades interactive runs — that is
# why prune moved to `interactivity_mode` in v0.9.2. Do not add new callers.
detect_run_mode() {
  [ -n "${CI:-}" ]                  && { echo unattended; return; }
  [ -n "${ESPALIER_UNATTENDED:-}" ] && { echo unattended; return; }
  [ -n "${ESPALIER_LOOP:-}" ]       && { echo unattended; return; }
  [ ! -t 0 ]                        && { echo unattended; return; }
  [ -t 0 ] && [ -t 1 ]              && { echo attended;   return; }
  echo ambiguous
}

# interactivity_mode — the CORRECT signal for whether a human checkpoint
# (grill question, requirements approval) can prompt. It answers "can the
# orchestrator ask the user a question right now?" — which the bash TTY test
# CANNOT, since the harness owns the real terminal, not this subshell.
#
# Contract: gates fire UNLESS a run is EXPLICITLY unattended. Only an explicit
# env signal means "no human is here":
#   CI, ESPALIER_UNATTENDED, ESPALIER_LOOP  → unattended (auto-approve + record)
#   ESPALIER_HEADLESS                        → unattended (claude -p / SDK runs
#                                              set this; prompting is impossible)
# Everything else — including the TTY-less-but-interactive Claude Code session —
# is "interactive": the orchestrator CAN and MUST use AskUserQuestion. Ambiguity
# fails SAFE toward asking, never toward silently skipping the gate.
#
# The orchestrator is the authority: if it can call AskUserQuestion, it is
# interactive regardless of what this returns. This helper only decides the
# unattended AUTO-APPROVE path for genuinely headless runs.
interactivity_mode() {
  [ -n "${CI:-}" ]               && { echo unattended; return; }
  [ -n "${ESPALIER_UNATTENDED:-}" ] && { echo unattended; return; }
  [ -n "${ESPALIER_LOOP:-}" ]    && { echo unattended; return; }
  [ -n "${ESPALIER_HEADLESS:-}" ] && { echo unattended; return; }
  echo interactive
}

# --- v0.25 context helpers ---------------------------------------------------
# report_archive · contract_extract · req_shape_check · grep_only_files ·
# scoped_docs · rule_bullets · contract_drift_lines · exit_gate.
# awk / find / wc only — mawk-safe (no {n,m} intervals), BSD-safe (no find
# -printf), and no unquoted word-splitting (an orchestrator may source this
# file under zsh). None of them refuses on size: they move, extract, list, run.

# _repo_rel PATH — a repo-relative path from an absolute or ./-prefixed one.
_repo_rel() {
  case "$1" in
    "$_DS_ROOT"/*) printf '%s' "${1#"$_DS_ROOT"/}" ;;
    ./*)           printf '%s' "${1#./}" ;;
    *)             printf '%s' "$1" ;;
  esac
}

# report_archive DIR LABEL — move DIR/coding-report.md to
# DIR/coding-log/NN-LABEL.md (NN = next free two-digit index) and print the
# new path. The report stays the CURRENT spawn's report; every prior spawn's
# report is one file in coding-log/, read only when named. No-op (exit 0)
# when there is no report to archive.
report_archive() {
  local dir="$1" label="$2" src n dest
  src="$dir/coding-report.md"
  [ -f "$src" ] || return 0
  mkdir -p "$dir/coding-log" || return 1
  n=$(ls "$dir/coding-log" 2>/dev/null | awk -F- '/^[0-9][0-9]-/ { v = $1 + 0; if (v > max) max = v } END { print max + 1 }')
  label=$(printf '%s' "$label" | tr -c 'A-Za-z0-9._-' '_')
  dest=$(printf '%s/coding-log/%02d-%s.md' "$dir" "$n" "$label")
  mv "$src" "$dest" || return 1
  printf '%s\n' "$dest"
}

# contract_extract DIR — copy the `## Security-Sensitive Fields` block of
# DIR/security-record.md (to the next `## ` heading or EOF; the trailing
# VERDICT sentinel is not part of the contract) into DIR/security-contract.md
# and print its path. Exit 1 when the record or the block is absent — the
# caller then reads the block from security-record.md as before.
contract_extract() {
  local dir="$1" rec out tmp
  rec="$dir/security-record.md"; out="$dir/security-contract.md"
  [ -f "$rec" ] || return 1
  grep -q '^## Security-Sensitive Fields' "$rec" || return 1
  tmp=$(mktemp "$out.XXXXXX") || return 1
  awk '
    /^## Security-Sensitive Fields/ { insp = 1; print; next }
    insp && /^## /       { exit }
    insp && /^VERDICT:/  { next }
    insp                 { print }
  ' "$rec" > "$tmp"
  mv "$tmp" "$out" || return 1
  printf '%s\n' "$out"
}

# req_shape_check DIR — print every heading of DIR/requirements.md that sits
# outside the contract set, one per line as "{heading} → requirements-notes.md".
# Report only: always exit 0, never edits, no size, no refusal — the human
# approved the text at the approval gate. The contract set: the requirement
# template's five numbered sections (Goal / Abuse tests as written in the
# field), Open Questions, Convention Notes, the simplify lane's proof
# sections, the map digest, and the fix lane's sections.
req_shape_check() {
  local req="$1/requirements.md"
  [ -f "$req" ] || return 0
  awk '
    /^```/ { fence = !fence; next }
    fence  { next }
    /^##+ / {
      h = $0; sub(/^#+ +/, "", h); sub(/[ \t]+$/, "", h)
      k = tolower(h); sub(/^[0-9]+\. */, "", k)
      if (k ~ /^(requirement summary|goal|acceptance criteria|abuse tests|scope definition|technical considerations|task decomposition|open questions|convention notes|retired surface|simplification evidence|known failure patterns|symptom|reproduction|root cause|files likely touched|layers involved|expected behaviou?r|out of scope|not in scope)/) next
      print h " → requirements-notes.md"
    }
  ' "$req"
  return 0
}

# grep_only_files — every tracked file matching a `grep-only-paths:` pattern
# (space-separated substrings, espalier/.espalier-config) as "path (N KB)",
# one per line. Patterns and sizes, no threshold: the context pack lists
# them and agents grep them instead of Reading them.
grep_only_files() {
  local pats p f
  pats=$(grep '^grep-only-paths:' "$_DS_ROOT/espalier/.espalier-config" 2>/dev/null \
         | head -1 | sed 's/^grep-only-paths:[[:space:]]*//; s/[[:space:]]*#.*$//')
  [ -n "$pats" ] || return 0
  printf '%s\n' "$pats" | tr ' \t' '\n\n' | while IFS= read -r p; do
    [ -n "$p" ] && git -C "$_DS_ROOT" ls-files --full-name 2>/dev/null | grep -F -- "$p"
  done | sort -u | while IFS= read -r f; do
    [ -f "$_DS_ROOT/$f" ] || continue
    printf '%s (%d KB)\n' "$f" $(( ($(wc -c < "$_DS_ROOT/$f") + 1023) / 1024 ))
  done
  return 0
}

# scoped_docs PATH… — the workspace docs (CLAUDE.md / AGENTS.md) on the path
# from each PATH's directory up to, excluding, the repo root — nearest last,
# de-duplicated, repo-relative. The context pack's "- Scoped docs:" line;
# agents grep each for the files they touch and read those sections.
scoped_docs() {
  local p d f chain
  for p in "$@"; do
    p=$(_repo_rel "$p"); d=$(dirname "$p"); chain=""
    while [ -n "$d" ] && [ "$d" != "." ] && [ "$d" != "/" ]; do
      for f in "$d/CLAUDE.md" "$d/AGENTS.md"; do
        [ -f "$_DS_ROOT/$f" ] && chain="$f
$chain"
      done
      d=$(dirname "$d")
    done
    [ -n "$chain" ] && printf '%s' "$chain"
  done | awk 'NF && !seen[$0]++'
  return 0
}

# rule_bullets FILE — the Removed-rules ledger key: every top-level "- "
# bullet (continuation and nested lines folded in) and every table body row,
# whitespace-normalised, one per line. Code fences are skipped. Two renders
# of a rule file compared with `comm -23` on this output show the rules the
# new render dropped.
rule_bullets() {
  [ -f "$1" ] || return 0
  awk '
    function flush() {
      if (cur != "") { gsub(/[ \t]+/, " ", cur); sub(/^ /, "", cur); sub(/ $/, "", cur); print cur }
      cur = ""
    }
    /^```/            { flush(); fence = !fence; next }
    fence             { next }
    /^[-*] /          { flush(); cur = substr($0, 3); next }
    /^\|/             { flush(); if ($0 !~ /^\|[ \t]*:?-+/) { row = $0; gsub(/[ \t]+/, " ", row); print row }; next }
    /^[ \t]+[^ \t]/   { if (cur != "") { cur = cur " " $0; next } }
                      { flush() }
    END               { flush() }
  ' "$1"
}

# contract_drift_lines FILE — report only: every line of a rule file that
# carries what the rules Writing Contract keeps out — a commit SHA, a date,
# a PR number, a shell command, or a history phrase — as "LINE<TAB>KIND<TAB>TEXT".
# Fenced code is skipped, except a fenced shell block, which is itself a hit.
contract_drift_lines() {
  [ -f "$1" ] || return 0
  awk '
    /^```/ {
      if (!fence && $0 ~ /^```(bash|sh|shell|zsh|console)/) print NR "\tshell\t" $0
      fence = !fence; next
    }
    fence { next }
    {
      if ($0 ~ /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)                    { print NR "\tdate\t" $0; next }
      if ($0 ~ /(PR|MR|pull request) *#?[0-9]+/ || $0 ~ /\(#[0-9]+\)/)          { print NR "\tpr\t" $0; next }
      if ($0 ~ /^\$ / || $0 ~ /`(npm|npx|pnpm|yarn|git|bash|sh|make|docker|cargo|go|python3?|pytest|pip|kubectl|helm) /) { print NR "\tshell\t" $0; next }
      if (tolower($0) ~ /(was (deleted|removed|renamed)|used to|no longer|pre-v0\.|removed in|deprecated since|formerly|since v[0-9]|as of v[0-9])/) { print NR "\thistory\t" $0; next }
      n = split($0, w, /[^0-9a-zA-Z]+/)
      for (i = 1; i <= n; i++)
        if (length(w[i]) >= 7 && length(w[i]) <= 40 && w[i] ~ /^[0-9a-f]+$/ && w[i] ~ /[0-9]/) { print NR "\tsha\t" $0; break }
    }
  ' "$1"
}

# _gate_fn_def GATE NAME — print the `NAME() { … }` definition from the
# installed gate: from the line that starts `NAME() {` to the line where the
# running brace depth returns to zero (gsub counts of { and } per line —
# mawk-safe; a brace-grouped multi-line body survives). Empty when absent.
_gate_fn_def() {
  awk -v fn="$2" '
    !insp && index($0, fn "() {") == 1 { insp = 1 }
    insp {
      print
      line = $0
      depth += gsub(/\{/, "{", line) - gsub(/\}/, "}", line)
      if (depth <= 0) exit
    }
  ' "$1"
}

# _gate_test_files DIR — the coding report's test files: the tokens of its
# `- Test files:` line plus the bullets under a `### Test files` heading,
# kept when they exist as files. One per line.
_gate_test_files() {
  local rep="$1/coding-report.md" t
  [ -f "$rep" ] || return 0
  {
    grep '^- Test files:' "$rep" | sed 's/^- Test files://'
    awk '/^#+ +[Tt]est files/ { insp = 1; next } /^#/ { insp = 0 } insp && /^[ \t]*[-*] / { sub(/^[ \t]*[-*] /, ""); print }' "$rep"
  } | tr ',`' '  ' | tr -s ' \t' '\n\n' | while IFS= read -r t; do
    t=$(_repo_rel "$t")
    [ -n "$t" ] && [ -f "$_DS_ROOT/$t" ] && printf '%s\n' "$t"
  done | awk '!seen[$0]++'
  return 0
}

# _gate_scoped_cmd DEF FILE… — when the run_tests body is ONE command whose
# runner takes file paths, print that command with the files appended (`--`
# for npm / pnpm / yarn scripts; package dirs for `go test`). Print nothing
# when the body is multi-line, `cd`s into a workspace the files are not all
# under, or the runner is not path-scopable — the caller then runs the full
# suite: never fewer tests than the coder listed.
_gate_scoped_cmd() {
  local def="$1"; shift
  local body cmd pre="" wd="" f rel files="" pkgs=""
  [ $# -gt 0 ] || return 0
  body=$(printf '%s\n' "$def" | sed '1d;$d' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' | grep -v '^#')
  [ "$(printf '%s\n' "$body" | wc -l | tr -d ' ')" = 1 ] || return 0
  cmd=$body
  case "$cmd" in
    "(cd "*) return 0 ;;
    "cd "*"&&"*)
      wd=${cmd#cd }; wd=${wd%%&&*}; wd=$(printf '%s' "$wd" | tr -d ' "'"'"'')
      cmd=${cmd#*&&}; cmd=${cmd# }; pre="cd $wd && " ;;
  esac
  case "$cmd" in *"&&"*|*"||"*|*";"*|*"|"*|*">"*) return 0 ;; esac
  for f in "$@"; do
    if [ -n "$wd" ]; then
      case "$f" in "$wd"/*) rel=${f#"$wd"/} ;; *) return 0 ;; esac
    else
      rel=$f
    fi
    files="$files $rel"; pkgs="$pkgs
./$(dirname "$rel")/"
  done
  pkgs=$(printf '%s\n' "$pkgs" | grep -v '^$' | sort -u | tr '\n' ' ' | sed 's/ $//')
  case "$cmd" in
    "npm test"|"npm run test"|"npm run test:"*|"pnpm test"|"pnpm run test"*|"yarn test"|"yarn run test"*)
      printf '%s%s --%s' "$pre" "$cmd" "$files" ;;
    "npx jest"*|"npx vitest run"*|"npx mocha"*|jest*|"vitest run"*|mocha*|pytest*|"python -m pytest"*|"python3 -m pytest"*|rspec*|"bundle exec rspec"*|phpunit*|"vendor/bin/phpunit"*)
      printf '%s%s%s' "$pre" "$cmd" "$files" ;;
    "go test"*)
      cmd=${cmd% ./...}; printf '%s%s %s' "$pre" "$cmd" "$pkgs" ;;
    *) return 0 ;;
  esac
}

# exit_gate DIR [TEST_FILE…] — the Stage 3 exit gate as one call: the
# installed gate's run_build and run_lint as two concurrent jobs (per-pid
# waits, each job's output to its own temp file), then run_tests scoped to
# TEST_FILE… (or to the coding report's listed test files when none are
# given; the full suite when the runner is not path-scopable). The commands
# have one source — the function bodies init substituted into
# espalier/hooks/pre-push-gate.sh — each extracted by brace depth, checked
# with `bash -n`, and run in a subshell from the repo root. Prints one line
# per job (`build: exit 0`, `lint: exit 0`, `tests: exit 0 (12 files)`) plus
# the log path of any failure. Exit codes are the contract:
#   0 green · 1 a gate job failed (red — re-spawn the coder with its log)
#   2 a run_* function is missing or unparseable — gate by hand as before
#   3 the greenfield placeholder gate — no gate yet, gate by hand
# Only exit 1 is a red gate; 2 and 3 mean "helper unavailable", never red.
exit_gate() {
  local dir="${1:-.}"; [ $# -gt 0 ] && shift
  local gate="$_DS_ROOT/espalier/hooks/pre-push-gate.sh"
  local name def def_b="" def_l="" def_t="" tmpd pid_b pid_l rc_b rc_l rc_t=0 t scoped nfiles
  if [ -f "$_DS_ROOT/espalier/.greenfield" ] \
     || { [ -f "$gate" ] && ! grep -q '^run_build()' "$gate" && grep -q 'greenfield placeholder' "$gate"; }; then
    echo "exit_gate: no gate yet; run build/lint by hand from development-process.md"
    return 3
  fi
  if [ ! -f "$gate" ]; then
    echo "exit_gate: espalier/hooks/pre-push-gate.sh not found — run the gate by hand as before"
    return 2
  fi
  for name in run_build run_lint run_tests; do
    def=$(_gate_fn_def "$gate" "$name")
    if [ -z "$def" ] || ! printf '%s\n' "$def" | bash -n 2>/dev/null; then
      echo "exit_gate: $name not found / not parseable in espalier/hooks/pre-push-gate.sh — run the gate by hand as before"
      return 2
    fi
    case "$name" in run_build) def_b=$def ;; run_lint) def_l=$def ;; run_tests) def_t=$def ;; esac
  done
  if [ $# -eq 0 ]; then
    while IFS= read -r t; do [ -n "$t" ] && set -- "$@" "$t"; done <<EOF
$(_gate_test_files "$dir")
EOF
  fi
  nfiles=$#
  tmpd=$(mktemp -d "${TMPDIR:-/tmp}/exit-gate.XXXXXX") || return 2
  ( cd "$_DS_ROOT" && eval "$def_b" && run_build ) > "$tmpd/build.log" 2>&1 & pid_b=$!
  ( cd "$_DS_ROOT" && eval "$def_l" && run_lint )  > "$tmpd/lint.log"  2>&1 & pid_l=$!
  wait "$pid_b"; rc_b=$?
  wait "$pid_l"; rc_l=$?
  if [ "$rc_b" -eq 0 ]; then echo "build: exit 0"; else echo "build: exit $rc_b — log: $tmpd/build.log"; fi
  if [ "$rc_l" -eq 0 ]; then echo "lint: exit 0";  else echo "lint: exit $rc_l — log: $tmpd/lint.log"; fi
  if [ "$rc_b" -ne 0 ]; then
    echo "tests: skipped — build red"
    return 1
  fi
  scoped=$(_gate_scoped_cmd "$def_t" "$@")
  if [ -n "$scoped" ]; then
    ( cd "$_DS_ROOT" && eval "$scoped" ) > "$tmpd/tests.log" 2>&1; rc_t=$?
    if [ "$rc_t" -eq 0 ]; then echo "tests: exit 0 ($nfiles files)"; else echo "tests: exit $rc_t ($nfiles files) — log: $tmpd/tests.log"; fi
  else
    ( cd "$_DS_ROOT" && eval "$def_t" && run_tests ) > "$tmpd/tests.log" 2>&1; rc_t=$?
    if [ "$rc_t" -eq 0 ]; then echo "tests: exit 0 (full suite)"; else echo "tests: exit $rc_t (full suite) — log: $tmpd/tests.log"; fi
  fi
  [ "$rc_l" -eq 0 ] && [ "$rc_t" -eq 0 ] && return 0
  return 1
}
