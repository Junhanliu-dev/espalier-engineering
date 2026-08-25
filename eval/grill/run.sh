#!/usr/bin/env bash
# Grill eval harness runner.
# Runs the espalier-grill skill against each golden fixture, scores the result with
# an LLM judge, and gates on the aggregate catch-rate (plan section 9) plus the
# per-fixture pass bar (rubric.md "Per-fixture pass").
#
# The judge also self-reports a "verdict" field. We do NOT gate on it: validate-judge.sh
# only ever validated the four dimension scores, so the verdict was the one field the
# gate read and nothing checked. We derive the verdict from the dimensions instead, and
# use the judge's claim only to warn when it misapplies its own rubric.
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

# KNOWN-ISSUES #1: an infra hiccup (rate-limit, transient API error) must not read as a
# scoring regression. Retry each claude -p call a bounded number of times; a fixture that
# still cannot execute is counted as an INFRA failure (distinct exit code 3), never folded
# into the scoring gate.
CLAUDE_RETRIES="${CLAUDE_RETRIES:-3}"

# Per-fixture pass bar — rubric.md "Per-fixture pass". Keep these in sync with the rubric.
GATE_COVERAGE="0.8"
GATE_NON_OBVIOUS="1.3"
GATE_DISCRIMINATION="1.3"

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
infra_fail_count=0
judge_verdict_mismatches=0
results=""   # accumulated: "fixture_id\ttier\tcoverage\tverdict\tjudge_said\n"

is_num() {
  # 0 if $1 is a bare non-negative integer or decimal ("2", "1.3", "0.0"); 1 otherwise.
  # sed prints the input unchanged when its pattern does not match, so every extracted
  # field must pass through here before it is trusted.
  awk -v v="$1" 'BEGIN{ exit !(v ~ /^[0-9]+(\.[0-9]+)?$/) }'
}

derive_verdict() {
  # $1=planted $2=surfaced $3=depth_cal $4=non_obvious $5=discrimination $6=coverage_only
  # Applies rubric.md "Per-fixture pass". Prints PASS or FAIL.
  local planted="$1" surfaced="$2" depth="$3" nonobv="$4" disc="$5" covonly="${6:-false}"

  # `skip` fixtures plant nothing and ask nothing; coverage is vacuously 1.0 and the
  # per-question dimensions are 0.0 by definition (rubric.md "skip fixtures pass ...").
  # depth_cal == 2 is what encodes "chose skip": grilling a skip fixture scores 0.
  if [ "$planted" -eq 0 ]; then
    [ "$depth" -eq 2 ] && { echo "PASS"; return; }
    echo "FAIL"; return
  fi

  # Coverage-only fixtures gate on coverage + depth alone — the non-obviousness and
  # discrimination bars do not apply (rubric.md "Coverage-only fixtures").
  if [ "$covonly" = "true" ]; then
    awk "BEGIN{ print (($surfaced / $planted >= $GATE_COVERAGE) && ($depth == 2)) ? \"PASS\" : \"FAIL\" }"
    return
  fi

  awk "BEGIN{
    cov = $surfaced / $planted
    ok = (cov >= $GATE_COVERAGE) && ($depth == 2) \
      && ($nonobv >= $GATE_NON_OBVIOUS) && ($disc >= $GATE_DISCRIMINATION)
    print ok ? \"PASS\" : \"FAIL\"
  }"
}

run_claude() {
  # $1 = full prompt. Retries claude -p up to CLAUDE_RETRIES times on non-zero exit or
  # empty output (both are how an infra hiccup shows up). Prints stdout on success;
  # returns non-zero when every attempt failed — an INFRA failure, NOT a scoring failure.
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
  # KNOWN-ISSUES #2: the judge sometimes wraps its one-line JSON in a ```json fence or adds
  # prose. Collapse newlines and keep only the first '{' through the last '}', so the sed
  # field extractors see bare compact JSON regardless of fencing.
  printf '%s' "$1" | tr '\n' ' ' | sed -E 's/^[^{]*//; s/[^}]*$//'
}

run_grill() {
  # $1 = fixture file. Prints the grill transcript to stdout; non-zero exit = infra failure.
  local fixture="$1"
  run_claude "You are running the espalier-grill skill in EVAL MODE.

EVAL MODE rules:
- Skip Step 0's TTY check — the fixture's answer_script is your interactive channel. Use it
  to answer your own grill questions; never ask a real human.
- Step 1.5 reads espalier/rules/ and espalier/wiki/. In eval there is no such directory on
  disk; if the fixture body contains a '## MOCK CONTEXT' block, treat the files listed there
  as the ENTIRE contents of espalier/rules/ and espalier/wiki/ (read only those). If the
  fixture has no '## MOCK CONTEXT' block, treat both directories as absent and skip Step 1.5
  silently, exactly as the skill says.
- The 'git rev-parse HEAD' / mark_stale drift-flag call in Step 1.5 cannot run in eval; when
  Step 1.5 would flag a doc stale, STATE that in the transcript instead of running it.
- Otherwise follow the skill exactly.

Skill definition:
$(cat "$SKILL")

Fixture (frontmatter holds the answer_script; body may hold a '## MOCK CONTEXT' block):
$(cat "$fixture")

Run the grill. Output the full transcript: the tier you chose, every question asked, which
answer_script reply you used for each, and — if any planted_collisions applied — the
rules/wiki citation you gave for each collision surfaced."
}

