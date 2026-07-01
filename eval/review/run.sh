#!/usr/bin/env bash
# Review eval harness runner.
# Runs the harness-reviewer against each golden fixture (a code change with planted
# convention/correctness/layer violations, or a clean change) reviewed against the
# canned ReviewApp conventions, scores the review-record with an LLM judge, and gates
# on catch-rate + a zero-false-positive rule + verdict accuracy.
#
# Dev/QA infra — NOT shipped to target projects. Mirrors eval/security/run.sh.
# Bash 3.2 compatible (macOS); no GNU-only tools; sed uses -E for BSD.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
FIXTURES="$HERE/fixtures"
RUBRIC="$HERE/rubric.md"
PROJECT="$HERE/project"
TPL="$HERE/../../skills/espalier-init/templates"
AGENT_TPL="$TPL/agents/harness-reviewer.md"
REVIEW_SKILL_TPL="$TPL/skills/espalier-review.md"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

GATE_CATCH_RATE="0.80"

for f in "$AGENT_TPL" "$REVIEW_SKILL_TPL" "$RUBRIC" "$PROJECT/coding-standards.md" "$PROJECT/engineering-structure.md"; do
  [ -f "$f" ] || { echo "ERROR: required file not found: $f"; exit 2; }
done
[ -d "$FIXTURES" ] || { echo "ERROR: fixtures dir not found at $FIXTURES"; exit 2; }

total_planted=0
total_caught=0
total_fp=0
fail_count=0
results=""

run_review() {
  local fixture="$1" fid="$2"
  local file; file="$(sed -n -E 's/^file:[[:space:]]*//p' "$fixture" | head -1)"
  [ -n "$file" ] || file="src/change.js"
  local proj="$WORK/$fid"
  local cdir="$proj/espalier/changes/feat/eval"
  mkdir -p "$proj/$(dirname "$file")" "$proj/espalier/rules" "$proj/espalier/agents" \
           "$proj/espalier/skills/espalier-review" "$cdir"

  awk 'body{print} /^---[[:space:]]*$/{c++; if(c==2) body=1}' "$fixture" > "$proj/$file"

  cp "$PROJECT/coding-standards.md"      "$proj/espalier/rules/coding-standards.md"
  cp "$PROJECT/engineering-structure.md" "$proj/espalier/rules/engineering-structure.md"
  sed -e 's/{project_name}/ReviewApp/g' -e 's/{project}/ReviewApp/g' "$AGENT_TPL" > "$proj/espalier/agents/harness-reviewer.md"
  sed -e 's/{project_name}/ReviewApp/g' -e 's/{project}/ReviewApp/g' "$REVIEW_SKILL_TPL" > "$proj/espalier/skills/espalier-review/SKILL.md"
  printf '## Coding Report\n- Files created: %s\n- Layers touched: (inspect the file path)\n- Notes: the change under review.\n' "$file" > "$cdir/coding-report.md"

  claude -p --output-format text \
"You are the harness-reviewer for ReviewApp. The project root is $proj; EVERY espalier/ path is relative to that root.

Read $proj/espalier/agents/harness-reviewer.md and follow it EXACTLY. Review against $proj/espalier/rules/coding-standards.md and $proj/espalier/rules/engineering-structure.md and $proj/espalier/skills/espalier-review/SKILL.md. Judge ONLY against those project rules, not generic opinions.

WHAT TO REVIEW: read $cdir/coding-report.md, then the file it lists ($proj/$file).

Write your review to $cdir/review-record.md using your instruction file's EXACT output format (findings table with Priority + Verdict). You have no Write/Edit tool — use a Bash heredoc/redirection." >/dev/null 2>&1 || return 1
}

judge() {
  local fixture="$1" record="$2"
  claude -p --output-format text \
"You are the review eval JUDGE. Score objectively against the rubric. Rubric:
$(cat "$RUBRIC")

Fixture (frontmatter is the answer key — planted_issues, expected_verdict, false_positive_watch):
$(cat "$fixture")

review-record the reviewer produced:
$(cat "$record")

Output ONE line of compact JSON only, no prose:
{\"planted\":N,\"caught\":N,\"false_positives\":N,\"verdict_match\":0,\"verdict\":\"PASS\"}" \
    2>/dev/null
}

for fixture in "$FIXTURES"/*.md; do
  [ -e "$fixture" ] || { echo "ERROR: no fixtures found"; exit 2; }
  fid="$(basename "$fixture" .md)"
  kind="$(sed -n -E 's/^kind:[[:space:]]*//p' "$fixture" | head -1)"

  if ! run_review "$fixture" "$fid"; then
    echo "$fid: reviewer run failed"; fail_count=$((fail_count + 1)); continue
  fi
  record="$WORK/$fid/espalier/changes/feat/eval/review-record.md"
  if [ ! -f "$record" ]; then
    echo "$fid: reviewer wrote no review-record.md"; fail_count=$((fail_count + 1)); continue
  fi
  if ! line="$(judge "$fixture" "$record")"; then
    echo "$fid: judge failed"; fail_count=$((fail_count + 1)); continue
  fi

  planted="$(printf '%s' "$line" | sed -E 's/.*"planted":([0-9]+).*/\1/')"
  caught="$(printf '%s'  "$line" | sed -E 's/.*"caught":([0-9]+).*/\1/')"
  fp="$(printf '%s'      "$line" | sed -E 's/.*"false_positives":([0-9]+).*/\1/')"
  vmatch="$(printf '%s'  "$line" | sed -E 's/.*"verdict_match":([01]).*/\1/')"

  case "$planted$caught$fp$vmatch" in *[!0-9]*|"") echo "$fid: unparseable judge output: $line"; fail_count=$((fail_count + 1)); continue ;; esac

  total_planted=$((total_planted + planted))
  total_caught=$((total_caught + caught))
  total_fp=$((total_fp + fp))

  fverdict="FAIL"
  if [ "$caught" -ge "$planted" ] && [ "$fp" -eq 0 ] && [ "$vmatch" -eq 1 ]; then
    fverdict="PASS"
  else
    fail_count=$((fail_count + 1))
  fi

  results="${results}${fid}\t${kind}\t${caught}/${planted}\t${fp}\t$([ "$vmatch" -eq 1 ] && echo match || echo MISMATCH)\t${fverdict}\n"
done

echo
printf 'fixture\tkind\tcaught\tfp\tverdict\tresult\n'
printf '%b' "$results"
echo

catch_rate="1.00"
[ "$total_planted" -gt 0 ] && catch_rate="$(awk "BEGIN{printf \"%.2f\", $total_caught/$total_planted}")"
echo "catch-rate:       $catch_rate  (gate >= $GATE_CATCH_RATE)"
echo "false positives:  $total_fp    (gate == 0)"
echo "fixture failures: $fail_count"

rate_ok="$(awk "BEGIN{print ($catch_rate >= $GATE_CATCH_RATE) ? 1 : 0}")"
if [ "$rate_ok" -eq 1 ] && [ "$total_fp" -eq 0 ] && [ "$fail_count" -eq 0 ]; then
  echo "RESULT: PASS"
else
  echo "RESULT: FAIL"
  exit 1
fi
