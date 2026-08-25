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
PROD_RULE_TPL="$TPL/rules/production-standards.md"
SEC_RULE_TPL="$TPL/rules/security-standards.md"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

GATE_CATCH_RATE="0.80"

# Optional $1: a fixture glob (e.g. 'rule-*.md') for partial re-runs after a
# transient (rate-limit) failure. The RESULT then covers only that subset — the
# release gate is the no-argument FULL run.
FIXTURE_GLOB="${1:-*.md}"
[ "$FIXTURE_GLOB" = "*.md" ] || echo "NOTE: partial run (glob=$FIXTURE_GLOB) — the release gate requires the full suite."

for f in "$AGENT_TPL" "$REVIEW_SKILL_TPL" "$PROD_RULE_TPL" "$SEC_RULE_TPL" "$RUBRIC" "$PROJECT/coding-standards.md" "$PROJECT/engineering-structure.md"; do
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
  # v0.9.0: the reviewer's Before-Reviewing step reads these always-loaded rules.
  # Universal seeds bind even with the {discovered} cells unfilled.
  cp "$PROD_RULE_TPL" "$proj/espalier/rules/production-standards.md"
  cp "$SEC_RULE_TPL"  "$proj/espalier/rules/security-standards.md"
  sed -e 's/{project_name}/ReviewApp/g' -e 's/{project}/ReviewApp/g' "$AGENT_TPL" > "$proj/espalier/agents/harness-reviewer.md"
  sed -e 's/{project_name}/ReviewApp/g' -e 's/{project}/ReviewApp/g' "$REVIEW_SKILL_TPL" > "$proj/espalier/skills/espalier-review/SKILL.md"

  # Multi-file fixture support (v0.23 combined code+tests fixtures): a body
  # made of '=== FILE: <path> ===' blocks materializes one file per block;
  # otherwise the whole body is the single $file, as before.
  if grep -q '^=== FILE: ' "$fixture"; then
    awk 'body{print} /^---[[:space:]]*$/{c++; if(c==2) body=1}' "$fixture" \
    | (
        cur=""
        while IFS= read -r bline; do
          case "$bline" in
            "=== FILE: "*" ===")
              cur="${bline#=== FILE: }"; cur="${cur% ===}"
              mkdir -p "$proj/$(dirname "$cur")"
              : > "$proj/$cur"
              ;;
            *)
              [ -n "$cur" ] && printf '%s\n' "$bline" >> "$proj/$cur"
              ;;
          esac
        done
      )
    filelist="$(sed -n -E 's/^=== FILE: (.*) ===$/\1/p' "$fixture")"
    testlist="$(printf '%s\n' "$filelist" | grep -E '^tests?/' || true)"
    {
      printf '## Coding Report\n- Files created: %s\n' "$(printf '%s' "$filelist" | tr '\n' ' ')"
      [ -n "$testlist" ] && printf -- '- Test files: %s\n' "$(printf '%s' "$testlist" | tr '\n' ' ')"
      printf -- '- Layers touched: (inspect the file paths)\n- Notes: the change under review.\n'
    } > "$cdir/coding-report.md"
    file="$(printf '%s\n' "$filelist" | head -1)"
  else
    printf '## Coding Report\n- Files created: %s\n- Layers touched: (inspect the file path)\n- Notes: the change under review.\n' "$file" > "$cdir/coding-report.md"
  fi

  claude -p --dangerously-skip-permissions --output-format text \
"You are the harness-reviewer for ReviewApp. The project root is $proj; EVERY espalier/ path is relative to that root.

Read $proj/espalier/agents/harness-reviewer.md and follow it EXACTLY. Review against $proj/espalier/rules/coding-standards.md, $proj/espalier/rules/engineering-structure.md, $proj/espalier/rules/production-standards.md, and $proj/espalier/skills/espalier-review/SKILL.md. Judge ONLY against those project rules, not generic opinions.

WHAT TO REVIEW: read $cdir/coding-report.md, then EVERY file it lists (under $proj/). When it lists test files, your verdict covers the tests too — run your test checklist on them with the code in view.

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

for fixture in "$FIXTURES"/$FIXTURE_GLOB; do
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
  # A judge reply sometimes carries prose before the JSON — take the LAST
  # JSON-object line rather than failing the fixture on the preamble.
  line="$(printf '%s\n' "$line" | grep -E '^\{.*\}[[:space:]]*$' | tail -1)"

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
