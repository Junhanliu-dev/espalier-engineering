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
# field), Open Questions, Convention Notes, References, the simplify lane's proof
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
      if (k ~ /^(requirement summary|goal|acceptance criteria|abuse tests|scope definition|technical considerations|task decomposition|open questions|convention notes|references|retired surface|simplification evidence|known failure patterns|symptom|reproduction|root cause|files likely touched|layers involved|expected behaviou?r|out of scope|not in scope)/) next
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

# _gate_scope_line CMD — one test command (`CMD`, or `cd WS && CMD`) scoped
# to the test files read from stdin, one per line: the command with the
# files appended (`--` for npm / pnpm / yarn scripts; package dirs for
# `go test`). Prints nothing when a file is not under WS, the command is
# compound, or the runner is not path-scopable.
_gate_scope_line() {
  local cmd="$1" pre="" wd="" f rel files="" pkgs=""
  case "$cmd" in
    "(cd "*) return 0 ;;
    "cd "*"&&"*)
      wd=${cmd#cd }; wd=${wd%%&&*}; wd=$(printf '%s' "$wd" | tr -d ' "'"'"'')
      cmd=${cmd#*&&}; cmd=${cmd# }; pre="cd $wd && " ;;
  esac
  case "$cmd" in *"&&"*|*"||"*|*";"*|*"|"*|*">"*) return 0 ;; esac
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ -n "$wd" ]; then
      case "$f" in "$wd"/*) rel=${f#"$wd"/} ;; *) return 0 ;; esac
    else
      rel=$f
    fi
    files="$files $rel"; pkgs="$pkgs
./$(dirname "$rel")/"
  done
  [ -n "$files" ] || return 0
  pkgs=$(printf '%s\n' "$pkgs" | grep -v '^$' | sort -u | tr '\n' ' ' | sed 's/ $//')
  case "$cmd" in
    "npm test"|"npm run test"|"npm run test:"*|"pnpm test"|"pnpm run test"*|"yarn test"|"yarn run test"*)
      printf '%s%s --%s' "$pre" "$cmd" "$files" ;;
    "npx jest"*|"npx vitest run"*|"npx mocha"*|jest*|"vitest run"*|mocha*|pytest*|"python -m pytest"*|"python3 -m pytest"*|"uv run pytest"*|"poetry run pytest"*|"pnpm exec vitest run"*|"pnpm vitest run"*|"pnpm exec jest"*|"bun test"*|rspec*|"bundle exec rspec"*|phpunit*|"vendor/bin/phpunit"*)
      printf '%s%s%s' "$pre" "$cmd" "$files" ;;
    "go test"*)
      cmd=${cmd% ./...}; printf '%s%s %s' "$pre" "$cmd" "$pkgs" ;;
    *) return 0 ;;
  esac
}

# _gate_scoped_cmd DEF FILE… — the run_tests body scoped to FILE…, when its
# shape allows it: ONE command whose runner takes file paths (the files
# appended — `_gate_scope_line`), or one workspace line per body line —
# `(cd WS && CMD) || return 1` or `cd WS && CMD`, a monorepo's shape — each
# scoped to the files under WS/ and joined with `&&`, a workspace with no
# listed file dropped. Prints nothing when a file is under no workspace,
# a line has another shape, or a runner is not path-scopable — the caller
# then runs the full suite: never fewer tests than the coder listed.
_gate_scoped_cmd() {
  local def="$1"; shift
  local body nlines cmd wd f sub one out="" claimed=0 total=$#
  [ "$total" -gt 0 ] || return 0
  body=$(printf '%s\n' "$def" | sed '1d;$d' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' | grep -v '^#')
  nlines=$(printf '%s\n' "$body" | wc -l | tr -d ' ')
  if [ "$nlines" = 1 ]; then
    printf '%s\n' "$@" | _gate_scope_line "$body"
    return 0
  fi
  while IFS= read -r cmd; do
    case "$cmd" in
      "(cd "*") || return 1") cmd=${cmd#\(}; cmd=${cmd%) || return 1} ;;
      "cd "*"&&"*) ;;
      *) return 0 ;;
    esac
    wd=${cmd#cd }; wd=${wd%%&&*}; wd=$(printf '%s' "$wd" | tr -d ' "'"'"'')
    sub=""
    for f in "$@"; do
      case "$f" in "$wd"/*) sub="$sub$f
"; claimed=$((claimed + 1)) ;; esac
    done
    [ -n "$sub" ] || continue
    one=$(printf '%s' "$sub" | _gate_scope_line "$cmd")
    [ -n "$one" ] || return 0
    out="$out${out:+ && }($one)"
  done <<EOF
$body
EOF
  [ "$claimed" -eq "$total" ] || return 0
  printf '%s' "$out"
}

# exit_gate DIR [TEST_FILE…] — the Stage 3 exit gate as one call: the
# installed gate's run_build and run_lint as two concurrent jobs (per-pid
# waits, each job's output to its own temp file), then — as soon as the
# build is green, while lint may still be running — run_tests scoped to
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
  if [ "$rc_b" -ne 0 ]; then
    wait "$pid_l"; rc_l=$?
    echo "build: exit $rc_b — log: $tmpd/build.log"
    if [ "$rc_l" -eq 0 ]; then echo "lint: exit 0"; else echo "lint: exit $rc_l — log: $tmpd/lint.log"; fi
    echo "tests: skipped — build red"
    return 1
  fi
  scoped=$(_gate_scoped_cmd "$def_t" "$@")
  if [ -n "$scoped" ]; then
    ( cd "$_DS_ROOT" && eval "$scoped" ) > "$tmpd/tests.log" 2>&1; rc_t=$?
    t="tests: exit $rc_t ($nfiles files)"
  else
    ( cd "$_DS_ROOT" && eval "$def_t" && run_tests ) > "$tmpd/tests.log" 2>&1; rc_t=$?
    t="tests: exit $rc_t (full suite)"
  fi
  wait "$pid_l"; rc_l=$?
  echo "build: exit 0"
  if [ "$rc_l" -eq 0 ]; then echo "lint: exit 0"; else echo "lint: exit $rc_l — log: $tmpd/lint.log"; fi
  if [ "$rc_t" -eq 0 ]; then echo "$t"; else echo "$t — log: $tmpd/tests.log"; fi
  [ "$rc_l" -eq 0 ] && [ "$rc_t" -eq 0 ] && return 0
  return 1
}

# --- v0.26 turn-economy helpers ----------------------------------------------
# contract_gaps · certificate_write · record_commits · drift_index ·
# stage85_drift · backlink_all · regression_verify. Each is a bash block the
# orchestrator used to retype at a stage boundary, with the same file
# effects; the skills now call them by name. Same discipline as above:
# mawk-safe, BSD-safe, zsh-safe, nothing refuses on size.

# contract_gaps DIR — the security contract's entries whose `covered_by:`
# line is missing or `none`, one `field:` value per line — read from
# DIR/security-contract.md, or from the `## Security-Sensitive Fields` block
# of security-record.md when the file is absent. Empty output = every entry
# names a test already in the diff: the orchestrator spawns no contract-phase
# coder and goes straight to the delta review, which proves each entry
# itself. Exit 1 when there is no contract at all.
contract_gaps() {
  local dir="$1" src
  if [ -f "$dir/security-contract.md" ]; then
    src="$dir/security-contract.md"
  elif [ -f "$dir/security-record.md" ] && grep -q '^## Security-Sensitive Fields' "$dir/security-record.md"; then
    src="$dir/security-record.md"
  else
    return 1
  fi
  awk '
    function flush() { if (field != "" && !covered) print field; field = ""; covered = 0 }
    /^## Security-Sensitive Fields/ { insp = 1; next }
    insp && /^## /       { flush(); exit }
    insp && /^- field:/  { flush(); field = $0; sub(/^- field:[ \t]*/, "", field); sub(/[ \t]+$/, "", field); next }
    insp && field != "" && /^[ \t]+covered_by:/ {
      v = $0; sub(/^[ \t]+covered_by:[ \t]*/, "", v); sub(/[ \t]+$/, "", v)
      if (v != "" && tolower(v) != "none") covered = 1
    }
    END { flush() }
  ' "$src"
}

