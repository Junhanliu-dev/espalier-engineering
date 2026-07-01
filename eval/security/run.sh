#!/usr/bin/env bash
# Security eval harness runner.
# Runs the harness-security auditor against each golden fixture (a code change with
# planted vulnerabilities, or a clean change), scores the produced security-record
# with an LLM judge, and gates on the aggregate catch-rate + a zero-false-positive
# rule + verdict accuracy.
#
# Dev/QA infra — NOT shipped to target projects. Mirrors eval/grill/run.sh.
# Bash 3.2 compatible (macOS); no GNU-only tools; sed uses -E for BSD.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
FIXTURES="$HERE/fixtures"
RUBRIC="$HERE/rubric.md"
TPL="$HERE/../../skills/espalier-init/templates"
AGENT_TPL="$TPL/agents/harness-security.md"
RULE_TPL="$TPL/rules/security-standards.md"
SKILL_TPL="$TPL/skills/espalier-security.md"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Security is higher-stakes than grill: a missed vuln is a shipped hole. Gate is
# strict and PROVISIONAL until the fixture set reaches 20-30 (see README).
GATE_CATCH_RATE="0.90"

[ -f "$AGENT_TPL" ] || { echo "ERROR: harness-security template not found at $AGENT_TPL"; exit 2; }
[ -f "$RUBRIC" ]    || { echo "ERROR: rubric not found at $RUBRIC"; exit 2; }
[ -d "$FIXTURES" ]  || { echo "ERROR: fixtures dir not found at $FIXTURES"; exit 2; }

total_planted=0
total_caught=0
total_fp=0
fail_count=0
results=""   # "fixture_id\tkind\tcaught/planted\tfp\tverdict\tPASS|FAIL\n"

# Build a throwaway project for the fixture and run the auditor headless.
# Produces $WORK/$fid/espalier/changes/feat/eval/security-record.md
run_audit() {
  local fixture="$1" fid="$2"
  local file; file="$(sed -n -E 's/^file:[[:space:]]*//p' "$fixture" | head -1)"
  [ -n "$file" ] || file="src/change.js"
  local proj="$WORK/$fid"
  local cdir="$proj/espalier/changes/feat/eval"
  mkdir -p "$proj/$(dirname "$file")" "$proj/espalier/rules" "$proj/espalier/agents" \
           "$proj/espalier/skills/espalier-security" "$proj/espalier/wiki" "$cdir"

  # fixture body (everything after the 2nd `---`) → the changed file
  awk 'body{print} /^---[[:space:]]*$/{c++; if(c==2) body=1}' "$fixture" > "$proj/$file"

  # generate the security install the auditor reads (project name substituted)
  sed -e 's/{project_name}/EvalApp/g' -e 's/{project}/EvalApp/g' "$AGENT_TPL" > "$proj/espalier/agents/harness-security.md"
  sed -e 's/{project_name}/EvalApp/g' -e 's/{project}/EvalApp/g' "$SKILL_TPL" > "$proj/espalier/skills/espalier-security/SKILL.md"
  cp "$RULE_TPL" "$proj/espalier/rules/security-standards.md"
  printf '# Critical Paths\nEntry points: controllers / handlers / queue consumers in src/. No auth middleware unless shown in the change.\n' > "$proj/espalier/wiki/critical-paths.md"
  printf '## Coding Report\n- Files created: %s\n- Layers touched: (inspect the file)\n- Notes: the change under audit.\n' "$file" > "$cdir/coding-report.md"

  claude -p --dangerously-skip-permissions --output-format text \
"You are the harness-security auditor for EvalApp. The project root is $proj; EVERY espalier/ path is relative to that root.

Read $proj/espalier/agents/harness-security.md and follow it EXACTLY (including reading the rule $proj/espalier/rules/security-standards.md and skill $proj/espalier/skills/espalier-security/SKILL.md it references).

WHAT TO AUDIT: read $cdir/coding-report.md, then the file it lists ($proj/$file). Assume the client is hostile.

Write your audit (OVERWRITE) to $cdir/security-record.md using your instruction file's EXACT output format (findings table + Verdict + the '## Security-Sensitive Fields' contract when a sensitive surface is touched). You have no Write/Edit tool — write the record via a Bash heredoc/redirection." >/dev/null 2>&1 || return 1
}

judge() {
  # $1 = fixture, $2 = security-record file. Prints ONE compact JSON line.
  local fixture="$1" record="$2"
  claude -p --output-format text \
"You are the security eval JUDGE. Score objectively against the rubric. Rubric:
$(cat "$RUBRIC")

Fixture (frontmatter is the answer key — planted_vulns, expected_verdict, false_positive_watch):
$(cat "$fixture")

security-record the auditor produced:
$(cat "$record")

Output ONE line of compact JSON only, no prose:
{\"planted\":N,\"caught\":N,\"false_positives\":N,\"verdict_match\":0,\"verdict\":\"PASS\"}" \
    2>/dev/null
}

for fixture in "$FIXTURES"/*.md; do
  [ -e "$fixture" ] || { echo "ERROR: no fixtures found"; exit 2; }
  fid="$(basename "$fixture" .md)"
  kind="$(sed -n -E 's/^kind:[[:space:]]*//p' "$fixture" | head -1)"

  if ! run_audit "$fixture" "$fid"; then
    echo "$fid: auditor run failed"; fail_count=$((fail_count + 1)); continue
  fi
  record="$WORK/$fid/espalier/changes/feat/eval/security-record.md"
  if [ ! -f "$record" ]; then
    echo "$fid: auditor wrote no security-record.md"; fail_count=$((fail_count + 1)); continue
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

  # per-fixture PASS: every planted vuln caught, no false positives, verdict matches
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
