#!/usr/bin/env bash
# Coder eval harness runner.
# Runs harness-coder against each task fixture in a throwaway git project, captures
# the diff of what it wrote, and scores conventions-followed / task-done / no-overscope
# with an LLM judge. GENERATIVE eval — gate is provisional (see README).
#
# Dev/QA infra — NOT shipped. Bash 3.2 compatible (macOS); sed uses -E for BSD.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
FIXTURES="$HERE/fixtures"
RUBRIC="$HERE/rubric.md"
PROJECT="$HERE/project"
TPL="$HERE/../../skills/espalier-init/templates"
CODER_TPL="$TPL/agents/harness-coder.md"
CODING_SKILL_TPL="$TPL/skills/espalier-coding.md"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

GATE_PASS_RATE="0.80"

# Optional $1: a fixture glob (e.g. 'coder-05*.md') for partial re-runs — the
# RESULT then covers only that subset; the release gate is the full run.
FIXTURE_GLOB="${1:-*.md}"
[ "$FIXTURE_GLOB" = "*.md" ] || echo "NOTE: partial run (glob=$FIXTURE_GLOB) — the release gate requires the full suite."

for f in "$CODER_TPL" "$CODING_SKILL_TPL" "$RUBRIC" \
         "$PROJECT/coding-standards.md" "$PROJECT/engineering-structure.md" "$PROJECT/reference/user-service.js"; do
  [ -f "$f" ] || { echo "ERROR: required file not found: $f"; exit 2; }
done
[ -d "$FIXTURES" ] || { echo "ERROR: fixtures dir not found at $FIXTURES"; exit 2; }

total=0; passed=0; overscope_total=0; overbuild_total=0; fail_count=0; results=""

setup_and_run() {
  local fixture="$1" fid="$2"
  local proj="$WORK/$fid"
  local target; target="$(sed -n -E 's/^target_file:[[:space:]]*//p' "$fixture" | head -1)"
  local folded; folded="$(sed -n -E 's/^folded:[[:space:]]*//p' "$fixture" | head -1)"
  local task; task="$(awk 'body{print} /^---[[:space:]]*$/{c++; if(c==2) body=1}' "$fixture")"
  local tests_clause=""
  if [ "$folded" = "true" ]; then
    tests_clause="
TESTS (folded test-mode duty): alongside the code, write the interface tests and failure-mode tests for this change, following the test conventions the TASK states. List the test files in their own '- Test files:' line of the coding report. Everything EXCEPT contracted abuse tests."
  fi
  mkdir -p "$proj/src/services" "$proj/src/controllers" "$proj/src/repositories" \
           "$proj/espalier/rules" "$proj/espalier/agents" "$proj/espalier/skills/espalier-coding" \
           "$proj/espalier/changes/feat/eval"
  cp "$PROJECT/coding-standards.md"       "$proj/espalier/rules/coding-standards.md"
  cp "$PROJECT/engineering-structure.md"  "$proj/espalier/rules/engineering-structure.md"
  cp "$PROJECT/reference/user-service.js" "$proj/src/services/user-service.js"
  printf 'module.exports = { info() {}, error() {} };\n' > "$proj/src/logger.js"
  sed -e 's/{project_name}/CoderApp/g' -e 's/{project}/CoderApp/g' "$CODER_TPL" > "$proj/espalier/agents/harness-coder.md"
  sed -e 's/{project_name}/CoderApp/g' -e 's/{project}/CoderApp/g' "$CODING_SKILL_TPL" > "$proj/espalier/skills/espalier-coding/SKILL.md"

  ( cd "$proj" && git init -q && git add -A && git -c user.email=e@e.co -c user.name=eval commit -qm baseline ) >/dev/null 2>&1

  claude -p --dangerously-skip-permissions --output-format text \
"You are the harness-coder for CoderApp. The project root is $proj; EVERY espalier/ path is relative to that root.

Read $proj/espalier/agents/harness-coder.md and follow it EXACTLY, plus $proj/espalier/skills/espalier-coding/SKILL.md and the rules under $proj/espalier/rules/. Mirror the reference pattern in $proj/src/services/user-service.js. Honor the coder's core rule: ONE task at a time — do NOT expand scope.

TASK: $task
$tests_clause
Implement it (primary file: $proj/$target). Write your coding-report to $proj/espalier/changes/feat/eval/coding-report.md." >/dev/null 2>&1 || return 1
}

judge() {
  local fixture="$1" diff="$2" report="$3"
  claude -p --output-format text \
"You are the coder eval JUDGE. Score objectively against the rubric. Rubric:
$(cat "$RUBRIC")

Fixture (frontmatter is the answer key — target_file, must_follow, must_not):
$(cat "$fixture")

Git diff of what the coder wrote:
$(cat "$diff")

Coder's coding-report:
$(cat "$report" 2>/dev/null || echo '(none)')

Output ONE line of compact JSON only, no prose:
{\"followed\":N,\"violated\":N,\"task_done\":0,\"overscope\":0,\"overbuild\":0,\"verdict\":\"PASS\"}

If (and only if) the fixture frontmatter has 'folded: true', ALSO include two
extra 0|1 fields in the same JSON object: \"tests_written\" (the diff adds at
least one test file for the change, listed in the report's '- Test files:'
line) and \"tests_meaningful\" (its assertions test the intended behaviour of
the changed interface — including at least one non-happy-path case — and are
not tautological). Test files written under a folded fixture are the coder's
DUTY: never count them as overscope or overbuild." \
    2>/dev/null
}

