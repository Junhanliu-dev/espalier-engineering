#!/bin/bash
# espalier-stats.sh — read-only lane-quality report over the espalier/ audit
# chain. Run manually from the repo root:
#
#   bash espalier/hooks/espalier-stats.sh
#
# Prints markdown to stdout. Writes NOTHING. Every section degrades to a
# "none" line when its source data is absent — a fresh install reports
# honestly instead of erroring. bash-3.2 safe (no associative arrays).
#
# What it measures (the lagging quality signals the docs call Layer 3):
#   - per-lane volume + terminal-status distribution (changes/*/*/pipeline-state.md)
#   - review-round + rollback distributions (the escalation counters)
#   - grill verdict mix (GRILLED / SKIPPED: crisp / --no-grill / non-interactive)
#   - charted vs uncharted feats (requirements.md charted_from:) — code rounds,
#     rollbacks, and the fix echo (fix-lane caused_by pointing at each cohort)
#   - simplify-filed changes (requirements.md simplify_from:) vs hand-written
#     refactors — code rounds, rollbacks, withdrawn cuts, simplify tags
#   - spawn shape per change (v0.25): coder spawns, handoffs, parallel parts,
#     fresh-session resumes — from coding-log/ and the HANDOFF / RESUMED rows;
#     (v0.26) contract phases covered at Stage 3 vs coder-spawned, and the
#     session-boundary preferences chosen at the approval gate;
#     (v0.27) changes whose coder logged a `### Deviations` block and Stage 3
#     BLOCKED rows — the territory-vs-contract channel in use
#   - workspace docs (report-only): every CLAUDE.md / AGENTS.md with size + last change
#   - per-map ticket/fog/session/spawned-change state (espalier/maps/)
#   - convention divergence hotspots (conv_fold, when drift-helpers is present)

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$ROOT" || exit 1
[ -d espalier ] || { echo "no espalier/ directory here — nothing to report"; exit 0; }

CH=espalier/changes
MAPS=espalier/maps

# _stat_dist LABEL <<< "one number per line" — min/median/mean/max, count-aware.
_stat_dist() {
  awk -v label="$1" '
    { v[++n] = $1; sum += $1 }
    END {
      if (n == 0) { printf "%s: none\n", label; exit }
      # insertion sort — n is small
      for (i = 2; i <= n; i++) { x = v[i]; j = i - 1
        while (j >= 1 && v[j] > x) { v[j+1] = v[j]; j-- } v[j+1] = x }
      med = (n % 2) ? v[(n+1)/2] : (v[n/2] + v[n/2+1]) / 2
      printf "%s: n=%d min=%s median=%s mean=%.2f max=%s\n", label, n, v[1], med, sum/n, v[n]
    }'
}

# _last_status STATEFILE — last `- Status:` value, or IN_PROGRESS-ish fallback.
_last_status() {
  awk -F': ' '/^- Status:/ { s = $2 } END { print (s == "" ? "(no status line)" : s) }' "$1"
}

echo "# Espalier Stats — $(date -u +%Y-%m-%d)"
echo

# ── Changes by lane ──────────────────────────────────────────────────────────
echo "## Changes by lane"
echo
if [ ! -d "$CH" ] || ! ls "$CH"/*/*/pipeline-state.md >/dev/null 2>&1; then
  echo "none — no changes recorded yet"
else
  for type_dir in "$CH"/*/; do
    type=$(basename "$type_dir")
    [ "$type" = "_template" ] && continue
    ls "$type_dir"*/pipeline-state.md >/dev/null 2>&1 || continue
    total=0
    statuses=""
    for sf in "$type_dir"*/pipeline-state.md; do
      total=$((total + 1))
      statuses="$statuses
$(_last_status "$sf")"
    done
    dist=$(printf '%s\n' "$statuses" | grep -v '^$' | sort | uniq -c | sort -rn \
           | awk '{ c=$1; sub(/^[[:space:]]*[0-9]+[[:space:]]+/, ""); printf "%s%s=%s", (NR>1 ? " " : ""), $0, c }')
    echo "- **$type**: $total ($dist)"
  done