# certificate_write DIR — the review certificate: `git add -A` (so new files
# count), then `Reviewed-Diff: <hash>` of the source diff since the change's
# Base-Ref (espalier/ excluded) in DIR/pipeline-state.md — the last existing
# `Reviewed-Diff:` line overwritten in place, else the line inserted after
# the Base-Ref line. Prints the hash. Exit 1 without a Base-Ref.
certificate_write() {
  local state="$1/pipeline-state.md" base hash n tmp
  [ -f "$state" ] || return 1
  base=$(grep -E '^(- )?Base-Ref:' "$state" | tail -1 | sed 's/.*Base-Ref:[[:space:]]*//' | tr -d '[:space:]')
  [ -n "$base" ] || { echo "certificate_write: no Base-Ref in $state" >&2; return 1; }
  git -C "$_DS_ROOT" add -A >/dev/null 2>&1
  hash=$(git -C "$_DS_ROOT" diff "$base" -- . ':(exclude)espalier/' | git hash-object --stdin)
  n=$(grep -nE '^(- )?Reviewed-Diff:' "$state" | tail -1 | cut -d: -f1)
  tmp=$(mktemp "$state.XXXXXX") || return 1
  if [ -n "$n" ]; then
    awk -v n="$n" -v h="$hash" 'NR == n { sub(/Reviewed-Diff:.*/, "Reviewed-Diff: " h) } { print }' "$state" > "$tmp"
  else
    awk -v h="$hash" '
      { print }
      !done && /^(- )?Base-Ref:/ { print (($0 ~ /^- /) ? "- " : "") "Reviewed-Diff: " h; done = 1 }
    ' "$state" > "$tmp"
  fi
  mv "$tmp" "$state" || return 1
  printf '%s\n' "$hash"
}

