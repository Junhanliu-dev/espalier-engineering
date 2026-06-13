#!/usr/bin/env bash
# Ask eval harness runner.
# For each fixture: materialize a temp git repo from the fixture's FILE blocks,
# run the espalier-ask skill against it via `claude` headless, then score with
# (1) deterministic sidecar/behaviour assertions and (2) an LLM judge.
# Gates on the aggregate pass-rate (rubric.md).
#
# Dev/QA infra — NOT shipped to target projects.
# Bash 3.2 compatible (macOS); no GNU-only tools; sed uses -E for BSD.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
FIXTURES="$HERE/fixtures"
RUBRIC="$HERE/rubric.md"
SKILL="$HERE/../../skills/espalier-init/templates/skills/espalier-ask.md"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

GATE_PASS_RATE="0.80"

[ -f "$SKILL" ]    || { echo "ERROR: ask skill not found at $SKILL"; exit 2; }
[ -f "$RUBRIC" ]   || { echo "ERROR: rubric not found at $RUBRIC"; exit 2; }
[ -d "$FIXTURES" ] || { echo "ERROR: fixtures dir not found at $FIXTURES"; exit 2; }
command -v claude  >/dev/null 2>&1 || { echo "ERROR: 'claude' CLI not on PATH"; exit 2; }

# frontmatter_value FIELD FIXTURE — first matching scalar value, or "".
frontmatter_value() { sed -n -E "s/^$1:[[:space:]]*//p" "$2" | head -1; }

# materialize FIXTURE DEST — write every '=== FILE: <path> ===' block in the
# fixture body into DEST. The body is everything after the 2nd '---' fence.
materialize() {
  local fixture="$1" dest="$2"
  awk '/^---$/ { d++; next } d>=2 { print }' "$fixture" \
  | (
      cur=""
      while IFS= read -r line; do
        case "$line" in
          "=== FILE: "*" ===")
            cur="${line#=== FILE: }"; cur="${cur% ===}"
            mkdir -p "$dest/$(dirname "$cur")"
            : > "$dest/$cur"
            ;;
          *)
            [ -n "$cur" ] && printf '%s\n' "$line" >> "$dest/$cur"
            ;;
        esac
      done
    )
}

run_ask() {
  # $1 = repo dir, $2 = question. Prints the skill transcript.
  local repo="$1" question="$2"
  ( cd "$repo" && claude -p --output-format text \
"You are running the espalier-ask skill against THIS repository (the current
working directory). The user's question is:

  $question

Follow the skill definition below EXACTLY — classify, search the espalier/ docs
first, verify any doc claim against the cited code before asserting it, fall
back to a codebase search if the docs are silent, answer with sources, and
perform the skill's notify-only sidecar writes when warranted. Output your full
working: which docs you read, which code files you verified, the final answer,
and any drift-flag or gap-log line you surfaced.

Skill definition:
$(cat "$SKILL")" 2>/dev/null )
}