fi
echo

# ── Review rounds + rollbacks ────────────────────────────────────────────────
echo "## Review rounds + rollbacks"
echo
if [ -d "$CH" ] && ls "$CH"/*/*/pipeline-state.md >/dev/null 2>&1; then
  # `- Review Rounds: req=N/D, code=N/D, test=N/D` — numerators only.
  for kind in req code test; do
    sed -n -E "s/^- Review Rounds:.* ${kind}=([0-9]+)\/.*/\1/p" "$CH"/*/*/pipeline-state.md 2>/dev/null \
      | _stat_dist "${kind} rounds"
  done
  sed -n -E 's/^- Total Rollbacks: ([0-9]+).*/\1/p' "$CH"/*/*/pipeline-state.md 2>/dev/null \
    | _stat_dist "rollbacks"
else
  echo "none"
fi
echo

# ── Spawn shape (per change) ─────────────────────────────────────────────────
# v0.25: coding-report.md is the CURRENT spawn's report and every prior
# spawn's report is one file in coding-log/ (archived by the orchestrator
# before each later spawn), so coder spawns per change = 1 + coding-log
# files. Handoffs = `| 3 | HANDOFF n |` rows (or *-handoff-*.md archives),
# parts = *-stage3-part*.md archives, fresh-session resumes = RESUMED rows.
# Every number degrades to `none` on an install without the new rows.
echo "## Spawn shape (per change)"
echo
if [ -d "$CH" ] && ls "$CH"/*/*/pipeline-state.md >/dev/null 2>&1; then
  spawns=""; handoffs=""; parts=""; resumes=""; commits=""
  for sf in "$CH"/*/*/pipeline-state.md; do
    dir=$(dirname "$sf")
    case "$dir" in */_template/*|*/_template) continue ;; esac
    if [ -d "$dir/coding-log" ]; then
      n_log=$(ls "$dir/coding-log" 2>/dev/null | grep -c '\.md$')
      [ -f "$dir/coding-report.md" ] && spawns="$spawns
$((n_log + 1))" || spawns="$spawns
$n_log"
      parts="$parts
$(ls "$dir/coding-log" 2>/dev/null | grep -c 'stage3-part')"
    elif [ -f "$dir/coding-report.md" ]; then
      spawns="$spawns
1"
    fi
    h=$(grep -cE '^\| 3 \| HANDOFF ' "$sf" 2>/dev/null); h=${h:-0}
    if [ "$h" -eq 0 ] && [ -d "$dir/coding-log" ]; then
      h=$(ls "$dir/coding-log" 2>/dev/null | grep -c -- '-handoff-')
    fi
    handoffs="$handoffs
$h"
    r=$(grep -cE '^\| [0-9]+ \| RESUMED ' "$sf" 2>/dev/null); r=${r:-0}
    resumes="$resumes
$r"
    c=$(grep -cE '^\| 7 \| [0-9a-f]+ \|' "$sf" 2>/dev/null); c=${c:-0}
    commits="$commits