# record_commits TYPE SLUG — the Stage 7 commit record: one
# `| 7 | SHA | files |` row per commit in Base-Ref..HEAD (oldest first; HEAD
# alone without a Base-Ref) under `## Commits` in the change's state file,
# idempotent per SHA, each row self-healing the reverse-lookup cache when
# lookup-helpers.sh is installed. Prints the rows it added.
record_commits() {
  local type="$1" slug="$2" state base shas sha files
  state="$_DS_ROOT/espalier/changes/$type/$slug/pipeline-state.md"
  [ -f "$state" ] || return 1
  base=$(grep -E '^(- )?Base-Ref:' "$state" | tail -1 | sed 's/.*Base-Ref:[[:space:]]*//' | tr -d '[:space:]')
  if [ -n "$base" ]; then
    shas=$(git -C "$_DS_ROOT" rev-list --reverse "${base}..HEAD")
  else
    shas=$(git -C "$_DS_ROOT" rev-parse HEAD)
  fi
  grep -q '^## Commits' "$state" \
    || printf '\n## Commits\n| Stage | SHA | Files |\n|-------|-----|-------|\n' >> "$state"
  [ -f "$_DS_ROOT/espalier/hooks/lookup-helpers.sh" ] && . "$_DS_ROOT/espalier/hooks/lookup-helpers.sh"
  printf '%s\n' "$shas" | while IFS= read -r sha; do
    [ -n "$sha" ] || continue
    files=$(git -C "$_DS_ROOT" diff-tree --no-commit-id --name-only -r "$sha" | tr '\n' ',' | sed 's/,$//')
    if ! grep -qE "^\| 7 \| ${sha} " "$state"; then
      printf '| 7 | %s | %s |\n' "$sha" "$files" >> "$state"
      printf '| 7 | %s | %s |\n' "$sha" "$files"
    fi
    type _cache_append >/dev/null 2>&1 && ( cd "$_DS_ROOT" && _cache_append "$sha" "${type}/${slug}" "original" )
  done
  return 0
}