judge() {
  # $1 = fixture, $2 = transcript file, $3 = sidecar-state string. One JSON line.
  local fixture="$1" transcript="$2" sidecars="$3"
  claude -p --output-format text \
"You are the espalier-ask eval JUDGE. Rubric:
$(cat "$RUBRIC")

Fixture (frontmatter holds the answer key; body holds the repo files):
$(cat "$fixture")

Observed sidecar state after the run:
$sidecars

Skill transcript:
$(cat "$transcript")

Score Gate 2 only (run.sh already scored Gate 1). Output ONE line of compact
JSON, no prose:
{\"type_correct\":true,\"docs_first\":2,\"verified\":2,\"sourced\":2,\"trusts_code\":2,\"verdict\":\"PASS\"}" \
    2>/dev/null
}

total=0
passed=0
fail_count=0
crit_fail=0   # Gate-1 failures in drift/no-install (safety-critical buckets)
results=""    # "fixture_id\tbucket\tgate1\tgate2\tverdict\n"

for fixture in "$FIXTURES"/*.md; do
  [ -e "$fixture" ] || { echo "ERROR: no fixtures found"; exit 2; }
  fid="$(basename "$fixture" .md)"
  bucket="$(frontmatter_value bucket "$fixture")"
  question="$(frontmatter_value question "$fixture")"
  total=$((total + 1))

  repo="$WORK/$fid"
  mkdir -p "$repo"
  materialize "$fixture" "$repo"
  ( cd "$repo" && git init -q && git add -A \
      && git -c user.email=eval@espalier -c user.name=eval commit -qm init ) >/dev/null 2>&1

  if ! run_ask "$repo" "$question" > "$WORK/$fid.transcript" 2>/dev/null; then
    echo "$fid: skill run failed"
    results="${results}${fid}\t${bucket}\tERR\t-\tFAIL\n"
    fail_count=$((fail_count + 1)); continue
  fi

  # --- Gate 1: deterministic side-effect assertions ------------------------
  drift_tsv="$repo/espalier/.drift-state.tsv"
  gap_tsv="$repo/espalier/.ask-gaps.tsv"
  gate1="PASS"; gate1_why=""

  has_drift=no
  [ -f "$drift_tsv" ] && grep -q "ask-verify:" "$drift_tsv" 2>/dev/null && has_drift=yes
  has_gap=no
  [ -f "$gap_tsv" ] && [ -s "$gap_tsv" ] && has_gap=yes

  case "$bucket" in
    drift)
      [ "$has_drift" = yes ] || { gate1="FAIL"; gate1_why="expected drift flag with ask-verify: reason"; }
      ;;
    gap)
      [ "$has_gap" = yes ] || { gate1="FAIL"; gate1_why="expected a .ask-gaps.tsv row"; }
      ;;
    no-install)
      if [ -d "$repo/espalier" ]; then gate1="FAIL"; gate1_why="created espalier/ in a non-install repo"; fi
      ;;
    classify|docs-first)
      [ "$has_drift" = no ] || { gate1="FAIL"; gate1_why="unexpected drift flag"; }
      [ "$has_gap" = no ]   || { gate1="FAIL"; gate1_why="unexpected gap row"; }
      ;;
  esac

  if [ "$gate1" = "FAIL" ]; then
    echo "$fid: Gate 1 FAIL — $gate1_why"
    case "$bucket" in drift|no-install) crit_fail=$((crit_fail + 1)) ;; esac
    results="${results}${fid}\t${bucket}\tFAIL\t-\tFAIL\n"
    fail_count=$((fail_count + 1)); continue
  fi

  # --- Gate 2: LLM judge on answer quality ---------------------------------
  sidecars="drift_flag=${has_drift}; gap_row=${has_gap}; espalier_dir=$([ -d "$repo/espalier" ] && echo present || echo absent)"
  if ! line="$(judge "$fixture" "$WORK/$fid.transcript" "$sidecars")"; then
    echo "$fid: judge failed"
    results="${results}${fid}\t${bucket}\tPASS\tERR\tFAIL\n"
    fail_count=$((fail_count + 1)); continue
  fi
  verdict="$(printf '%s' "$line" | sed -E 's/.*"verdict":"([A-Z]+)".*/\1/')"

  if [ "$verdict" = "PASS" ]; then
    passed=$((passed + 1))
    results="${results}${fid}\t${bucket}\tPASS\tPASS\tPASS\n"
  else
    results="${results}${fid}\t${bucket}\tPASS\tFAIL\tFAIL\n"
    fail_count=$((fail_count + 1))
  fi
done

echo
printf 'fixture\tbucket\tgate1\tgate2\tverdict\n'
printf '%b' "$results"
echo

pass_rate="0.00"
[ "$total" -gt 0 ] && pass_rate="$(awk "BEGIN{printf \"%.2f\", $passed/$total}")"
echo "pass-rate: $pass_rate  (gate >= $GATE_PASS_RATE)"
echo "fixtures: $total   passed: $passed   failed: $fail_count   critical-bucket gate1 failures: $crit_fail"

ok="$(awk "BEGIN{print ($pass_rate >= $GATE_PASS_RATE) ? 1 : 0}")"
if [ "$ok" -eq 1 ] && [ "$crit_fail" -eq 0 ]; then
  echo "RESULT: PASS"
else
  echo "RESULT: FAIL"
  exit 1
fi
