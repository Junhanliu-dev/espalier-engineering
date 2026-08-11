#!/usr/bin/env bash
# Run eval harness runner (mirrors eval/map/run.sh mechanics).
# Runs the espalier-maprun skill (ONE master pass) against each fixture, scores
# the transcript with an LLM judge against rubric.md, and gates on the
# aggregate catch-rate plus the per-fixture pass bar. Verdicts are DERIVED
# from the judge's dimension fields — the judge's own verdict string is only
# ever a warning signal (same rationale as the grill harness).
#
# Dev/QA infra — NOT shipped to target projects.
# Bash 3.2 compatible (macOS); no GNU-only tools; sed uses -E for BSD.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
FIXTURES="$HERE/fixtures"
RUBRIC="$HERE/rubric.md"
SKILL="$HERE/../../skills/espalier-init/templates/skills/espalier-maprun.md"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

GATE_CATCH_RATE="0.80"
GATE_COVERAGE="0.8"
CLAUDE_RETRIES="${CLAUDE_RETRIES:-3}"
# Pinned: a user whose default model routes through stricter safeguards (e.g.
# Fable) gets hard API refusals on the harness's autonomous-worker prompts.
export MAPRUN_NO_DASHBOARD=1   # dispatch must not pop TUI windows inside evals
EVAL_MODEL="${EVAL_MODEL:-opus}"

[ -f "$SKILL" ]    || { echo "ERROR: espalier-maprun skill not found at $SKILL"; exit 2; }
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
results=""   # "fixture_id\tcoverage\tverdict\tjudge_said\n"

is_num() {
  awk -v v="$1" 'BEGIN{ exit !(v ~ /^[0-9]+(\.[0-9]+)?$/) }'
}

derive_verdict() {
  # $1=planted $2=surfaced $3=contracts_ok(true|false) $4=behavior_correct
  # Applies rubric.md "Per-fixture pass". Prints PASS or FAIL.
  local planted="$1" surfaced="$2" contracts="$3" behavior="$4"
  [ "$contracts" = "true" ] || { echo "FAIL"; return; }
  if [ "$planted" -eq 0 ]; then
    [ "$behavior" = "true" ] && { echo "PASS"; return; }
    echo "FAIL"; return
  fi
  awk "BEGIN{ print ($surfaced / $planted >= $GATE_COVERAGE) ? \"PASS\" : \"FAIL\" }"
}