$c"
  done
  if [ -z "$(printf '%s\n' "$spawns" | grep -v '^$')" ]; then
    echo "none — no coding reports yet"
  else
    printf '%s\n' "$spawns"   | grep -v '^$' | _stat_dist "coder spawns per change"
    printf '%s\n' "$handoffs" | grep -v '^$' | _stat_dist "handoffs per change"
    printf '%s\n' "$parts"    | grep -v '^$' | _stat_dist "parallel parts per change"
    printf '%s\n' "$resumes"  | grep -v '^$' | _stat_dist "fresh-session resumes per change"
    printf '%s\n' "$commits"  | grep -v '^$' | _stat_dist "commits per change (Stage 7 rows)"
    # v0.26: where the contract phase went — covered at Stage 3 (no coder
    # spawn), a coder spawned for the gaps, or no contract at all; and the
    # session-boundary preference the human chose at the approval gate.
    cov=0; spawned=0; nocon=0; sb_none=0; sb_2=0; sb_4=0; sb_both=0
    for sf in "$CH"/*/*/pipeline-state.md; do
      case "$sf" in */_template/*) continue ;; esac
      if grep -qE '^\| 5 \| PASSED \|[^|]*\| folded: contract covered' "$sf" 2>/dev/null; then cov=$((cov + 1))
      elif grep -qE '^\| 5 \| (IN_PROGRESS|STARTED) \|[^|]*\| .*contract phase' "$sf" 2>/dev/null; then spawned=$((spawned + 1))
      elif grep -qE '^\| 5 \| SKIPPED \|[^|]*\| folded: no contract' "$sf" 2>/dev/null; then nocon=$((nocon + 1)); fi
      case "$(grep -m1 '^- Session-Boundary:' "$sf" 2>/dev/null | awk '{print $3}')" in
        none) sb_none=$((sb_none + 1)) ;; after-2) sb_2=$((sb_2 + 1)) ;;
        after-4) sb_4=$((sb_4 + 1)) ;; both) sb_both=$((sb_both + 1)) ;;
      esac
    done
    echo "contract phases: covered-at-Stage-3=$cov coder-spawned=$spawned no-contract=$nocon"
    echo "session boundaries chosen: none=$sb_none after-2=$sb_2 after-4=$sb_4 both=$sb_both"
    # v0.27: the territory-vs-contract channel — changes whose coder logged
    # deviations (coding-report.md or any archived report) and Stage 3
    # BLOCKED rows (the human resolved a criterion mid-implementation).
    dev_changes=0; blocked=0
    for sf in "$CH"/*/*/pipeline-state.md; do
      case "$sf" in */_template/*) continue ;; esac
      dir=$(dirname "$sf")
      if grep -qs '^### Deviations' "$dir/coding-report.md" "$dir"/coding-log/*.md 2>/dev/null; then dev_changes=$((dev_changes + 1)); fi
      b=$(grep -cE '^\| 3 \| BLOCKED ' "$sf" 2>/dev/null); b=${b:-0}; blocked=$((blocked + b))
    done
    echo "deviations: changes-with-logged-deviations=$dev_changes stage3-blocked-rows=$blocked"
    echo
    echo "(Quality reads: handoffs are a coder finishing bounded work at a clean"
    echo "point — a change that hands off habitually wants smaller sub-tasks at"
    echo "decomposition; resumes are the human taking a session boundary;"
    echo "commits per change near 1 means the coder is still landing the whole"
    echo "task as one commit — the Commit Discipline wants one seam per commit;"
    echo "contract phases covered at Stage 3 are the coder writing its abuse"
    echo "tests with the code — a rising coder-spawned count means the coder's"
    echo "classification is missing fields the auditor names; logged"
    echo "deviations are the code refusing the contract as written — many"
    echo "per change means Stage 1 is not reading the territory it should."
    echo "Pre-v0.25 changes have no coding-log/ and count as one spawn.)"
  fi
else
  echo "none"
fi
echo

# ── Stage durations ──────────────────────────────────────────────────────────
echo "## Stage durations (from Stage History timestamps)"
echo
if [ ! -d "$CH" ] || ! ls "$CH"/*/*/pipeline-state.md >/dev/null 2>&1; then
  echo "none"
elif ! command -v python3 >/dev/null 2>&1; then
  echo "stage durations: unavailable (python3 not found)"
else
  # Span = gap between consecutive Stage History rows, attributed to the
  # EARLIER row's stage and classified by the row that CLOSES it (a gate row
  # is written after the human answers, so the wait ends at that row). Rows
  # noting non-interactive/auto-* never count as human — headless fleets and
  # maprun workers write those markers with zero human wait behind them.
  # Parsing is bounded to the "## Stage History" section (the same file holds
  # Commits/Follow-up tables); one unparsable row skips that row only.
  find "$CH" -mindepth 3 -maxdepth 3 -name pipeline-state.md -not -path "*/_template/*" 2>/dev/null \
  | python3 -c '
import sys, re
from datetime import datetime

