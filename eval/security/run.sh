#!/usr/bin/env bash
# Security eval harness runner.
# Runs the harness-security auditor against each golden fixture (a code change with
# planted vulnerabilities, or a clean change), scores the produced security-record
# with an LLM judge, and gates on the aggregate catch-rate + a zero-false-positive
# rule + verdict accuracy.
#
# Two fixture modes:
#   (default)          change-scoped Stage-4 audit — single `file:` body, the
#                      auditor writes security-record.md.
#   mode: repo-audit   /espalier-audit repo-audit mode — multi-file body
#                      (`=== FILE: <path> ===` blocks), the auditor RETURNS its
#                      findings (captured stdout), no security-record.md.
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
# KEEP_WORK=1 preserves the throwaway projects, records, and per-fixture judge
# lines for judge-validation / debugging (default: clean up on exit).
KEEP_WORK="${KEEP_WORK:-0}"
[ "$KEEP_WORK" = "1" ] || trap 'rm -rf "$WORK"' EXIT
if [ "$KEEP_WORK" = "1" ]; then : > "$WORK/judge-lines.tsv"; fi

# Security is higher-stakes than grill: a missed vuln is a shipped hole. Gate is
# strict and PROVISIONAL until the fixture set reaches 20-30 (see README).
GATE_CATCH_RATE="0.90"

# Optional $1: a fixture glob (e.g. 'vuln-*.md') for partial re-runs after a
# transient failure, or while iterating on one fixture. The RESULT then covers
# only that subset — the release gate is the no-argument FULL run.
FIXTURE_GLOB="${1:-*.md}"
[ "$FIXTURE_GLOB" = "*.md" ] || echo "NOTE: partial run (glob=$FIXTURE_GLOB) — the release gate requires the full suite."

[ -f "$AGENT_TPL" ] || { echo "ERROR: harness-security template not found at $AGENT_TPL"; exit 2; }
[ -f "$RUBRIC" ]    || { echo "ERROR: rubric not found at $RUBRIC"; exit 2; }
[ -d "$FIXTURES" ]  || { echo "ERROR: fixtures dir not found at $FIXTURES"; exit 2; }

total_planted=0
total_caught=0
total_fp=0
fail_count=0
results=""   # "fixture_id\tkind\tcaught/planted\tfp\tverdict\tPASS|FAIL\n"

# install_espalier PROJ — generate the security install the auditor reads
# (project name substituted). Shared by both modes.
install_espalier() {
  local proj="$1"
  mkdir -p "$proj/espalier/rules" "$proj/espalier/agents" \
           "$proj/espalier/skills/espalier-security" "$proj/espalier/wiki"
  sed -e 's/{project_name}/EvalApp/g' -e 's/{project}/EvalApp/g' "$AGENT_TPL" > "$proj/espalier/agents/harness-security.md"
  sed -e 's/{project_name}/EvalApp/g' -e 's/{project}/EvalApp/g' "$SKILL_TPL" > "$proj/espalier/skills/espalier-security/SKILL.md"
  cp "$RULE_TPL" "$proj/espalier/rules/security-standards.md"
  printf '# Critical Paths\nEntry points: controllers / handlers / queue consumers in src/. No auth middleware unless shown in the change.\n' > "$proj/espalier/wiki/critical-paths.md"
}

# Build a throwaway project for the fixture and run the auditor headless.
# Produces $WORK/$fid/espalier/changes/feat/eval/security-record.md
run_audit() {
  local fixture="$1" fid="$2"
  local file; file="$(sed -n -E 's/^file:[[:space:]]*//p' "$fixture" | head -1)"
  [ -n "$file" ] || file="src/change.js"
  local proj="$WORK/$fid"
  local cdir="$proj/espalier/changes/feat/eval"
  mkdir -p "$proj/$(dirname "$file")" "$cdir"
  install_espalier "$proj"

  # fixture body (everything after the 2nd `---`) → the changed file
  awk 'body{print} /^---[[:space:]]*$/{c++; if(c==2) body=1}' "$fixture" > "$proj/$file"

  printf '## Coding Report\n- Files created: %s\n- Layers touched: (inspect the file)\n- Notes: the change under audit.\n' "$file" > "$cdir/coding-report.md"

  claude -p --dangerously-skip-permissions --output-format text \
"You are the harness-security auditor for EvalApp. The project root is $proj; EVERY espalier/ path is relative to that root.

Read $proj/espalier/agents/harness-security.md and follow it EXACTLY (including reading the rule $proj/espalier/rules/security-standards.md and skill $proj/espalier/skills/espalier-security/SKILL.md it references).

WHAT TO AUDIT: read $cdir/coding-report.md, then the file it lists ($proj/$file). Assume the client is hostile.

Write your audit (OVERWRITE) to $cdir/security-record.md using your instruction file's EXACT output format (findings table + Verdict + the '## Security-Sensitive Fields' contract when a sensitive surface is touched). You have no Write/Edit tool — write the record via a Bash heredoc/redirection." >/dev/null 2>&1 || return 1
}