judge() {
  # $1 = fixture file, $2 = transcript file. Prints one compact JSON line; non-zero = infra.
  local fixture="$1" transcript="$2"
  run_claude "You are the grill eval JUDGE. Rubric:
$(cat "$RUBRIC")

Fixture:
$(cat "$fixture")

Grill transcript:
$(cat "$transcript")

Score the run. If the fixture carries planted_collisions, count them into planted/surfaced
exactly like planted_ambiguities (rubric dimension 6 — a collision counts as surfaced only
if grill named it AND cited the rules/wiki file). Output ONE line of compact JSON only, no
prose, no code fence:
{\"planted\":N,\"surfaced\":N,\"depth_cal\":0-2,\"non_obvious\":0.0-2.0,\"discrimination\":0.0-2.0,\"verdict\":\"PASS|FAIL\"}"
}

for fixture in "$FIXTURES"/*.md; do
  [ -e "$fixture" ] || { echo "ERROR: no fixtures found"; exit 2; }
  fid="$(basename "$fixture" .md)"
  tier="$(sed -n -E 's/^expected_tier:[[:space:]]*//p' "$fixture" | head -1)"
  shadow="$(sed -n -E 's/^shadow:[[:space:]]*//p' "$fixture" | head -1)"
  covonly="$(sed -n -E 's/^coverage_only:[[:space:]]*//p' "$fixture" | head -1)"
  [ "$covonly" = "true" ] || covonly="false"

  if ! run_grill "$fixture" > "$WORK/$fid.transcript"; then
    echo "$fid: grill run FAILED TO EXECUTE after $CLAUDE_RETRIES tries (infra, not scoring)"
    infra_fail_count=$((infra_fail_count + 1)); continue
  fi
  if ! line="$(judge "$fixture" "$WORK/$fid.transcript")"; then
    echo "$fid: judge FAILED TO EXECUTE after $CLAUDE_RETRIES tries (infra, not scoring)"
    infra_fail_count=$((infra_fail_count + 1)); continue
  fi
  # Take the LAST JSON-object line — a prose preamble must not fail the fixture.
  line="$(printf '%s\n' "$line" | grep -E '^\{.*\}[[:space:]]*$' | tail -1)"

  # KNOWN-ISSUES #2: normalise fenced/prose-wrapped judge output to bare JSON before parsing.
  line="$(json_extract "$line")"

  planted="$(printf '%s' "$line"  | sed -E 's/.*"planted":([0-9]+).*/\1/')"
  surfaced="$(printf '%s' "$line" | sed -E 's/.*"surfaced":([0-9]+).*/\1/')"
  depth="$(printf '%s' "$line"    | sed -E 's/.*"depth_cal":([0-9]+).*/\1/')"
  nonobv="$(printf '%s' "$line"   | sed -E 's/.*"non_obvious":([0-9.]+).*/\1/')"
  disc="$(printf '%s' "$line"     | sed -E 's/.*"discrimination":([0-9.]+).*/\1/')"
  judge_said="$(printf '%s' "$line" | sed -E 's/.*"verdict":"([A-Z_]+)".*/\1/')"

  if ! is_num "$planted" || ! is_num "$surfaced" || ! is_num "$depth" \
     || ! is_num "$nonobv" || ! is_num "$disc"; then
    echo "$fid: unparseable judge output: $line"; fail_count=$((fail_count + 1)); continue
  fi

  total_planted=$((total_planted + planted))
  total_surfaced=$((total_surfaced + surfaced))
  if [ "$shadow" = "true" ]; then
    shadow_planted=$((shadow_planted + planted));       shadow_surfaced=$((shadow_surfaced + surfaced))
  else
    nonshadow_planted=$((nonshadow_planted + planted)); nonshadow_surfaced=$((nonshadow_surfaced + surfaced))
  fi

  # Derive the verdict from the dimensions. Never trust the judge's own verdict string:
  # it is the field the gate reads and the field validate-judge.sh never checked.
  verdict="$(derive_verdict "$planted" "$surfaced" "$depth" "$nonobv" "$disc" "$covonly")"
  [ "$verdict" = "PASS" ] || fail_count=$((fail_count + 1))

  if [ "$judge_said" != "$verdict" ]; then
    judge_verdict_mismatches=$((judge_verdict_mismatches + 1))
    echo "WARNING: $fid — judge self-reported $judge_said but the rubric-derived verdict is $verdict" >&2
    echo "         (dims: depth_cal=$depth non_obvious=$nonobv discrimination=$disc)" >&2
  fi

  cov="n/a"
  [ "$planted" -gt 0 ] && cov="$(awk "BEGIN{printf \"%.2f\", $surfaced/$planted}")"
  results="${results}${fid}\t${tier}\t${cov}\t${verdict}\t${judge_said}\n"
done

echo
printf 'fixture\ttier\tcoverage\tverdict\tjudge_said\n'
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
  echo "         verdict on $judge_verdict_mismatches fixture(s). The judge is misapplying its own pass bar."
  echo "         Sharpen the rubric anchors (rubric.md 'Judge validation' step 4) and re-validate."
fi

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

# Exit codes are distinct so a caller can tell the three outcomes apart (KNOWN-ISSUES #1):
#   0 — PASS        scoring gate cleared, every fixture executed
#   1 — FAIL        a real scoring regression (catch-rate / shadow / per-fixture bar)
#   3 — INCONCLUSIVE at least one fixture could not execute (infra); scoring not trustworthy
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