FORMATS = ("%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%dT%H:%M")
HUMAN = ("requirements approved", "approved by user", "delivery", "grilled", "skipped:", "resumed")
UNATTENDED = ("non-interactive", "auto-")

def parse_ts(s):
    s = s.strip()
    for f in FORMATS:
        try:
            return datetime.strptime(s, f)
        except ValueError:
            pass
    return None

lanes = {}

for path in sys.stdin:
    path = path.strip()
    if not path:
        continue
    m = re.search(r"changes/([^/]+)/", path)
    lane = m.group(1) if m else "?"
    L = lanes.setdefault(lane, {"stages": {}, "cls": {"human": 0, "agent": 0, "other": 0}, "skipped": 0})
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        continue
    sect = re.search(r"^## Stage History\n(.*?)(?=^## |\Z)", text, re.M | re.S)
    if not sect:
        continue
    rows = []
    for line in sect.group(1).splitlines():
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 3 or cells[0].lower() == "stage" or set(cells[0]) <= {"-", " "}:
            continue
        ts = parse_ts(cells[2])
        if ts is None:
            L["skipped"] += 1
            rows.append(None)
            continue
        rows.append((cells[0], cells[1], ts, cells[3] if len(cells) > 3 else ""))
    for a, b in zip(rows, rows[1:]):
        if a is None or b is None:
            continue
        secs = int((b[2] - a[2]).total_seconds())
        if secs < 0:
            continue
        try:
            stage = int(re.match(r"\d+", a[0]).group(0))
        except AttributeError:
            stage = -1
        L["stages"].setdefault(stage, []).append(secs)
        note = (b[3] + " " + b[1]).lower()
        if any(u in note for u in UNATTENDED):
            cls = "agent"
        elif any(h in note for h in HUMAN):
            cls = "human"
        elif b[0][:1].isdigit() and 3 <= int(re.match(r"\d+", b[0]).group(0)) <= 6:
            cls = "agent"
        else:
            cls = "other"
        L["cls"][cls] += secs