# Repo-audit mode: materialize the fixture's '=== FILE: <path> ===' blocks into a
# throwaway project, run the auditor with the /espalier-audit spawn prompt, and
# capture its FINAL MESSAGE (stdout) as the findings record — repo-audit mode
# writes no security-record.md by design.
# Produces $WORK/$fid/repo-findings.md
run_repo_audit() {
  local fixture="$1" fid="$2"
  local proj="$WORK/$fid"
  mkdir -p "$proj"
  install_espalier "$proj"

  # fixture body (after the 2nd `---`) → one file per '=== FILE: ... ===' block
  awk 'body{print} /^---[[:space:]]*$/{c++; if(c==2) body=1}' "$fixture" \
  | (
      cur=""
      while IFS= read -r line; do
        case "$line" in
          "=== FILE: "*" ===")
            cur="${line#=== FILE: }"; cur="${cur% ===}"
            mkdir -p "$proj/$(dirname "$cur")"
            : > "$proj/$cur"
            ;;
          *)
            [ -n "$cur" ] && printf '%s\n' "$line" >> "$proj/$cur"
            ;;
        esac
      done
    )

  local filelist
  filelist="$(sed -n -E 's/^=== FILE: (.*) ===$/\1/p' "$fixture")"
  [ -n "$filelist" ] || return 1

  claude -p --dangerously-skip-permissions --output-format text \
"You are the harness-security auditor in REPO-AUDIT MODE for EvalApp. The project root is $proj; EVERY espalier/ path is relative to that root.

Read $proj/espalier/agents/harness-security.md and follow its '## Repo-Audit Mode' section EXACTLY (including reading the rule $proj/espalier/rules/security-standards.md and skill $proj/espalier/skills/espalier-security/SKILL.md it references). You are auditing EXISTING code, not a change — there is no coding-report.md and no changes/ dir.

SURFACE FILES TO AUDIT (paths relative to $proj — the code as it stands NOW):
$filelist

Trace every client-supplied value in these files to its authorization decision or persistence call. Assume the client is hostile. Do NOT write security-record.md — your ENTIRE final message must be the Repo-Audit output format from your instruction file (findings table + '**Batch verdict:**' + the '### Security-Sensitive Fields' / '### Controls Confirmed' / '### No Sensitive Fields' sections)." \
    > "$WORK/$fid.repo-findings.md" 2>/dev/null || return 1
  # claude -p can exit 0 with empty output on an aborted run — treat as failure.
  [ -s "$WORK/$fid.repo-findings.md" ] || return 1
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

for fixture in "$FIXTURES"/$FIXTURE_GLOB; do
  [ -e "$fixture" ] || { echo "ERROR: no fixtures found"; exit 2; }
  fid="$(basename "$fixture" .md)"
  kind="$(sed -n -E 's/^kind:[[:space:]]*//p' "$fixture" | head -1)"
  mode="$(sed -n -E 's/^mode:[[:space:]]*//p' "$fixture" | head -1)"

  if [ "$mode" = "repo-audit" ]; then
    if ! run_repo_audit "$fixture" "$fid"; then
      echo "$fid: repo-audit run failed"; fail_count=$((fail_count + 1)); continue
    fi
    record="$WORK/$fid.repo-findings.md"
  else
    if ! run_audit "$fixture" "$fid"; then
      echo "$fid: auditor run failed"; fail_count=$((fail_count + 1)); continue
    fi
    record="$WORK/$fid/espalier/changes/feat/eval/security-record.md"
    if [ ! -f "$record" ]; then
      echo "$fid: auditor wrote no security-record.md"; fail_count=$((fail_count + 1)); continue
    fi
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

  if [ "$KEEP_WORK" = "1" ]; then
    cp "$record" "$WORK/$fid.record.md" 2>/dev/null || true
    printf '%s\t%s\n' "$fid" "$line" >> "$WORK/judge-lines.tsv"
  fi

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
if [ "$KEEP_WORK" = "1" ]; then echo "KEEP_WORK dir:    $WORK"; fi

rate_ok="$(awk "BEGIN{print ($catch_rate >= $GATE_CATCH_RATE) ? 1 : 0}")"
if [ "$rate_ok" -eq 1 ] && [ "$total_fp" -eq 0 ] && [ "$fail_count" -eq 0 ]; then
  echo "RESULT: PASS"
else
  echo "RESULT: FAIL"
  exit 1
fi
