#!/usr/bin/env bash
# Map eval harness runner (mirrors eval/grill/run.sh mechanics).
# Runs the espalier-map skill against each fixture, scores the transcript with
# an LLM judge against rubric.md, and gates on the aggregate catch-rate plus
# the per-fixture pass bar. Verdicts are DERIVED from the judge's dimension
# fields — the judge's own verdict string is only ever a warning signal
# (same rationale as the grill harness).
#
# Dev/QA infra — NOT shipped to target projects.
# Bash 3.2 compatible (macOS); no GNU-only tools; sed uses -E for BSD.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
FIXTURES="$HERE/fixtures"
RUBRIC="$HERE/rubric.md"
SKILL="$HERE/../../skills/espalier-init/templates/skills/espalier-map.md"
GRILL_SKILL="$HERE/../../skills/espalier-init/templates/skills/espalier-grill.md"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

GATE_CATCH_RATE="0.80"
GATE_COVERAGE="0.8"
CLAUDE_RETRIES="${CLAUDE_RETRIES:-3}"

[ -f "$SKILL" ]       || { echo "ERROR: espalier-map skill not found at $SKILL"; exit 2; }
[ -f "$GRILL_SKILL" ] || { echo "ERROR: espalier-grill skill not found at $GRILL_SKILL"; exit 2; }
[ -f "$RUBRIC" ]      || { echo "ERROR: rubric not found at $RUBRIC"; exit 2; }
[ -d "$FIXTURES" ]    || { echo "ERROR: fixtures dir not found at $FIXTURES"; exit 2; }

total_planted=0
total_surfaced=0
shadow_planted=0
shadow_surfaced=0
nonshadow_planted=0
nonshadow_surfaced=0
fail_count=0
infra_fail_count=0
judge_verdict_mismatches=0
results=""   # "fixture_id\tmode\tcoverage\tverdict\tjudge_said\n"

is_num() {
  awk -v v="$1" 'BEGIN{ exit !(v ~ /^[0-9]+(\.[0-9]+)?$/) }'
}

derive_verdict() {
  # $1=planted $2=surfaced $3=placement $4=typing $5=contracts_ok(true|false)
  # $6=behavior_correct(true|false|n/a) $7=coverage_only(true|false)
  # Applies rubric.md "Per-fixture pass". Prints PASS or FAIL.
  local planted="$1" surfaced="$2" placement="$3" typing="$4"
  local contracts="$5" behavior="$6" covonly="${7:-false}"

  # The contract bar is hard on EVERY family.
  [ "$contracts" = "true" ] || { echo "FAIL"; return; }

  # Behavior fixtures plant nothing: behavior_correct decides.
  if [ "$planted" -eq 0 ]; then
    [ "$behavior" = "true" ] && { echo "PASS"; return; }
    echo "FAIL"; return
  fi

  if [ "$covonly" = "true" ]; then
    awk "BEGIN{ print ($surfaced / $planted >= $GATE_COVERAGE) ? \"PASS\" : \"FAIL\" }"
    return
  fi

  awk "BEGIN{
    cov = $surfaced / $planted
    ok = (cov >= $GATE_COVERAGE) && ($placement >= 1) && ($typing >= 1)
    print ok ? \"PASS\" : \"FAIL\"
  }"
}

run_claude() {
  # Retries claude -p; empty output / non-zero exit = infra hiccup, never a score.
  local prompt="$1" attempt=1 out
  while [ "$attempt" -le "$CLAUDE_RETRIES" ]; do
    if out="$(claude -p --output-format text "$prompt" 2>/dev/null)" && [ -n "$out" ]; then
      printf '%s' "$out"
      return 0
    fi
    attempt=$((attempt + 1))
    [ "$attempt" -le "$CLAUDE_RETRIES" ] && sleep $((attempt * 3))
  done
  return 1
}

json_extract() {
  printf '%s' "$1" | tr '\n' ' ' | sed -E 's/^[^{]*//; s/[^}]*$//'
}

run_map() {
  # $1 = fixture file. Prints the map transcript; non-zero exit = infra failure.
  local fixture="$1"
  run_claude "You are running the espalier-map skill in EVAL MODE.

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
- Otherwise follow the map skill exactly — including plan-don't-do, one non-research
  ticket per work session, fog graduation, and stopping when the session's work is done.

Map skill definition:
$(cat "$SKILL")

Grill skill definition (for mode=decision):
$(cat "$GRILL_SKILL")

Fixture (frontmatter: mode, target_ticket, answer_script; body: the idea and any MOCK blocks):
$(cat "$fixture")

Run the session the fixture's mode calls for (chart, or work on target_ticket). Output the
full transcript: every question + which answer_script reply you used, every artifact you
would write (map.md, tickets) in full, and every action you would take, in order."
}