def dist(vals):
    n = len(vals)
    v = sorted(vals)
    med = v[n // 2] if n % 2 else (v[n // 2 - 1] + v[n // 2]) / 2
    return "n=%d min=%ds median=%ds mean=%.1fs max=%ds" % (n, v[0], med, sum(v) / n, v[-1])

printed = False
for lane in sorted(lanes):
    L = lanes[lane]
    if not L["stages"]:
        continue
    printed = True
    for st in sorted(L["stages"]):
        label = ("stage %d" % st) if st >= 0 else "stage ?"
        print("- **%s** %s: %s" % (lane, label, dist(L["stages"][st])))
    extra = " (skipped_rows=%d)" % L["skipped"] if L["skipped"] else ""
    c = L["cls"]
    print("- **%s** totals: human-wait=%ds agent-work=%ds other=%ds%s" % (lane, c["human"], c["agent"], c["other"], extra))
if not printed:
    print("none — no parsable Stage History timestamps yet")
'
  echo
  echo "(Approximate by design — the buckets answer \"where did the hour go\","
  echo "not billing. Minute-resolution legacy timestamps floor to 0s spans."
  echo "Post-fold (v0.23) Stage 4 rows are code+tests reviews and Stage 5/6 may"
  echo "be SKIPPED rows with ~0s spans — compare durations within-era.)"
fi
echo

# ── Grill verdicts ───────────────────────────────────────────────────────────
echo "## Grill verdicts (Stage 1 residual-ambiguity mix)"
echo
if [ -d "$CH" ] && ls "$CH"/*/*/pipeline-state.md >/dev/null 2>&1; then
  g=$(grep -ho 'GRILLED' "$CH"/*/*/pipeline-state.md 2>/dev/null | wc -l | tr -d ' ')
  gl=$(grep -ho 'GRILLED (light)' "$CH"/*/*/pipeline-state.md 2>/dev/null | wc -l | tr -d ' ')
  gf=$(grep -ho 'GRILLED (full)' "$CH"/*/*/pipeline-state.md 2>/dev/null | wc -l | tr -d ' ')
  gu=$((g - gl - gf))   # pre-v0.23 rows recorded a bare GRILLED with no tier
  sc=$(grep -ho 'SKIPPED: crisp' "$CH"/*/*/pipeline-state.md 2>/dev/null | wc -l | tr -d ' ')
  sn=$(grep -ho 'SKIPPED: --no-grill' "$CH"/*/*/pipeline-state.md 2>/dev/null | wc -l | tr -d ' ')
  si=$(grep -ho 'SKIPPED: non-interactive' "$CH"/*/*/pipeline-state.md 2>/dev/null | wc -l | tr -d ' ')
  echo "GRILLED=$g (light=$gl full=$gf untiered=$gu)  crisp=$sc  no-grill=$sn  non-interactive=$si"
  echo
  echo "(A map-charted slice should trend crisp/light — high GRILLED among"
  echo "charted feats means maps are under-specifying their slices.)"
else
  echo "none"
fi
echo

# ── Charted vs uncharted feats ───────────────────────────────────────────────
echo "## Charted vs uncharted feats (map-lane echo)"
echo
if [ -d "$CH/feat" ] && ls "$CH"/feat/*/pipeline-state.md >/dev/null 2>&1; then
  charted_n=0; uncharted_n=0
  charted_code=""; uncharted_code=""
  charted_rb=""; uncharted_rb=""
  charted_slugs=""
  for sf in "$CH"/feat/*/pipeline-state.md; do
    dir=$(dirname "$sf"); slug=$(basename "$dir")
    code=$(sed -n -E 's/^- Review Rounds:.* code=([0-9]+)\/.*/\1/p' "$sf" | head -1)
    rb=$(sed -n -E 's/^- Total Rollbacks: ([0-9]+).*/\1/p' "$sf" | head -1)
    if grep -q '^charted_from:' "$dir/requirements.md" 2>/dev/null; then
      charted_n=$((charted_n + 1))
      charted_slugs="$charted_slugs $slug"
      [ -n "$code" ] && charted_code="$charted_code
$code"
      [ -n "$rb" ] && charted_rb="$charted_rb
$rb"
    else
      uncharted_n=$((uncharted_n + 1))
      [ -n "$code" ] && uncharted_code="$uncharted_code
$code"
      [ -n "$rb" ] && uncharted_rb="$uncharted_rb
$rb"
    fi
  done
  echo "charted feats:   $charted_n"
  echo "uncharted feats: $uncharted_n"
  printf '%s\n' "$charted_code"   | grep -v '^$' | _stat_dist "  charted code rounds"
  printf '%s\n' "$uncharted_code" | grep -v '^$' | _stat_dist "  uncharted code rounds"
  printf '%s\n' "$charted_rb"     | grep -v '^$' | _stat_dist "  charted rollbacks"
  printf '%s\n' "$uncharted_rb"   | grep -v '^$' | _stat_dist "  uncharted rollbacks"

  # Fix echo: each fix change's caused_by target lands in one cohort.
  fix_charted=0; fix_uncharted=0; fix_unlinked=0
  if [ -d "$CH/fix" ] && ls "$CH"/fix/*/requirements.md >/dev/null 2>&1; then
    for rf in "$CH"/fix/*/requirements.md; do
      target=$(sed -n -E 's/^caused_by:[[:space:]]*(.+)$/\1/p' "$rf" | head -1 | tr -d ' ')
      if [ -z "$target" ]; then
        fix_unlinked=$((fix_unlinked + 1)); continue
      fi
      tslug=$(basename "$target")
      case " $charted_slugs " in
        *" $tslug "*) fix_charted=$((fix_charted + 1)) ;;
        *)            fix_uncharted=$((fix_uncharted + 1)) ;;
      esac
    done
  fi
  echo "  fix echo: against-charted=$fix_charted against-uncharted=$fix_uncharted unlinked=$fix_unlinked"
  echo "  (normalize by cohort size before comparing — charted=$charted_n uncharted=$uncharted_n)"
else
  echo "none — no feat changes yet"
fi
echo

