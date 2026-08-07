#!/usr/bin/env bash
# Judge-validation harness for the map eval judge (rubric.md "Judge validation").
# The LLM judge in run.sh must be trusted before its catch-rate is. This script
# measures judge-vs-human agreement on a fixture subset and gates at >= 75%.
#
#   bash eval/map/validate-judge.sh generate
#       Runs the map skill + judge on the subset. Writes transcripts, the
#       judge's scores, and a BLANK hand-score sheet you fill in by eye.
#       Unlike the grill validator there is no per-question grid: every map
#       dimension is per-fixture, so handscore.tsv is the only sheet.
#
#       Fill, per fixture: surfaced (a count), placement (0/1/2),
#       typing (0/1/2), contracts_ok (true/false), behavior_correct
#       (true/false — 'true' when the fixture carries no expected_behavior).
#
#   bash eval/map/validate-judge.sh rollup
#       Derives each fixture's human `verdict` row from the hand-scored
#       dimensions via rubric.md "Per-fixture pass" — never hand-enter it.
#
#   bash eval/map/validate-judge.sh compare
#       Reads your filled sheet + the judge scores, computes per-dimension
#       agreement, prints PASS/FAIL against the 0.75 gate.
#
# Subset = a fixed 5-fixture core spanning every family, PLUS every
# shadow-*.md present in fixtures/ — the judge is validated across seed and
# shadow material alike.
#
# Dev/QA infra — NOT shipped to target projects. Bash 3.2 compatible (macOS).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
FIXTURES="$HERE/fixtures"
RUBRIC="$HERE/rubric.md"
SKILL="$HERE/../../skills/espalier-init/templates/skills/espalier-map.md"
GRILL_SKILL="$HERE/../../skills/espalier-init/templates/skills/espalier-grill.md"
OUT="$HERE/judge-validation"
AGREE_GATE="0.75"
GATE_COVERAGE="0.8"

CORE_SUBSET="chart-01-team-crm chart-03-crisp-endpoint chart-05-tempt-build work-01-resolve-notifications work-02-collision-data-access"

subset() {
  # Core + every shadow fixture present.
  local s="$CORE_SUBSET" f
  for f in "$FIXTURES"/shadow-*.md; do
    [ -e "$f" ] || continue
    s="$s $(basename "$f" .md)"
  done
  printf '%s' "$s"
}

# Tolerances (judge vs human counts as agreeing within these):
#   surfaced          exact count +/- 1
#   placement         exact (0/1/2)
#   typing            exact (0/1/2)
#   contracts_ok      exact (true/false)
#   behavior_correct  exact (true/false)
#   verdict           exact PASS/FAIL (derived on the human side by `rollup`)

planted_count() {
  # $1 = fixture file. planted_decisions entries + planted_collisions entries.
  awk '
    /^planted_decisions:[[:space:]]*\[\][[:space:]]*$/  { next }
    /^planted_collisions:[[:space:]]*\[\][[:space:]]*$/ { next }
    /^planted_decisions:/  { blk="d"; next }
    /^planted_collisions:/ { blk="c"; next }
    /^[A-Za-z_]+:/         { blk="" }
    blk != "" && /^[[:space:]]+-[[:space:]]+id:/  { n++ }
    blk != "" && /^[[:space:]]+-[[:space:]]+doc:/ { n++ }
    END { print n + 0 }
  ' "$1"
}

run_map() {
  local fixture="$1"
  claude -p --output-format text \
"You are running the espalier-map skill in EVAL MODE.

EVAL MODE rules:
- There is no filesystem, no git, no marker file, and no AskUserQuestion. STATE every
  artifact you would produce, verbatim, in the transcript instead: the session marker
  you would write/remove, map.md in full, every ticket file in full, every bash command
  you would run (do NOT actually run anything).
- The fixture's answer_script is the human. When you would ask the user, find the
  matching asks_about entry and use its reply. If NO entry matches your question, the
  human is unavailable for it: record it as an Open Question with a named conservative
  default — NEVER invent the user's answer.
- A '## MOCK MAP' block in the fixture is the ENTIRE contents of that espalier/maps/
  directory. A '## MOCK CONTEXT' block is the ENTIRE espalier/rules/ + espalier/wiki/.
  No block of either kind = those directories are empty/absent.
- The max-open-tickets cap for this run is the fixture's max_open_tickets value.
- Grilling-ticket resolution and destination-naming use espalier-grill mode=decision;
  its skill text follows the map skill below.
- Otherwise follow the map skill exactly.

Map skill definition:
$(cat "$SKILL")

Grill skill definition (for mode=decision):
$(cat "$GRILL_SKILL")

Fixture:
$(cat "$fixture")

Run the session the fixture's mode calls for (chart, or work on target_ticket). Output the
full transcript: every question + which answer_script reply you used, every artifact you
would write (map.md, tickets) in full, and every action you would take, in order." 2>/dev/null
}