run_claude() {
  # Retries claude -p; empty output / non-zero exit = infra hiccup, never a score.
  local prompt="$1" attempt=1 out
  while [ "$attempt" -le "$CLAUDE_RETRIES" ]; do
    if out="$(claude -p --model "$EVAL_MODEL" --output-format text "$prompt" 2>/dev/null)" && [ -n "$out" ]; then
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

run_master() {
  # $1 = fixture file. Prints the master-pass transcript; non-zero = infra failure.
  local fixture="$1"
  run_claude "You are running the espalier-maprun skill in EVAL MODE: execute exactly ONE
master pass against a simulated repo, then stop.

EVAL MODE rules:
- There is no filesystem, no git, no processes, and no AskUserQuestion tool. STATE every
  command you would run, verbatim, in the transcript instead — then take its output from
  the fixture's '## MOCK REPO STATE' command script: find the entry whose 'command:'
  matches what you would run and use its 'output:' (and 'exit:' code) as the result. If
  NO entry matches, say so and proceed conservatively — NEVER invent command output, and
  NEVER assume an unlisted command succeeded.
- The fixture's answer_script is the human. When you would ask the user, find the
  matching asks_about entry and use its reply. If NO entry matches your question, the
  human is unavailable for it: record it as an Open Question with a named conservative
  default — NEVER invent the user's answer.
- File contents the pass needs (question files, requirements, record excerpts) appear as
  'file:' entries in the MOCK REPO STATE — same matching rule.
- Follow the run skill exactly — the pass order, the halt rules, the worker contract,
  the anti-patterns. One pass, then a report, then STOP.

Run skill definition:
$(cat "$SKILL")

Fixture (frontmatter: planted_hazards, expected_behavior, answer_script; body: MOCK REPO STATE):
$(cat "$fixture")

Execute the single master pass. Output the full transcript: every command + which MOCK
entry answered it, every question + which answer_script reply you used, every state
transition you would record, and the final report, in order."
}

judge() {
  local fixture="$1" transcript="$2"
  run_claude "You are the run eval JUDGE. Rubric:
$(cat "$RUBRIC")

Fixture:
$(cat "$fixture")

Master-pass transcript:
$(cat "$transcript")

Score the run per the rubric. planted = the fixture's planted_hazards count; surfaced
counts per rubric dimension 1 (an expected_handling ACTION shown in the transcript).
placement and typing do not apply to this lane — always report 0. contracts_ok is
dimension 2's boolean. behavior_correct judges expected_behavior when the fixture
carries one (report true when it carries none). Output ONE line of compact JSON only,
no prose, no code fence:
{\"planted\":N,\"surfaced\":N,\"placement\":0,\"typing\":0,\"contracts_ok\":true,\"behavior_correct\":true,\"verdict\":\"PASS|FAIL\"}"
}

for fixture in "$FIXTURES"/*.md; do
  [ -e "$fixture" ] || { echo "ERROR: no fixtures found"; exit 2; }
  fid="$(basename "$fixture" .md)"
  shadow="$(sed -n -E 's/^shadow:[[:space:]]*//p' "$fixture" | head -1)"

  if ! run_master "$fixture" > "$WORK/$fid.transcript"; then
    echo "$fid: master pass FAILED TO EXECUTE after $CLAUDE_RETRIES tries (infra, not scoring)"
    infra_fail_count=$((infra_fail_count + 1)); continue
  fi
  if ! line="$(judge "$fixture" "$WORK/$fid.transcript")"; then
    echo "$fid: judge FAILED TO EXECUTE after $CLAUDE_RETRIES tries (infra, not scoring)"
    infra_fail_count=$((infra_fail_count + 1)); continue
  fi

  line="$(json_extract "$line")"

  planted="$(printf '%s' "$line"   | sed -E 's/.*"planted":([0-9]+).*/\1/')"
  surfaced="$(printf '%s' "$line"  | sed -E 's/.*"surfaced":([0-9]+).*/\1/')"
  contracts="$(printf '%s' "$line" | sed -E 's/.*"contracts_ok":(true|false).*/\1/')"
  behavior="$(printf '%s' "$line"  | sed -E 's/.*"behavior_correct":(true|false).*/\1/')"
  judge_said="$(printf '%s' "$line" | sed -E 's/.*"verdict":"([A-Z_]+)".*/\1/')"

  if ! is_num "$planted" || ! is_num "$surfaced" \
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

  verdict="$(derive_verdict "$planted" "$surfaced" "$contracts" "$behavior")"
  [ "$verdict" = "PASS" ] || fail_count=$((fail_count + 1))

  if [ "$judge_said" != "$verdict" ]; then
    judge_verdict_mismatches=$((judge_verdict_mismatches + 1))
    echo "WARNING: $fid — judge self-reported $judge_said but the rubric-derived verdict is $verdict" >&2
    echo "         (dims: contracts_ok=$contracts behavior_correct=$behavior surfaced=$surfaced/$planted)" >&2
  fi

  cov="n/a"
  [ "$planted" -gt 0 ] && cov="$(awk "BEGIN{printf \"%.2f\", $surfaced/$planted}")"
  results="${results}${fid}\t${cov}\t${verdict}\t${judge_said}\n"
done

echo
printf 'fixture\tcoverage\tverdict\tjudge_said\n'
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

# Judge-validation state: a handscore.tsv with derived verdict rows means the
# validate-judge.sh generate→rollup→compare cycle has been completed at least once.
if [ -f "$HERE/judge-validation/handscore.tsv" ] \
   && awk -F'\t' '$2=="verdict" && ($3=="PASS" || $3=="FAIL") {found=1} END{exit !found}' \
        "$HERE/judge-validation/handscore.tsv"; then
  echo "NOTE: judge validated against hand scores (eval/maprun/judge-validation/ —"
  echo "      see README 'Judge validation' for the run record and its caveats)."
else
  echo "NOTE: the run judge has NOT yet been validated against hand scores"
  echo "      (rubric.md 'Judge validation') — every result is PROVISIONAL until it is."
fi

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