# ── Simplify-filed changes ───────────────────────────────────────────────────
# simplify-lane echo: every change whose requirements.md carries
# simplify_from: (a cut filed by /espalier-simplify under refactor/, or a
# retirement-map slice under feat/) against hand-written refactors.
echo "## Simplify-filed changes (simplify-lane echo)"
echo
if [ -d "$CH" ] && ls "$CH"/*/*/requirements.md >/dev/null 2>&1 \
   && grep -l '^simplify_from:' "$CH"/*/*/requirements.md >/dev/null 2>&1; then
  s_n=0; h_n=0
  s_code=""; h_code=""; s_rb=""; h_rb=""
  s_status=""; withdrawn=0; tags=0
  for rf in "$CH"/*/*/requirements.md; do
    dir=$(dirname "$rf"); sf="$dir/pipeline-state.md"
    [ -f "$sf" ] || continue
    code=$(sed -n -E 's/^- Review Rounds:.* code=([0-9]+)\/.*/\1/p' "$sf" | head -1)
    rb=$(sed -n -E 's/^- Total Rollbacks: ([0-9]+).*/\1/p' "$sf" | head -1)
    if grep -q '^simplify_from:' "$rf" 2>/dev/null; then
      s_n=$((s_n + 1))
      [ -n "$code" ] && s_code="$s_code
$code"
      [ -n "$rb" ] && s_rb="$s_rb
$rb"
      s_status="$s_status
$(_last_status "$sf")"
      w=$(grep -c 'simplify: missed consumer' "$sf" 2>/dev/null); withdrawn=$((withdrawn + ${w:-0}))
      t=$(grep -c '\[simplify-' "$sf" 2>/dev/null); tags=$((tags + ${t:-0}))
    elif [ "$(basename "$(dirname "$dir")")" = "refactor" ]; then
      h_n=$((h_n + 1))
      [ -n "$code" ] && h_code="$h_code
$code"
      [ -n "$rb" ] && h_rb="$h_rb
$rb"
    fi
  done
  echo "simplify-filed changes: $s_n"
  echo "hand-written refactors: $h_n"
  printf '%s\n' "$s_code" | grep -v '^$' | _stat_dist "  simplify-filed code rounds"
  printf '%s\n' "$h_code" | grep -v '^$' | _stat_dist "  hand-written refactor code rounds"
  printf '%s\n' "$s_rb"   | grep -v '^$' | _stat_dist "  simplify-filed rollbacks"
  printf '%s\n' "$h_rb"   | grep -v '^$' | _stat_dist "  hand-written refactor rollbacks"
  st_line=$(printf '%s\n' "$s_status" | grep -v '^$' | sort | uniq -c | awk '{ printf "%s=%s ", $2, $1 }')
  echo "  simplify-filed statuses: ${st_line:-none}"
  echo "  withdrawn (missed consumer): $withdrawn"
  echo "  simplify tags in review snapshots: $tags"
  echo "  (Quality reads: withdrawn = the survey record was wrong — a rising"
  echo "  rate means the scout prompt needs tightening; simplify-filed code"
  echo "  rounds at or below hand-written refactors means the proof record is"
  echo "  doing its job.)"
else
  echo "none — no simplify-filed changes yet"
fi
echo