judge() {
  local fixture="$1" transcript="$2"
  claude -p --output-format text \
"You are the map eval JUDGE. Rubric:
$(cat "$RUBRIC")

Fixture:
$(cat "$fixture")

Map transcript:
$(cat "$transcript")

Score the run per the rubric. planted = planted_decisions count plus planted_collisions
count; surfaced per rubric dimensions 1 and 6. placement and typing per dimensions 2-3
(0 when planted is 0). contracts_ok per dimension 4. behavior_correct judges
expected_behavior when present (true when absent). Output ONE line of compact JSON only:
{\"planted\":N,\"surfaced\":N,\"placement\":0-2,\"typing\":0-2,\"contracts_ok\":true,\"behavior_correct\":true,\"verdict\":\"PASS|FAIL\"}" \
    2>/dev/null
}

json_extract() {
  printf '%s' "$1" | tr '\n' ' ' | sed -E 's/^[^{]*//; s/[^}]*$//'
}

cmd="${1:-}"
case "$cmd" in
  generate)
    [ -f "$SKILL" ] || { echo "ERROR: skill not found at $SKILL"; exit 2; }
    mkdir -p "$OUT/transcripts"
    printf 'fixture\tdimension\thuman_score\tnote\n' > "$OUT/handscore.tsv"
    printf 'fixture\tsurfaced\tplacement\ttyping\tcontracts_ok\tbehavior_correct\tverdict\n' > "$OUT/judge-scores.tsv"
    printf 'fixture\tplanted\tcoverage_only\n' > "$OUT/.planted.tsv"
    for fid in $(subset); do
      fx="$FIXTURES/$fid.md"
      [ -f "$fx" ] || { echo "ERROR: missing fixture $fid"; exit 2; }
      echo "map+judge: $fid"
      co="$(sed -n -E 's/^coverage_only:[[:space:]]*//p' "$fx" | head -1)"
      [ "$co" = "true" ] || co="false"
      printf '%s\t%s\t%s\n' "$fid" "$(planted_count "$fx")" "$co" >> "$OUT/.planted.tsv"
      run_map "$fx" > "$OUT/transcripts/$fid.transcript"
      line="$(judge "$fx" "$OUT/transcripts/$fid.transcript")"
      line="$(json_extract "$line")"
      surfaced="$(printf '%s' "$line"  | sed -E 's/.*"surfaced":([0-9]+).*/\1/')"
      placement="$(printf '%s' "$line" | sed -E 's/.*"placement":([0-9]+).*/\1/')"
      typing="$(printf '%s' "$line"    | sed -E 's/.*"typing":([0-9]+).*/\1/')"
      contracts="$(printf '%s' "$line" | sed -E 's/.*"contracts_ok":(true|false).*/\1/')"
      behavior="$(printf '%s' "$line"  | sed -E 's/.*"behavior_correct":(true|false).*/\1/')"
      jverdict="$(printf '%s' "$line"  | sed -E 's/.*"verdict":"([A-Z_]+)".*/\1/')"
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$fid" "$surfaced" "$placement" "$typing" "$contracts" "$behavior" "$jverdict" >> "$OUT/judge-scores.tsv"
      for dim in surfaced placement typing contracts_ok behavior_correct; do
        printf '%s\t%s\t\t\n' "$fid" "$dim" >> "$OUT/handscore.tsv"
      done
      printf '%s\tverdict\t\t(derived by rollup — do not hand-enter)\n' "$fid" >> "$OUT/handscore.tsv"
    done
    echo
    echo "Wrote to $OUT :"
    echo "  transcripts/<fixture>.transcript  — read these to score"
    echo "  judge-scores.tsv                  — the judge's scores (do not edit)"
    echo "  handscore.tsv                     — fill the five dimension rows per fixture,"
    echo "                                      then run 'rollup' to derive verdicts,"
    echo "                                      then 'compare'."
    ;;
  rollup)
    [ -f "$OUT/handscore.tsv" ] || { echo "ERROR: no handscore.tsv — run 'generate' first"; exit 2; }
    [ -f "$OUT/.planted.tsv" ]  || { echo "ERROR: no .planted.tsv — run 'generate' first"; exit 2; }
    tmp="$OUT/.handscore.tsv.tmp"
    awk -F'\t' -v OFS='\t' -v gcov="$GATE_COVERAGE" '
      FNR==NR { if (FNR>1) { planted[$1]=$2; covonly[$1]=$3 } next }
      { lines[++nl]=$0
        if (FNR>1) {
          if      ($2=="surfaced")         sur[$1]=$3
          else if ($2=="placement")        pl[$1]=$3
          else if ($2=="typing")           ty[$1]=$3
          else if ($2=="contracts_ok")     co[$1]=$3
          else if ($2=="behavior_correct") be[$1]=$3
        }
      }
      END {
        for (i=1; i<=nl; i++) {
          split(lines[i], a, "\t")
          if (i>1 && a[2] == "verdict") continue          # stale derived row -> regenerate
          print lines[i]
          if (i==1 || a[2] != "behavior_correct") continue
          f=a[1]; p=planted[f]
          if (sur[f]=="" || pl[f]=="" || ty[f]=="" || co[f]=="" || be[f]=="") {
            printf "WARN: %s — dimensions incomplete; verdict left blank\n", f > "/dev/stderr"
            print f, "verdict", "", "(derived by rollup — score all five dimensions first)"
            continue
          }
          # rubric.md "Per-fixture pass": contracts bar is hard everywhere.
          if (co[f] != "true") { v="FAIL"; note="derived: contracts_ok=false" }
          else if (p+0 == 0) {
            v = (be[f]=="true") ? "PASS" : "FAIL"
            note = sprintf("derived: behavior fixture, behavior_correct=%s", be[f])
          } else if (covonly[f] == "true") {
            cov = sur[f] / p
            v = (cov >= gcov+0) ? "PASS" : "FAIL"
            note = sprintf("derived: coverage-only, coverage=%.2f", cov)
          } else {
            cov = sur[f] / ps
            ok = (cov >= gcov+0) && (pl[f]+0 >= 1) && (ty[f]+0 >= 1)
            v = ok ? "PASS" : "FAIL"
            note = sprintf("derived: coverage=%.2f placement=%s typing=%s", cov, pl[f], ty[f])
          }
          print f, "verdict", v, note
        }
      }
    ' "$OUT/.planted.tsv" "$OUT/handscore.tsv" > "$tmp"
    mv "$tmp" "$OUT/handscore.tsv"
    echo "derived the verdict row for each fully-scored fixture (rubric.md 'Per-fixture pass')"
    ;;
  compare)
    [ -f "$OUT/handscore.tsv" ]    || { echo "ERROR: no handscore.tsv — run 'generate' first"; exit 2; }
    [ -f "$OUT/judge-scores.tsv" ] || { echo "ERROR: no judge-scores.tsv — run 'generate' first"; exit 2; }
    awk -F'\t' '
      function agree(dim, h, j,   d) {
        if (h == "") return -1
        if (dim == "verdict")          return (h == j) ? 1 : 0
        if (dim == "contracts_ok")     return (h == j) ? 1 : 0
        if (dim == "behavior_correct") return (h == j) ? 1 : 0
        d = h - j; if (d < 0) d = -d
        if (dim == "surfaced")  return (d <= 1) ? 1 : 0
        if (dim == "placement") return (h == j) ? 1 : 0
        if (dim == "typing")    return (h == j) ? 1 : 0
        return -1
      }
      FNR==NR {
        if (FNR==1) next
        surfaced[$1]=$2; placement[$1]=$3; typing[$1]=$4
        contracts[$1]=$5; behavior[$1]=$6; verdict[$1]=$7
        next
      }
      FNR==1 { next }
      {
        fx=$1; dim=$2; h=$3
        jv = (dim=="surfaced")?surfaced[fx] : (dim=="placement")?placement[fx] \
           : (dim=="typing")?typing[fx] : (dim=="contracts_ok")?contracts[fx] \
           : (dim=="behavior_correct")?behavior[fx] : verdict[fx]
        a = agree(dim, h, jv)
        if (a < 0) { skipped++; next }
        total++; if (a==1) agreed++
        printf "  %-40s %-17s human=%-6s judge=%-6s %s\n", fx, dim, h, jv, (a==1?"agree":"DISAGREE")
      }
      END {
        if (total==0) { print "ERROR: no scored cells in handscore.tsv"; exit 2 }
        rate = agreed/total
        printf "\nagreement: %d/%d = %.2f  (gate >= %s)\n", agreed, total, rate, gate
        if (skipped>0) printf "(%d cells unscored, skipped)\n", skipped
        if (rate >= gate+0) print "JUDGE: VALIDATED"
        else { print "JUDGE: NOT VALIDATED — sharpen rubric anchors and re-score"; exit 1 }
      }
    ' gate="$AGREE_GATE" "$OUT/judge-scores.tsv" "$OUT/handscore.tsv"
    ;;
  *)
    echo "usage: validate-judge.sh generate|rollup|compare"; exit 2 ;;
esac

