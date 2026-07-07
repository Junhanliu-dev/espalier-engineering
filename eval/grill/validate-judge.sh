#!/usr/bin/env bash
# Judge-validation harness for the grill eval judge (see rubric.md "Judge validation").
# The LLM judge in run.sh must be trusted before its catch-rate is. This script measures
# judge-vs-human agreement on a fixed 6-fixture subset and gates at >= 75%.
#
#   bash eval/grill/validate-judge.sh generate
#       Runs grill + judge on the subset. Writes transcripts, the judge's own scores,
#       and a BLANK hand-score sheet you fill in by eye.
#
#   # ...open judge-validation/handscore.tsv, read each transcript, fill human_score...
#
#   bash eval/grill/validate-judge.sh compare
#       Reads your filled sheet + the judge scores, computes per-dimension agreement,
#       prints PASS/FAIL against the 0.75 gate.
#
# Dev/QA infra — NOT shipped to target projects. Bash 3.2 compatible (macOS).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
FIXTURES="$HERE/fixtures"
RUBRIC="$HERE/rubric.md"
SKILL="$HERE/../../skills/espalier-init/templates/skills/espalier-grill.md"
OUT="$HERE/judge-validation"
AGREE_GATE="0.75"

# Fixed 6-fixture subset: spans all three tiers and mixes seed + shadow fixtures so the
# judge is validated across the range it will actually score.
SUBSET="full-01-dashboard-faster shadow-full-02-decimal-points light-01-csv-export shadow-light-02-invoice-failures skip-01-copyright-year shadow-skip-01-bold-titles"

# Agreement tolerances per dimension (judge vs human counts as agreeing within these):
#   surfaced        exact count +/- 1
#   depth_cal       exact (0/1/2)
#   non_obvious     +/- 0.5
#   discrimination  +/- 0.5

run_grill() {
  local fixture="$1"
  claude -p --output-format text \
"You are running the espalier-grill skill in EVAL MODE.

EVAL MODE rules: skip Step 0's TTY check — the fixture's answer_script is your
interactive channel. Use it to answer your own grill questions; never ask a real
human. Otherwise follow the skill exactly.

Skill definition:
$(cat "$SKILL")

Fixture (frontmatter holds the answer_script):
$(cat "$fixture")

Run the grill. Output the full transcript: the tier you chose, every question asked,
and which answer_script reply you used for each." 2>/dev/null
}

judge() {
  local fixture="$1" transcript="$2"
  claude -p --output-format text \
"You are the grill eval JUDGE. Rubric:
$(cat "$RUBRIC")

Fixture:
$(cat "$fixture")

Grill transcript:
$(cat "$transcript")

Score the run. Output ONE line of compact JSON only, no prose:
{\"planted\":N,\"surfaced\":N,\"depth_cal\":0-2,\"non_obvious\":0.0-2.0,\"discrimination\":0.0-2.0,\"verdict\":\"PASS|FAIL\"}" \
    2>/dev/null
}

cmd="${1:-}"
case "$cmd" in
  generate)
    [ -f "$SKILL" ] || { echo "ERROR: skill not found at $SKILL"; exit 2; }
    mkdir -p "$OUT/transcripts"
    printf 'fixture\tdimension\thuman_score\tnote\n' > "$OUT/handscore.tsv"
    printf 'fixture\tsurfaced\tdepth_cal\tnon_obvious\tdiscrimination\n' > "$OUT/judge-scores.tsv"
    for fid in $SUBSET; do
      fx="$FIXTURES/$fid.md"
      [ -f "$fx" ] || { echo "ERROR: missing fixture $fid"; exit 2; }
      echo "grill+judge: $fid"
      run_grill "$fx" > "$OUT/transcripts/$fid.transcript"
      line="$(judge "$fx" "$OUT/transcripts/$fid.transcript")"
      surfaced="$(printf '%s' "$line" | sed -E 's/.*"surfaced":([0-9]+).*/\1/')"
      depth="$(printf '%s' "$line"    | sed -E 's/.*"depth_cal":([0-9]+).*/\1/')"
      nonobv="$(printf '%s' "$line"   | sed -E 's/.*"non_obvious":([0-9.]+).*/\1/')"
      disc="$(printf '%s' "$line"     | sed -E 's/.*"discrimination":([0-9.]+).*/\1/')"
      printf '%s\t%s\t%s\t%s\t%s\n' "$fid" "$surfaced" "$depth" "$nonobv" "$disc" >> "$OUT/judge-scores.tsv"
      for dim in surfaced depth_cal non_obvious discrimination; do
        printf '%s\t%s\t\t\n' "$fid" "$dim" >> "$OUT/handscore.tsv"
      done
    done
    echo
    echo "Wrote to $OUT :"
    echo "  transcripts/<fixture>.transcript  — read these to score"
    echo "  judge-scores.tsv                  — the judge's scores (do not edit)"
    echo "  handscore.tsv                     — fill the human_score column, then run 'compare'"
    ;;
  compare)
    [ -f "$OUT/handscore.tsv" ]    || { echo "ERROR: no handscore.tsv — run 'generate' first"; exit 2; }
    [ -f "$OUT/judge-scores.tsv" ] || { echo "ERROR: no judge-scores.tsv — run 'generate' first"; exit 2; }
    awk -F'\t' '
      # tolerances
      function agree(dim, h, j,   d) {
        if (h == "") return -1                       # unscored cell -> skip
        d = h - j; if (d < 0) d = -d
        if (dim == "surfaced")       return (d <= 1) ? 1 : 0
        if (dim == "depth_cal")      return (h == j) ? 1 : 0
        if (dim == "non_obvious")    return (d <= 0.5) ? 1 : 0
        if (dim == "discrimination") return (d <= 0.5) ? 1 : 0
        return -1
      }
      FNR==NR {
        if (FNR==1) next
        js[$1] = $0                                  # judge row keyed by fixture
        surfaced[$1]=$2; depth[$1]=$3; nonobv[$1]=$4; disc[$1]=$5
        next
      }
      FNR==1 { next }                                # skip handscore header
      {
        fx=$1; dim=$2; h=$3
        jv = (dim=="surfaced")?surfaced[fx] : (dim=="depth_cal")?depth[fx] : (dim=="non_obvious")?nonobv[fx] : disc[fx]
        a = agree(dim, h, jv)
        if (a < 0) { skipped++; next }
        total++; if (a==1) agreed++
        printf "  %-32s %-14s human=%-5s judge=%-5s %s\n", fx, dim, h, jv, (a==1?"agree":"DISAGREE")
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
    echo "usage: validate-judge.sh generate|compare"; exit 2 ;;
esac