# drift_index TYPE SLUG — Stage 4 post-review: every Convention Drift block
# of the change's review-record.md (parse-drift-blocks.py) flags its rule
# file stale and appends a `convention_drift:` line to the state file; a
# malformed block (two rule files in one block) appends
# `convention_drift_malformed:` instead — never a P0 back into the record.
# Prints the appended lines. No-op without a record or python3.
drift_index() {
  local type="$1" slug="$2" dir rev sha kind rule coupled line
  dir="$_DS_ROOT/espalier/changes/$type/$slug"; rev="$dir/review-record.md"
  [ -f "$rev" ] || return 0
  command -v python3 >/dev/null 2>&1 || { echo "drift_index: python3 not found — drift not indexed" >&2; return 0; }
  sha=$(git -C "$_DS_ROOT" rev-parse HEAD)
  python3 "$_DS_ROOT/espalier/hooks/parse-drift-blocks.py" "$rev" | while IFS="$(printf '\t')" read -r kind rule coupled; do
    case "$kind" in
      DRIFT)
        mark_stale "$rule" "$sha" "convention drift flagged in ${type}/${slug} review"
        line="convention_drift: $rule"
        [ -n "$coupled" ] && line="$line (coupled_with: $coupled)"
        ;;
      MALFORMED) line="convention_drift_malformed: $rule (reviewer bundled blocks — drift NOT indexed)" ;;
      *) continue ;;
    esac
    printf '%s\n' "$line" >> "$dir/pipeline-state.md"
    printf '%s\n' "$line"
  done
  return 0
}

# stage85_drift TYPE SLUG — the Stage 8.5 doc-drift notice: every flagged
# doc as a row of a notify table appended to the change's doc-patches.md
# (edits no doc, blocks nothing) and one summary line on stdout.
stage85_drift() {
  local type="$1" slug="$2" patches stale f tier reason n
  patches="$_DS_ROOT/espalier/changes/$type/$slug/doc-patches.md"
  stale=$(stale_files)
  if [ -z "$stale" ]; then echo "Stage 8.5: no drift."; return 0; fi
  {
    echo ""
    echo "## Stage 8.5 Doc Drift (notify-only)"
    echo "| File | Tier | Reason |"
    echo "|------|------|--------|"
    printf '%s\n' "$stale" | while IFS= read -r f; do
      [ -z "$f" ] && continue
      tier=$(classify_tier "$f")
      reason=$(awk -F'\t' -v x="$f" '$1==x {print $4; exit}' "$DRIFT_STATE")
      echo "| $f | $tier | $reason |"
    done
  } >> "$patches"
  n=$(printf '%s\n' "$stale" | grep -c .)
  echo "Stage 8.5: $n stale doc(s) — run /espalier-prune to refresh. (Not blocking; pipeline continues.)"
}

# _backlink_one SLUG CAUSING_SLUG ROLE LOOKUP — one Follow-up Fixes row in the
# causing change's state file; idempotent on (own slug, role) — the same
# slug can legitimately appear as primary and call_path in different fixes.
_backlink_one() {
  local slug="$1" causing="$2" role="$3" lookup="$4" state reason own
  state="$_DS_ROOT/espalier/changes/$causing/pipeline-state.md"
  [ -f "$state" ] || return 0
  grep -q '^## Follow-up Fixes' "$state" \
    || printf '\n## Follow-up Fixes\n| Fix Slug | Role | Lookup | Reason | Date |\n|----------|------|--------|--------|------|\n' >> "$state"
  own="fix/$slug"
  grep -qF "| $own | $role |" "$state" && return 0
  # The title line sits BELOW the YAML frontmatter — grep it; head -1 would read `---`.
  reason=$(grep -m1 '^# Bug:' "$_DS_ROOT/espalier/changes/fix/$slug/requirements.md" 2>/dev/null | sed 's/^# Bug: //')
  [ -n "$reason" ] || reason="$own"
  printf '| %s | %s | %s | %s | %s |\n' "$own" "$role" "$lookup" "$reason" "$(date -u +%Y-%m-%d)" >> "$state"
  printf '%s -> %s (%s)\n' "$own" "$causing" "$role"
}

