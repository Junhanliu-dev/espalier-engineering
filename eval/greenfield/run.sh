#!/usr/bin/env bash
# Greenfield interview eval runner.
# Plays each fixture's answer_script against the greenfield flow (EVAL MODE,
# dry-run — no scaffolder is ever executed), LLM-judges the transcript
# against rubric.md, gates on aggregate results.
#
# Dev/QA infra — NOT shipped to target projects.
# Bash 3.2 compatible (macOS); no GNU-only tools; sed uses -E for BSD.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
FIXTURES="$HERE/fixtures"
RUBRIC="$HERE/rubric.md"
FLOW="$HERE/../../skills/espalier-init/references/greenfield.md"
TRACKS_DIR="$HERE/../../skills/espalier-init/references/greenfield"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

[ -f "$FLOW" ]     || { echo "ERROR: greenfield flow not found at $FLOW"; exit 2; }
[ -f "$RUBRIC" ]   || { echo "ERROR: rubric not found at $RUBRIC"; exit 2; }
[ -d "$FIXTURES" ] || { echo "ERROR: fixtures dir not found at $FIXTURES"; exit 2; }

fail_count=0
results=""   # "fixture_id\ttrack\trounds\tverdict\n"

run_flow() {
  # $1 = fixture file. Prints the interview transcript to stdout.
  local fixture="$1" expected_track track_file track_content=""
  expected_track="$(sed -n -E 's/^expected_track:[[:space:]]*//p' "$fixture" | head -1)"
  track_file="$TRACKS_DIR/$expected_track.md"
  [ -f "$track_file" ] && track_content="$(cat "$track_file")"
  claude -p --output-format text \
"You are running the Espalier GREENFIELD FLOW in EVAL MODE.

EVAL MODE rules:
- DRY-RUN: never execute scaffolder/install/deploy commands — state what you
  WOULD run and move on. Treat the repo as bare and the session as a TTY.
- The fixture's answer_script is your interactive channel: when you would ask
  the user something, find the matching reply and use it. If no reply matches,
  apply your recommended default and say so. Never ask a real human.
- Stop after presenting the scaffold proposal and stating what you would do
  next (verification gate, guided-deploy offer). Do not simulate beyond that.
- Otherwise follow the flow exactly.

Greenfield flow definition:
$(cat "$FLOW")

Track file for the expected track (read it when the flow tells you to):
$track_content

Fixture (frontmatter holds the answer_script):
$(cat "$fixture")

Run the interview. Output the full transcript: every question asked (mark each
AskUserQuestion round), which reply or default you used, the resolved track,
the scaffold proposal, and every decision you would log to stack-decisions.md." \
    2>/dev/null
}

judge() {
  # $1 = fixture file, $2 = transcript file. Prints one compact JSON line.
  local fixture="$1" transcript="$2"
  claude -p --output-format text \
"You are the greenfield eval JUDGE. Rubric:
$(cat "$RUBRIC")

Fixture (answer key in frontmatter):
$(cat "$fixture")

Interview transcript:
$(cat "$transcript")

Score the run. Output ONE line of compact JSON only, no prose:
{\"track_ok\":true,\"rounds_used\":N,\"rounds_ok\":true,\"defaults\":N,\"expected_hit\":N,\"expected_total\":N,\"forbidden_hit\":N,\"verdict\":\"PASS|FAIL\"}" \
    2>/dev/null
}

for fixture in "$FIXTURES"/*.md; do
  [ -e "$fixture" ] || { echo "ERROR: no fixtures found"; exit 2; }
  fid="$(basename "$fixture" .md)"
  track="$(sed -n -E 's/^expected_track:[[:space:]]*//p' "$fixture" | head -1)"

  if ! run_flow "$fixture" > "$WORK/$fid.transcript"; then
    echo "$fid: flow run failed"; fail_count=$((fail_count + 1)); continue
  fi
  if ! line="$(judge "$fixture" "$WORK/$fid.transcript")"; then
    echo "$fid: judge failed"; fail_count=$((fail_count + 1)); continue
  fi

  rounds="$(printf '%s' "$line"  | sed -E 's/.*"rounds_used":([0-9]+).*/\1/')"
  verdict="$(printf '%s' "$line" | sed -E 's/.*"verdict":"([A-Z]+)".*/\1/')"
  case "$verdict" in PASS|FAIL) ;; *) echo "$fid: unparseable judge output: $line"; fail_count=$((fail_count + 1)); continue ;; esac

  [ "$verdict" = "PASS" ] || fail_count=$((fail_count + 1))
  results="${results}${fid}\t${track}\t${rounds}\t${verdict}\n"
done

echo
printf 'fixture\ttrack\trounds\tverdict\n'
printf '%b' "$results"
echo
echo "fixture failures: $fail_count"

if [ "$fail_count" -eq 0 ]; then
  echo "RESULT: PASS"
else
  echo "RESULT: FAIL"
  exit 1
fi