for fixture in "$FIXTURES"/$FIXTURE_GLOB; do
  [ -e "$fixture" ] || { echo "ERROR: no fixtures found"; exit 2; }
  fid="$(basename "$fixture" .md)"
  total=$((total + 1))

  if ! setup_and_run "$fixture" "$fid"; then
    echo "$fid: coder run failed"; fail_count=$((fail_count + 1)); continue
  fi
  proj="$WORK/$fid"
  diff_file="$WORK/$fid.diff"
  # src/ AND tests/ — folded fixtures write test files, and a diff that
  # excludes them would judge the tests duty unfulfilled regardless of output.
  ( cd "$proj" && git add -A && git diff --cached -- 'src/' 'tests/' ) > "$diff_file" 2>/dev/null || true
  report="$proj/espalier/changes/feat/eval/coding-report.md"

  if [ ! -s "$diff_file" ]; then
    echo "$fid: coder wrote no code"; fail_count=$((fail_count + 1)); results="${results}${fid}\t-\t-\tNO-CODE\tFAIL\n"; continue
  fi
  if ! line="$(judge "$fixture" "$diff_file" "$report")"; then
    echo "$fid: judge failed"; fail_count=$((fail_count + 1)); continue
  fi
  # A judge reply sometimes carries prose before the JSON — take the LAST
  # JSON-object line rather than failing the fixture on the preamble.
  line="$(printf '%s\n' "$line" | grep -E '^\{.*\}[[:space:]]*$' | tail -1)"

  violated="$(printf '%s' "$line" | sed -E 's/.*"violated":([0-9]+).*/\1/')"
  tdone="$(printf '%s'    "$line" | sed -E 's/.*"task_done":([01]).*/\1/')"
  oscope="$(printf '%s'   "$line" | sed -E 's/.*"overscope":([01]).*/\1/')"
  obuild="$(printf '%s'   "$line" | sed -E 's/.*"overbuild":([01]).*/\1/')"

  case "$violated$tdone$oscope$obuild" in *[!0-9]*|"") echo "$fid: unparseable judge output: $line"; fail_count=$((fail_count + 1)); continue ;; esac

  # Folded fixtures (v0.23): the coder also had the tests duty — gate on it.
  folded_fx="$(sed -n -E 's/^folded:[[:space:]]*//p' "$fixture" | head -1)"
  tests_ok=1
  tflag=""
  if [ "$folded_fx" = "true" ]; then
    tw="$(printf '%s' "$line" | sed -E 's/.*"tests_written":([01]).*/\1/')"
    tm="$(printf '%s' "$line" | sed -E 's/.*"tests_meaningful":([01]).*/\1/')"
    case "$tw$tm" in *[!0-9]*|"") echo "$fid: unparseable folded judge fields: $line"; fail_count=$((fail_count + 1)); continue ;; esac
    [ "$tw" -eq 1 ] && [ "$tm" -eq 1 ] || tests_ok=0
    tflag="\ttests=$([ "$tests_ok" -eq 1 ] && echo ok || echo "w=$tw m=$tm")"
  fi

  overscope_total=$((overscope_total + oscope))
  overbuild_total=$((overbuild_total + obuild))
  fverdict="FAIL"
  if [ "$violated" -eq 0 ] && [ "$tdone" -eq 1 ] && [ "$oscope" -eq 0 ] && [ "$obuild" -eq 0 ] && [ "$tests_ok" -eq 1 ]; then
    fverdict="PASS"; passed=$((passed + 1))
  else
    fail_count=$((fail_count + 1))
  fi

  results="${results}${fid}\tviol=${violated}\ttask=${tdone}\tscope=$([ "$oscope" -eq 1 ] && echo OVER || echo ok)\tbuild=$([ "$obuild" -eq 1 ] && echo OVER || echo ok)${tflag}\t${fverdict}\n"
done

echo
printf 'fixture\tviolations\ttask\tscope\tbuild\tresult\n'
printf '%b' "$results"
echo

pass_rate="0.00"
[ "$total" -gt 0 ] && pass_rate="$(awk "BEGIN{printf \"%.2f\", $passed/$total}")"
echo "pass-rate:        $pass_rate  (gate >= $GATE_PASS_RATE)"
echo "over-scope count: $overscope_total  (gate == 0)"
echo "over-build count: $overbuild_total  (gate == 0)"
echo "fixture failures: $fail_count"

rate_ok="$(awk "BEGIN{print ($pass_rate >= $GATE_PASS_RATE) ? 1 : 0}")"
if [ "$rate_ok" -eq 1 ] && [ "$overscope_total" -eq 0 ] && [ "$overbuild_total" -eq 0 ]; then
  echo "RESULT: PASS"
else
  echo "RESULT: FAIL"
  exit 1
fi
