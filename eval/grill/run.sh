#!/usr/bin/env bash
# Grill eval harness runner.
# Runs the espalier-grill skill against each golden fixture, scores the result with
# an LLM judge, and gates on the aggregate catch-rate (plan section 9).
#
# Dev/QA infra — NOT shipped to target projects.
# Bash 3.2 compatible (macOS); no GNU-only tools; sed uses -E for BSD.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
FIXTURES="$HERE/fixtures"
RUBRIC="$HERE/rubric.md"
SKILL="$HERE/../../skills/espalier-init/templates/skills/espalier-grill.md"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

GATE_CATCH_RATE="0.80"

[ -f "$SKILL" ]    || { echo "ERROR: grill skill not found at $SKILL"; exit 2; }
[ -f "$RUBRIC" ]   || { echo "ERROR: rubric not found at $RUBRIC"; exit 2; }
[ -d "$FIXTURES" ] || { echo "ERROR: fixtures dir not found at $FIXTURES"; exit 2; }

total_planted=0
total_surfaced=0
shadow_planted=0
shadow_surfaced=0
nonshadow_planted=0
nonshadow_surfaced=0
fail_count=0
results=""   # accumulated: "fixture_id\ttier\tcoverage\tverdict\n"

run_grill() {
  # $1 = fixture file. Prints the grill transcript to stdout.
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
  # $1 = fixture file, $2 = transcript file. Prints one compact JSON line.
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

for fixture in "$FIXTURES"/*.md; do
  [ -e "$fixture" ] || { echo "ERROR: no fixtures found"; exit 2; }
  fid="$(basename "$fixture" .md)"
  tier="$(sed -n -E 's/^expected_tier:[[:space:]]*//p' "$fixture" | head -1)"
  shadow="$(sed -n -E 's/^shadow:[[:space:]]*//p' "$fixture" | head -1)"

  if ! run_grill "$fixture" > "$WORK/$fid.transcript"; then
    echo "$fid: grill run failed"; fail_count=$((fail_count + 1)); continue
  fi
  if ! line="$(judge "$fixture" "$WORK/$fid.transcript")"; then
    echo "$fid: judge failed"; fail_count=$((fail_count + 1)); continue
  fi

  planted="$(printf '%s' "$line"  | sed -E 's/.*"planted":([0-9]+).*/\1/')"
  surfaced="$(printf '%s' "$line" | sed -E 's/.*"surfaced":([0-9]+).*/\1/')"
  verdict="$(printf '%s' "$line"  | sed -E 's/.*"verdict":"([A-Z]+)".*/\1/')"

  case "$planted$surfaced" in *[!0-9]*|"") echo "$fid: unparseable judge output: $line"; fail_count=$((fail_count + 1)); continue ;; esac

  total_planted=$((total_planted + planted))
  total_surfaced=$((total_surfaced + surfaced))
  if [ "$shadow" = "true" ]; then
    shadow_planted=$((shadow_planted + planted));       shadow_surfaced=$((shadow_surfaced + surfaced))
  else
    nonshadow_planted=$((nonshadow_planted + planted)); nonshadow_surfaced=$((nonshadow_surfaced + surfaced))
  fi
  [ "$verdict" = "PASS" ] || fail_count=$((fail_count + 1))

  cov="n/a"
  [ "$planted" -gt 0 ] && cov="$(awk "BEGIN{printf \"%.2f\", $surfaced/$planted}")"
  results="${results}${fid}\t${tier}\t${cov}\t${verdict}\n"
done

echo
printf 'fixture\ttier\tcoverage\tverdict\n'
printf '%b' "$results"
echo

catch_rate="0.00"
[ "$total_planted" -gt 0 ] && catch_rate="$(awk "BEGIN{printf \"%.2f\", $total_surfaced/$total_planted}")"
shadow_rate="n/a"
[ "$shadow_planted" -gt 0 ] && shadow_rate="$(awk "BEGIN{printf \"%.2f\", $shadow_surfaced/$shadow_planted}")"
nonshadow_rate="n/a"
[ "$nonshadow_planted" -gt 0 ] && nonshadow_rate="$(awk "BEGIN{printf \"%.2f\", $nonshadow_surfaced/$nonshadow_planted}")"
echo "catch-rate (all):        $catch_rate  (gate >= $GATE_CATCH_RATE)"
echo "catch-rate (shadow):     $shadow_rate  (the trustworthy number — see README 'shadow subset')"
echo "catch-rate (non-shadow): $nonshadow_rate"
echo "fixture failures: $fail_count"

pass="$(awk "BEGIN{print ($catch_rate >= $GATE_CATCH_RATE) ? 1 : 0}")"

# Shadow-subset gate. A high all-fixtures rate driven only by non-shadow (author-written)
# fixtures is not trustworthy: the skill can be tuned to pass fixtures written alongside
# it. If any shadow fixtures exist, they must ALSO clear the gate. If none exist, the gate
# is provisional — warn loudly (this is the seed-set state, README "Discipline").
shadow_pass=1
if [ "$shadow_planted" -gt 0 ]; then
  shadow_pass="$(awk "BEGIN{print ($shadow_rate >= $GATE_CATCH_RATE) ? 1 : 0}")"
else
  echo "WARNING: no shadow fixtures present — gate is PROVISIONAL (README 'shadow subset')."
fi

if [ "$pass" -eq 1 ] && [ "$shadow_pass" -eq 1 ] && [ "$fail_count" -eq 0 ]; then
  echo "RESULT: PASS"
else
  echo "RESULT: FAIL"
  exit 1
fi