judge() {
  local fixture="$1" transcript="$2"
  run_claude "You are the map eval JUDGE. Rubric:
$(cat "$RUBRIC")

Fixture:
$(cat "$fixture")

Map transcript:
$(cat "$transcript")

Score the run per the rubric. planted = the fixture's planted_decisions count plus
planted_collisions count; surfaced counts per rubric dimensions 1 and 6 (a collision
surfaces only WITH its citation; apply the false-collision penalty). placement and typing
are 0-2 per dimensions 2-3 (report 0 when planted is 0). contracts_ok is dimension 4's
boolean. behavior_correct judges expected_behavior when the fixture carries one (report
true when it carries none). Output ONE line of compact JSON only, no prose, no code fence:
{\"planted\":N,\"surfaced\":N,\"placement\":0-2,\"typing\":0-2,\"contracts_ok\":true,\"behavior_correct\":true,\"verdict\":\"PASS|FAIL\"}"
}

for fixture in "$FIXTURES"/*.md; do
  [ -e "$fixture" ] || { echo "ERROR: no fixtures found"; exit 2; }
  fid="$(basename "$fixture" .md)"
  mode="$(sed -n -E 's/^mode:[[:space:]]*//p' "$fixture" | head -1)"
  shadow="$(sed -n -E 's/^shadow:[[:space:]]*//p' "$fixture" | head -1)"
  covonly="$(sed -n -E 's/^coverage_only:[[:space:]]*//p' "$fixture" | head -1)"
  [ "$covonly" = "true" ] || covonly="false"

  if ! run_map "$fixture" > "$WORK/$fid.transcript"; then
    echo "$fid: map run FAILED TO EXECUTE after $CLAUDE_RETRIES tries (infra, not scoring)"
    infra_fail_count=$((infra_fail_count + 1)); continue
  fi
  if ! line="$(judge "$fixture" "$WORK/$fid.transcript")"; then
    echo "$fid: judge FAILED TO EXECUTE after $CLAUDE_RETRIES tries (infra, not scoring)"
    infra_fail_count=$((infra_fail_count + 1)); continue
  fi

  line="$(json_extract "$line")"

  planted="$(printf '%s' "$line"   | sed -E 's/.*"planted":([0-9]+).*/\1/')"
  surfaced="$(printf '%s' "$line"  | sed -E 's/.*"surfaced":([0-9]+).*/\1/')"
  placement="$(printf '%s' "$line" | sed -E 's/.*"placement":([0-9]+).*/\1/')"
  typing="$(printf '%s' "$line"    | sed -E 's/.*"typing":([0-9]+).*/\1/')"
  contracts="$(printf '%s' "$line" | sed -E 's/.*"contracts_ok":(true|false).*/\1/')"
  behavior="$(printf '%s' "$line"  | sed -E 's/.*"behavior_correct":(true|false).*/\1/')"
  judge_said="$(printf '%s' "$line" | sed -E 's/.*"verdict":"([A-Z_]+)".*/\1/')"

  if ! is_num "$planted" || ! is_num "$surfaced" || ! is_num "$placement" || ! is_num "$typing" \
     || { [ "$contracts" != "true" ] && [ "$contracts" != "false" ]; } \
     || { [ "$behavior" != "true" ] && [ "$behavior" != "false" ]; }; then
    echo "$fid: unparseable judge output: $line"; fail_count=$((fail_count + 1)); continue
  fi

  total_planted=$((total_planted + planted))
  total_surfaced=$((total_surfaced + surfaced))
  if [ "$shadow" = "true" ]; then
    shadow_planted=$((shadow_planted + planted));       shadow_surfaced=$((shadow_surfaced + surfaced))
  else
    nonshadow_planted=$((nonshadow_planted + planted)); nonshadow_surfaced=$((nonshadow_surfaced + surfaced))
  fi

  verdict="$(derive_verdict "$planted" "$surfaced" "$placement" "$typing" "$contracts" "$behavior" "$covonly")"
  [ "$verdict" = "PASS" ] || fail_count=$((fail_count + 1))

  if [ "$judge_said" != "$verdict" ]; then
    judge_verdict_mismatches=$((judge_verdict_mismatches + 1))
    echo "WARNING: $fid — judge self-reported $judge_said but the rubric-derived verdict is $verdict" >&2
    echo "         (dims: placement=$placement typing=$typing contracts_ok=$contracts behavior_correct=$behavior)" >&2
  fi

  cov="n/a"
  [ "$planted" -gt 0 ] && cov="$(awk "BEGIN{printf \"%.2f\", $surfaced/$planted}")"
  results="${results}${fid}\t${mode}\t${cov}\t${verdict}\t${judge_said}\n"
done

echo
printf 'fixture\tmode\tcoverage\tverdict\tjudge_said\n'
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
echo "fixture failures: $fail_count  (verdict derived from rubric.md 'Per-fixture pass')"
echo "infra failures:   $infra_fail_count  (could not execute after $CLAUDE_RETRIES tries — NOT scored)"

if [ "$judge_verdict_mismatches" -gt 0 ]; then
  echo "WARNING: the judge's self-reported verdict disagreed with the rubric-derived"
  echo "         verdict on $judge_verdict_mismatches fixture(s). Sharpen the rubric anchors and re-validate."
fi

echo "NOTE: the map judge has NOT yet been validated against hand scores"
echo "      (rubric.md 'Judge validation') — every result is PROVISIONAL until it is."

pass="$(awk "BEGIN{print ($catch_rate >= $GATE_CATCH_RATE) ? 1 : 0}")"

shadow_pass=1
if [ "$shadow_planted" -gt 0 ]; then
  shadow_pass="$(awk "BEGIN{print ($shadow_rate >= $GATE_CATCH_RATE) ? 1 : 0}")"
else
  echo "WARNING: no shadow fixtures present — gate is PROVISIONAL (README 'shadow subset')."
fi

#   0 — PASS   1 — FAIL (real scoring regression)   3 — INCONCLUSIVE (infra)
if [ "$pass" -eq 1 ] && [ "$shadow_pass" -eq 1 ] && [ "$fail_count" -eq 0 ]; then
  if [ "$infra_fail_count" -eq 0 ]; then
    echo "RESULT: PASS"
  else
    echo "RESULT: INCONCLUSIVE — scoring gate cleared over the fixtures that ran, but"
    echo "        $infra_fail_count fixture(s) never executed (infra). Re-run before trusting a PASS."
    exit 3
  fi
else
  echo "RESULT: FAIL"
  exit 1
fi
