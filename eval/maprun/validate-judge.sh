#!/usr/bin/env bash
# Judge-validation harness for the run eval judge (rubric.md "Judge validation").
# The LLM judge in run.sh must be trusted before its catch-rate is. This script
# measures judge-vs-human agreement on a fixture subset and gates at >= 75%.
#
#   bash eval/maprun/validate-judge.sh generate
#       Runs the run skill (one master pass) + judge on the subset. Writes
#       transcripts, the judge's scores, and a BLANK hand-score sheet you
#       fill in by eye. Every run dimension is per-fixture, so handscore.tsv
#       is the only sheet.
#
#       Fill, per fixture: surfaced (a count), contracts_ok (true/false),
#       behavior_correct (true/false — 'true' when the fixture carries no
#       expected_behavior).
#
#   bash eval/maprun/validate-judge.sh rollup
#       Derives each fixture's human `verdict` row from the hand-scored
#       dimensions via rubric.md "Per-fixture pass" — never hand-enter it.
#
#   bash eval/maprun/validate-judge.sh compare
#       Reads your filled sheet + the judge scores, computes per-dimension
#       agreement, prints PASS/FAIL against the 0.75 gate.
#
# Subset = every fixture in fixtures/ (the lane ships with six), PLUS every
# shadow-*.md present — the judge is validated across seed and shadow
# material alike.
#
# Dev/QA infra — NOT shipped to target projects. Bash 3.2 compatible (macOS).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
FIXTURES="$HERE/fixtures"
RUBRIC="$HERE/rubric.md"
SKILL="$HERE/../../skills/espalier-init/templates/skills/espalier-maprun.md"
OUT="$HERE/judge-validation"
AGREE_GATE="0.75"
# Pinned: stricter-safeguard default models (e.g. Fable) hard-refuse these prompts.
EVAL_MODEL="${EVAL_MODEL:-opus}"
GATE_COVERAGE="0.8"