# ── Ceiling markers ──────────────────────────────────────────────────────────
# v0.28: deliberate shortcuts with a named limit — `ceiling: <limit>; <trigger>`
# in a code comment (harness-coder.md → Solution Selection Ladder). Read-only
# ledger over tracked source: count, the ones naming no trigger (no `;`), each
# row with its blame date. espalier/ and the grep-only paths are never source.
echo "## Ceiling markers (deliberate shortcuts with a named limit)"
echo
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  _cl_excl="':(exclude)espalier/'"
  for _p in $(grep -m1 '^grep-only-paths:' espalier/.espalier-config 2>/dev/null | cut -d: -f2-); do
    case "$_p" in
      */) _cl_excl="$_cl_excl ':(glob,exclude)${_p}**' ':(glob,exclude)**/${_p}**'" ;;
      *)  _cl_excl="$_cl_excl ':(glob,exclude)$_p' ':(glob,exclude)**/$_p'" ;;
    esac
  done
  _cl_rows=$(eval "git grep -nE '(#|//|--|/\\*|<!--) ?ceiling:' -- . $_cl_excl" 2>/dev/null)
  if [ -n "$_cl_rows" ]; then
    _cl_n=$(printf '%s\n' "$_cl_rows" | grep -c .)
    _cl_nt=$(printf '%s\n' "$_cl_rows" | grep -vcE 'ceiling:[^;]*;' || true); _cl_nt=${_cl_nt:-0}
    echo "ceilings: markers=$_cl_n no-trigger=$_cl_nt"
    printf '%s\n' "$_cl_rows" | while IFS= read -r _r; do
      _f=${_r%%:*}; _rest=${_r#*:}; _ln=${_rest%%:*}; _txt=${_rest#*:}
      _txt=$(printf '%s' "$_txt" | sed -E 's/^.*ceiling:[[:space:]]*//; s/[[:space:]]*(\*\/|-->)[[:space:]]*$//')
      _t=$(git blame -L"$_ln,$_ln" --porcelain -- "$_f" 2>/dev/null | awk '/^author-time /{print $2; exit}')
      _d=""
      if [ -n "$_t" ]; then _d=$(date -r "$_t" +%Y-%m-%d 2>/dev/null || date -d "@$_t" +%Y-%m-%d 2>/dev/null); fi
      _tag=""; case "$_txt" in *\;*) ;; *) _tag=" [no-trigger]" ;; esac
      echo "- $_f:$_ln${_d:+ (since $_d)} — $_txt$_tag"
    done
    echo
    echo "(Quality reads: a marker is a shortcut the coder chose under the"
    echo "ladder — the count is not a defect count; no-trigger rows are the ones"
    echo "that rot, the reviewer files [no-trigger] when the line is next in a"
    echo "diff; /espalier-simplify reads every marker as a lead and files a fired"
    echo "trigger as a cut or an upgrade change.)"
  else
    echo "none — no ceiling: markers in tracked source"
  fi
else
  echo "not a git work tree"
fi
echo

# ── Workspace docs (report-only) ─────────────────────────────────────────────
# Every CLAUDE.md / AGENTS.md in the repo with its size and last-change date.
# Since Claude Code 2.1.259 a coder that Reads under a workspace gets that
# workspace's doc chain injected whole; espalier does not own these docs —
# the coder's Docs clause keeps their claims true, trimming them is the
# owner's lever, and this row is how its effect is seen. No threshold.
echo "## Workspace docs (report-only)"
echo
wd=$(git ls-files 2>/dev/null | grep -E '(^|/)(CLAUDE|AGENTS)\.md$')
if [ -z "$wd" ]; then
  echo "none — no CLAUDE.md / AGENTS.md tracked"
else
  printf '%s\n' "$wd" | while IFS= read -r f; do
    [ -f "$f" ] || continue
    kb=$(( ($(wc -c < "$f") + 1023) / 1024 ))
    last=$(git log -1 --format=%cs -- "$f" 2>/dev/null); [ -n "$last" ] || last="?"
    echo "- $f — ${kb} KB — last change $last"
  done
  echo
  echo "(The root instruction file is always loaded; a subdirectory doc is"
  echo "injected whole on Claude Code when an agent Reads under it, and reaches"
  echo "Codex / Copilot coders only through the pack's Scoped-docs line.)"
fi
echo