# backlink_all SLUG — the fix lane's Stage 7 back-links: every `caused_by:`
# entry of espalier/changes/fix/SLUG/requirements.md whose slug names a real
# change (never unknown / unknown_squash, never a `- note:` overflow row)
# gets its Follow-up Fixes row in the causing change's state file. Prints
# one line per row written. Exit 1 without a requirements file.
backlink_all() {
  local slug="$1" req c_slug c_role c_lookup
  req="$_DS_ROOT/espalier/changes/fix/$slug/requirements.md"
  [ -f "$req" ] || return 1
  awk '
    function flush() {
      if (s != "" && s != "unknown" && s != "unknown_squash") print s "\t" r "\t" l
      s = ""; r = ""; l = ""
    }
    NR == 1 && /^---/ { fm = 1; next }
    fm && /^---/ { flush(); exit }
    fm && /^caused_by:/ { inc = 1; next }
    fm && inc && /^[^ \t-]/ { flush(); inc = 0 }
    inc && /^[ \t]*- / {
      flush()
      if ($0 ~ /^[ \t]*- slug:/) { s = $0; sub(/^[ \t]*- slug:[ \t]*/, "", s); sub(/[ \t]+$/, "", s) }
      next
    }
    inc && s != "" && /^[ \t]+role:/   { r = $0; sub(/^[ \t]+role:[ \t]*/, "", r); sub(/[ \t]+$/, "", r) }
    inc && s != "" && /^[ \t]+lookup:/ { l = $0; sub(/^[ \t]+lookup:[ \t]*/, "", l); sub(/[ \t]+$/, "", l) }
    END { flush() }
  ' "$req" | while IFS="$(printf '\t')" read -r c_slug c_role c_lookup; do
    [ -n "$c_slug" ] || continue
    _backlink_one "$slug" "$c_slug" "$c_role" "$c_lookup"
  done
  return 0
}

# _reg_harness_error FILE — exit 0 when a runner's output shows it failed to
# RUN at all (missing module, bad invocation, nothing collected) rather than
# ran and failed an assertion — conflating the two is how a test that never
# executed gets certified.
_reg_harness_error() {
  grep -qiE 'cannot find module|module ?not ?found|no such file or directory|command not found|ENOENT|ImportError|ModuleNotFoundError|SyntaxError|failed to (resolve|load|collect)|no tests? (found|ran)' "$1"
}