subset() {
  local f
  for f in "$FIXTURES"/*.md; do
    [ -e "$f" ] || continue
    printf '%s ' "$(basename "$f" .md)"
  done
}

# Tolerances (judge vs human counts as agreeing within these):
#   surfaced          exact count +/- 1
#   contracts_ok      exact (true/false)
#   behavior_correct  exact (true/false)
#   verdict           exact PASS/FAIL (derived on the human side by `rollup`)

planted_count() {
  # $1 = fixture file. planted_hazards entries.
  awk '
    /^planted_hazards:[[:space:]]*\[\][[:space:]]*$/ { next }
    /^planted_hazards:/ { blk=1; next }
    /^[A-Za-z_]+:/      { blk=0 }
    blk && /^[[:space:]]+-[[:space:]]+id:/ { n++ }
    END { print n + 0 }
  ' "$1"
}

run_master() {
  local fixture="$1"
  claude -p --model "$EVAL_MODEL" --output-format text \
"You are running the espalier-maprun skill in EVAL MODE: execute exactly ONE
master pass against a simulated repo, then stop.

EVAL MODE rules:
- There is no filesystem, no git, no processes, and no AskUserQuestion tool. STATE every
  command you would run, verbatim, then take its output from the fixture's
  '## MOCK REPO STATE' command script. If NO entry matches, say so and proceed
  conservatively — NEVER invent command output.
- The fixture's answer_script is the human. Where it has no matching reply, record an
  Open Question with a named conservative default — NEVER invent the user's answer.
- File contents appear as 'file:' entries in the MOCK REPO STATE — same matching rule.
- Follow the run skill exactly. One pass, then a report, then STOP.

Run skill definition:
$(cat "$SKILL")

Fixture:
$(cat "$fixture")

Execute the single master pass. Output the full transcript: every command + which MOCK
entry answered it, every question + which answer_script reply you used, every state
transition, and the final report, in order." 2>/dev/null
}

judge() {
  local fixture="$1" transcript="$2"
  claude -p --model "$EVAL_MODEL" --output-format text \
"You are the run eval JUDGE. Rubric:
$(cat "$RUBRIC")

Fixture:
$(cat "$fixture")

Master-pass transcript:
$(cat "$transcript")

Score the run per the rubric. planted = planted_hazards count; surfaced per rubric
dimension 1. placement and typing do not apply — always report 0. contracts_ok per
dimension 2. behavior_correct judges expected_behavior when present (true when absent).
Output ONE line of compact JSON only:
{\"planted\":N,\"surfaced\":N,\"placement\":0,\"typing\":0,\"contracts_ok\":true,\"behavior_correct\":true,\"verdict\":\"PASS|FAIL\"}" \
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
    printf 'fixture\tsurfaced\tcontracts_ok\tbehavior_correct\tverdict\n' > "$OUT/judge-scores.tsv"
    printf 'fixture\tplanted\n' > "$OUT/.planted.tsv"
    for fid in $(subset); do
      fx="$FIXTURES/$fid.md"
      [ -f "$fx" ] || { echo "ERROR: missing fixture $fid"; exit 2; }
      echo "run+judge: $fid"
      printf '%s\t%s\n' "$fid" "$(planted_count "$fx")" >> "$OUT/.planted.tsv"
      run_master "$fx" > "$OUT/transcripts/$fid.transcript"
      line="$(judge "$fx" "$OUT/transcripts/$fid.transcript")"
      line="$(json_extract "$line")"
      surfaced="$(printf '%s' "$line"  | sed -E 's/.*"surfaced":([0-9]+).*/\1/')"
      contracts="$(printf '%s' "$line" | sed -E 's/.*"contracts_ok":(true|false).*/\1/')"
      behavior="$(printf '%s' "$line"  | sed -E 's/.*"behavior_correct":(true|false).*/\1/')"
      jverdict="$(printf '%s' "$line"  | sed -E 's/.*"verdict":"([A-Z_]+)".*/\1/')"
      printf '%s\t%s\t%s\t%s\t%s\n' "$fid" "$surfaced" "$contracts" "$behavior" "$jverdict" >> "$OUT/judge-scores.tsv"
      for dim in surfaced contracts_ok behavior_correct; do
        printf '%s\t%s\t\t\n' "$fid" "$dim" >> "$OUT/handscore.tsv"
      done
      printf '%s\tverdict\t\t(derived by rollup — do not hand-enter)\n' "$fid" >> "$OUT/handscore.tsv"
    done
    echo
    echo "Wrote to $OUT :"
    echo "  transcripts/<fixture>.transcript  — read these to score"
    echo "  judge-scores.tsv                  — the judge's scores (do not edit)"
    echo "  handscore.tsv                     — fill the three dimension rows per fixture,"
    echo "                                      then run 'rollup' to derive verdicts,"
    echo "                                      then 'compare'."
    ;;
  rollup)
    [ -f "$OUT/handscore.tsv" ] || { echo "ERROR: no handscore.tsv — run 'generate' first"; exit 2; }
    [ -f "$OUT/.planted.tsv" ]  || { echo "ERROR: no .planted.tsv — run 'generate' first"; exit 2; }
    tmp="$OUT/.handscore.tsv.tmp"
    awk -F'\t' -v OFS='\t' -v gcov="$GATE_COVERAGE" '
      FNR==NR { if (FNR>1) planted[$1]=$2; next }
      { lines[++nl]=$0
        if (FNR>1) {
          if      ($2=="surfaced")         sur[$1]=$3
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
          if (sur[f]=="" || co[f]=="" || be[f]=="") {
            printf "WARN: %s — dimensions incomplete; verdict left blank\n", f > "/dev/stderr"
            print f, "verdict", "", "(derived by rollup — score all three dimensions first)"
            continue
          }
          # rubric.md "Per-fixture pass": contracts bar is hard everywhere.
          if (co[f] != "true") { v="FAIL"; note="derived: contracts_ok=false" }
          else if (p+0 == 0) {
            v = (be[f]=="true") ? "PASS" : "FAIL"
            note = sprintf("derived: behavior fixture, behavior_correct=%s", be[f])
          } else {
            cov = sur[f] / p
            v = (cov >= gcov+0) ? "PASS" : "FAIL"
            note = sprintf("derived: coverage=%.2f", cov)
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
        return -1
      }
      FNR==NR {
        if (FNR==1) next
        surfaced[$1]=$2; contracts[$1]=$3; behavior[$1]=$4; verdict[$1]=$5
        next
      }
      FNR==1 { next }
      {
        fx=$1; dim=$2; h=$3
        jv = (dim=="surfaced")?surfaced[fx] : (dim=="contracts_ok")?contracts[fx] \
           : (dim=="behavior_correct")?behavior[fx] : verdict[fx]
        a = agree(dim, h, jv)
        if (a < 0) { skipped++; next }
        total++; if (a==1) agreed++
        printf "  %-32s %-17s human=%-6s judge=%-6s %s\n", fx, dim, h, jv, (a==1?"agree":"DISAGREE")
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