# ── Maps ─────────────────────────────────────────────────────────────────────
echo "## Maps"
echo
if [ ! -d "$MAPS" ] || ! ls "$MAPS"/*/map.md >/dev/null 2>&1; then
  echo "none — no maps charted yet"
else
  for mf in "$MAPS"/*/map.md; do
    mdir=$(dirname "$mf"); mslug=$(basename "$mdir")
    mstatus=$(sed -n -E 's/^status:[[:space:]]*([A-Z_]+).*/\1/p' "$mf" | head -1)
    t_open=0; t_closed=0; t_oos=0
    g_n=0; r_n=0; p_n=0; k_n=0
    if ls "$mdir"/tickets/*.md >/dev/null 2>&1; then
      for tf in "$mdir"/tickets/*.md; do
        st=$(sed -n -E 's/^status:[[:space:]]*([a-z-]+).*/\1/p' "$tf" | head -1)
        ty=$(sed -n -E 's/^type:[[:space:]]*([a-z]+).*/\1/p' "$tf" | head -1)
        case "$st" in
          open)          t_open=$((t_open + 1)) ;;
          closed)        t_closed=$((t_closed + 1)) ;;
          out-of-scope)  t_oos=$((t_oos + 1)) ;;
        esac
        case "$ty" in
          grilling)  g_n=$((g_n + 1)) ;;
          research)  r_n=$((r_n + 1)) ;;
          prototype) p_n=$((p_n + 1)) ;;
          task)      k_n=$((k_n + 1)) ;;
        esac
      done
    fi
    # Session-log rows: table lines between "## Session log" and the next "##",
    # minus the header + separator.
    sessions=$(awk '/^## Session log/{f=1; next} /^## /{f=0} f && /^\|/' "$mf" | tail -n +3 | grep -c . || true)
    # Fog: non-empty, non-comment lines in "## Not yet specified".
    fog=$(awk '/^## Not yet specified/{f=1; next} /^## /{f=0} f && !/^<!--/ && !/^-->/ && NF' "$mf" | grep -c . || true)
    spawned=$(awk '/^## Spawned Changes/{f=1; next} /^## /{f=0} f && /^\|/' "$mf" | tail -n +3 | grep -c . || true)
    echo "- **$mslug** [$mstatus] tickets: open=$t_open closed=$t_closed out-of-scope=$t_oos" \
         "(grilling=$g_n research=$r_n prototype=$p_n task=$k_n) sessions=$sessions fog-remaining=$fog spawned=$spawned"
  done
  echo
  echo "(Quality reads: fog-remaining should shrink across sessions; a CLEARED"
  echo "map with spawned rows still open is mid-build; closed-per-session near 1"
  echo "means the one-ticket rule held.)"
fi
echo

# ── Convention divergence ────────────────────────────────────────────────────
echo "## Convention divergence (top keys)"
echo
if [ -f espalier/hooks/drift-helpers.sh ]; then
  . espalier/hooks/drift-helpers.sh
  if type conv_fold >/dev/null 2>&1; then
    out=$(conv_fold 2>/dev/null | sort -t"$(printf '\t')" -k2,2rn | head -5 \
          | awk -F'\t' '{ printf "- %s: diverges=%s status=%s\n", $1, $2, $3 }')
    if [ -n "$out" ]; then
      printf '%s\n' "$out"
      echo
      echo "(On a greenfield install, early divergence against decided rules is"
      echo "the system converging — watch that counts fall, not that they are zero.)"
    else
      echo "none recorded"
    fi
  else
    echo "drift-helpers present but conv_fold missing (pre-v0.16 install)"
  fi
else
  echo "drift-helpers not installed"
fi

# ── Adoption nudges ──────────────────────────────────────────────────────────
# Report-only: surfaces a shipped-but-unused opt-in when the data says it
# would pay. Never writes config — discovery proposes, the human confirms.
# Gated-push proxy: `| 7 | <sha> | <files> |` Commits rows (one per Stage 7
# push, idempotent per SHA).
if [ -d "$CH" ] && ! grep -q '^hook-parallel-gates:' espalier/.espalier-config 2>/dev/null; then
  pushes=$(grep -hcE '^\| 7 \| ' "$CH"/*/*/pipeline-state.md 2>/dev/null | awk '{s+=$1} END{print s+0}')
  if [ "${pushes:-0}" -ge 3 ]; then
    echo
    echo "## Adoption nudges"
    echo
    echo "hook-parallel-gates not set — if build/lint/tests are independent,"
    echo "opting in saves ~40% per gated push (see docs). Opt in only when the"
    echo "three discovered commands are truly independent."
  fi
fi