# _reg_last PREFIX DIR — the last line starting with PREFIX in the current
# coding-report.md, else in the newest coding-log/ report that has one.
_reg_last() {
  local prefix="$1" dir="$2" f
  if [ -f "$dir/coding-report.md" ] && grep -q "^$prefix" "$dir/coding-report.md"; then
    grep "^$prefix" "$dir/coding-report.md" | tail -1
    return 0
  fi
  f=$(ls -r "$dir/coding-log"/*.md 2>/dev/null | while IFS= read -r g; do
        grep -q "^$prefix" "$g" && { printf '%s\n' "$g"; break; }
      done)
  [ -n "$f" ] && grep "^$prefix" "$f" | tail -1
  return 0
}

# regression_verify DIR REG_RUN TEST_FILE… — the fix lane's regression check
# at the Stage 3 exit gate, as one call. REG_RUN is the project's runner
# scoped to exactly TEST_FILE… (`npx jest <files>`, `pytest <files>`,
# `npm test -- <files>`), run from the repo root. Two steps, in this order:
# the FIXED tree first (validates the invocation itself — runner found, deps
# resolve, file loads), then the change's Base-Ref in a detached worktree
# with the test files copied in and the installed dependency dirs linked.
# Appends to DIR/coding-report.md and prints:
#   - REGRESSION_VERIFIED: true | false — … | skipped — …
#   - REGRESSION_VERIFIED_SCOPE: <hash of the test files' contents>
# `true` only on a genuine assertion failure at Base-Ref — a harness error
# there is `skipped`, never `true` (a bug whose pre-fix symptom IS a
# load-time error classifies as skipped: the check errs toward human eyes).
# A report carrying `- HANDOFF: true` is left untouched (archived and
# continued by a fresh coder). When the scope hash equals the last recorded
# one (this report, else the newest coding-log/ report), the runs are
# skipped and the previous result is re-appended marked (cached).
regression_verify() {
  local dir="$1" run="$2"; shift 2
  local state cod base scope prev_scope prev_res out_now rc_now wt rc_pre t dep line
  state="$dir/pipeline-state.md"; cod="$dir/coding-report.md"
  if [ ! -f "$cod" ] || grep -q '^- HANDOFF: true' "$cod"; then
    echo "REGRESSION_VERIFIED: skipped this return — coding-report.md is a handoff (archived; continuation coder next)"
    return 0
  fi
  if [ $# -eq 0 ]; then
    line="- REGRESSION_VERIFIED: skipped — no regression test file named"
    printf '%s\n' "$line" >> "$cod"; printf '%s\n' "$line"
    return 0
  fi
  scope=$( (for t in "$@"; do printf '%s %s\n' "$t" "$(git -C "$_DS_ROOT" hash-object "$t" 2>/dev/null)"; done) | sort | git hash-object --stdin )
  prev_scope=$(_reg_last '- REGRESSION_VERIFIED_SCOPE:' "$dir" | sed 's/^- REGRESSION_VERIFIED_SCOPE:[[:space:]]*//')
  prev_res=$(_reg_last '- REGRESSION_VERIFIED:' "$dir"); prev_res=${prev_res% (cached)}
  base=$(grep -E '^(- )?Base-Ref:' "$state" 2>/dev/null | tail -1 | sed 's/.*Base-Ref:[[:space:]]*//' | tr -d '[:space:]')
  if [ -z "$base" ]; then
    line="- REGRESSION_VERIFIED: skipped — no Base-Ref recorded"
  elif [ -n "$prev_scope" ] && [ "$prev_scope" = "$scope" ] && [ -n "$prev_res" ]; then
    line="$prev_res (cached)"
  else
    out_now=$(mktemp "${TMPDIR:-/tmp}/reg-now.XXXXXX") || return 2
    ( cd "$_DS_ROOT" && eval "$run" ) > "$out_now" 2>&1; rc_now=$?
    if [ "$rc_now" -ne 0 ] && _reg_harness_error "$out_now"; then
      line="- REGRESSION_VERIFIED: skipped — scoped invocation could not run on the fixed tree: $(grep -m1 . "$out_now")"
    elif [ "$rc_now" -ne 0 ]; then
      line="- REGRESSION_VERIFIED: false — regression test FAILS on the FIXED code (broken test or unfixed bug) (P0 at Stage 6)"
    else
      wt=$(mktemp -d "${TMPDIR:-/tmp}/reg-base.XXXXXX") || return 2
      if git -C "$_DS_ROOT" worktree add --detach "$wt" "$base" >/dev/null 2>&1; then
        for t in "$@"; do mkdir -p "$wt/$(dirname "$t")"; cp "$_DS_ROOT/$t" "$wt/$t"; done
        for dep in node_modules .venv venv vendor; do
          [ -e "$_DS_ROOT/$dep" ] && [ ! -e "$wt/$dep" ] && ln -s "$_DS_ROOT/$dep" "$wt/$dep"
        done
        ( cd "$wt" && eval "$run" ) > "$wt/.reg.out" 2>&1; rc_pre=$?
        if [ "$rc_pre" -eq 0 ]; then
          line="- REGRESSION_VERIFIED: false — test PASSES on pre-fix code; it does not capture the bug (P0 at Stage 6)"
        elif _reg_harness_error "$wt/.reg.out"; then
          line="- REGRESSION_VERIFIED: skipped — could not RUN at Base-Ref (harness error, not an assertion failure): $(grep -m1 . "$wt/.reg.out")"
        else
          line="- REGRESSION_VERIFIED: true (test fails on pre-fix $base, passes on fix)"
        fi
        git -C "$_DS_ROOT" worktree remove --force "$wt" >/dev/null 2>&1
      else
        line="- REGRESSION_VERIFIED: skipped — could not create worktree at $base"
        rm -rf "$wt"
      fi
    fi
    rm -f "$out_now"
  fi
  printf '%s\n' "$line" >> "$cod"
  printf -- '- REGRESSION_VERIFIED_SCOPE: %s\n' "$scope" >> "$cod"
  printf '%s\n' "$line"
  return 0
}

# --- v0.27 unknowns helpers ---------------------------------------------------
# deviations_list · open_question_append · delivery_brief (+ _md_section).
# The territory-vs-contract channel: the coder logs departures, the panel
# verifies them, the human sees them at the Stage 4 PASS and in the delivery
# brief. Same rules as the blocks above — awk only, mawk/BSD-safe, nothing
# refuses on size, nothing here decides anything.

# _md_section FILE HEADING — print the body of the first markdown section
# whose heading line is exactly HEADING (any `#` depth), up to the next
# heading of the same or a higher level, a `- HANDOFF:` / `- BLOCKED-ON-…`
# sentinel, or EOF. Fenced blocks inside the section are printed as-is.
# Prints nothing (exit 0) when the file or the heading is absent.
_md_section() {
  local f="$1" h="$2"
  [ -f "$f" ] || return 0
  awk -v want="$h" '
    /^```/ { if (insp) print; fence = !fence; next }
    fence  { if (insp) print; next }
    /^#+ / {
      if (insp) {
        d = 0; while (substr($0, d + 1, 1) == "#") d++
        if (d <= depth) exit
      } else if ($0 == want) {
        insp = 1; depth = 0; while (substr($0, depth + 1, 1) == "#") depth++
        next
      }
    }
    insp && (/^- HANDOFF: / || /^- BLOCKED-ON-REQUIREMENT: /) { exit }
    insp { print }
  ' "$f"
}

# deviations_list DIR — the entries of the `### Deviations` block of
# DIR/coding-report.md, one per line, blank lines dropped. Nothing when the
# report or the block is absent (exit 0 either way): the caller prints what
# it gets and counts the lines.
deviations_list() {
  _md_section "$1/coding-report.md" "### Deviations" | grep -v '^[[:space:]]*$'
  return 0
}

# open_question_append DIR TEXT — append `- TEXT` under `## Open Questions`
# in DIR/requirements.md, creating the heading at the end when absent. The
# orchestrator records a ratified (or unattended-default) resolution of a
# Stage 3 BLOCKED report here; the criterion itself is never rewritten by
# this helper. Prints the line it wrote. Exit 1 without a requirements.md.
open_question_append() {
  local req="$1/requirements.md" text="$2" tmp
  [ -f "$req" ] || return 1
  if grep -q '^## Open Questions' "$req"; then
    tmp="$req.oqtmp"
    # insert after the last non-blank line of the section (or right after
    # the heading when the section is empty)
    awk -v line="- $text" '
      { buf[NR] = $0 }
      /^## Open Questions/ && !seen { seen = 1; insp = 1; at = NR; next }
      insp && /^## / { insp = 0 }
      insp && !/^[[:space:]]*$/ { at = NR }
      END {
        for (i = 1; i <= NR; i++) { print buf[i]; if (i == at) print line }
      }
    ' "$req" > "$tmp" && mv "$tmp" "$req"
  else
    if [ -s "$req" ] && [ -n "$(tail -c1 "$req")" ]; then printf '\n' >> "$req"; fi
    printf '\n## Open Questions\n- %s\n' "$text" >> "$req"
  fi
  printf -- '- %s\n' "$text"
}

# delivery_brief TYPE SLUG — write espalier/changes/TYPE/SLUG/delivery-brief.md
# from the change's own records (requirements.md, coding-report.md, the two
# review records, pipeline-state.md, ci-result.md, deploy-result.md):
# sections copied, nothing paraphrased, nothing judged; a section with no
# source is one `none` line. Prints the path and one count line. Exit 1
# without a requirements.md.
delivery_brief() {
  local type="$1" slug="$2" dir out req cod state rev sec n_dev n_round n_commit body
  dir="$_DS_ROOT/espalier/changes/$type/$slug"
  req="$dir/requirements.md"; cod="$dir/coding-report.md"; state="$dir/pipeline-state.md"
  rev="$dir/review-record.md"; sec="$dir/security-record.md"; out="$dir/delivery-brief.md"
  [ -f "$req" ] || return 1
  _sec_or_none() {  # FILE HEADING — the section body, or "none"
    body=$(_md_section "$1" "$2" | grep -v '^[[:space:]]*$')
    if [ -n "$body" ]; then printf '%s\n' "$body"; else echo "none"; fi
  }
  _first_heading() {  # FILE PATTERN — the first heading line matching PATTERN (regex), else ""
    grep -E "$2" "$1" 2>/dev/null | head -1
  }
  local h_sum h_ac h_tc h_oq h_ref
  h_sum=$(_first_heading "$req" '^##+ .*[Rr]equirement [Ss]ummary'); [ -n "$h_sum" ] || h_sum=$(_first_heading "$req" '^##+ .*(Goal|Symptom)')
  h_ac=$(_first_heading "$req" '^##+ .*[Aa]cceptance [Cc]riteria')
  h_tc=$(_first_heading "$req" '^##+ .*[Tt]echnical [Cc]onsiderations')
  h_oq=$(_first_heading "$req" '^##+ Open Questions')
  h_ref=$(_first_heading "$req" '^##+ References')
  n_dev=$(deviations_list "$dir" | grep -c .)
  n_round=$(grep -cE '^\| 4 \| ROUND [0-9]+ FAIL ' "$state" 2>/dev/null); n_round=${n_round:-0}
  n_commit=$(grep -cE '^\| 7 \| [0-9a-f]+ \|' "$state" 2>/dev/null); n_commit=${n_commit:-0}
  {
    echo "# Delivery Brief: $type/$slug"
    echo ""
    echo "Assembled from the change's records by \`delivery_brief\` — copied, not authored."
    echo ""
    echo "## What was asked"
    [ -n "$h_sum" ] && _sec_or_none "$req" "$h_sum" || echo "none"
    echo ""
    echo "## Acceptance criteria"
    [ -n "$h_ac" ] && _sec_or_none "$req" "$h_ac" || echo "none"
    echo ""
    echo "## Decisions the code froze (Technical Considerations)"
    [ -n "$h_tc" ] && _sec_or_none "$req" "$h_tc" || echo "none"
    echo ""
    echo "## Decisions ratified by the human (Open Questions)"
    [ -n "$h_oq" ] && _sec_or_none "$req" "$h_oq" || echo "none"
    echo ""
    echo "## References the requester named"
    [ -n "$h_ref" ] && _sec_or_none "$req" "$h_ref" || echo "none"
    echo ""
    echo "## Deviations (the code vs the contract — panel-verified)"
    body=$(deviations_list "$dir"); if [ -n "$body" ]; then printf '%s\n' "$body"; else echo "none"; fi
    echo ""
    echo "## Deliberately not built (coder Notes)"
    body=$(grep -E '^- Notes:' "$cod" 2>/dev/null | head -1 | sed 's/^- Notes:[[:space:]]*//'); [ -n "$body" ] && echo "$body" || echo "none"
    echo ""
    echo "## Files and tests"
    body=$(grep -E '^- (Files created|Files modified|Test files|Docs):' "$cod" 2>/dev/null); [ -n "$body" ] && printf '%s\n' "$body" || echo "none"
    echo ""
    echo "## Verdicts (last sentinel of each record)"
    body=$( { grep '^VERDICT:' "$rev" 2>/dev/null | tail -1 | sed 's/^/- review: /'; grep '^VERDICT:' "$sec" 2>/dev/null | tail -1 | sed 's/^/- security: /'; } ); [ -n "$body" ] && printf '%s\n' "$body" || echo "none"
    echo ""
    echo "## Rounds, handoffs, blocks (Stage History)"
    body=$(grep -E '^\| [0-9]+ \| (ROUND [0-9]+ FAIL|HANDOFF [0-9]+|BLOCKED [0-9]+|ESCALATED|RESUMED) ' "$state" 2>/dev/null); [ -n "$body" ] && printf '%s\n' "$body" || echo "none"
    echo ""
    echo "## Commits"
    body=$(grep -E '^\| 7 \| [0-9a-f]+ \|' "$state" 2>/dev/null); [ -n "$body" ] && printf '%s\n' "$body" || echo "none"
    echo ""
    echo "## CI and deploy"
    if [ -f "$dir/ci-result.md" ]; then echo "- ci-result.md: present"; else echo "- ci-result.md: none"; fi
    if [ -f "$dir/deploy-result.md" ]; then echo "- deploy-result.md: present"; else echo "- deploy-result.md: none"; fi
  } > "$out"
  printf '%s\n' "$out"
  echo "delivery brief: $n_dev deviations, $n_round rounds, $n_commit commits"
}
