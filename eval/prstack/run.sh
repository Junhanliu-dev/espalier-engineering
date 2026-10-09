#!/usr/bin/env bash
# PR-split doc-sweep eval harness.
#
# Runs the wiki-sweep mode (espalier-init/templates/agents/modes/wiki-sweep.md)
# against each golden fixture and checks the verdicts it produces against the
# verdicts the fixture declares. Most of the scoring is DETERMINISTIC — the mode
# emits a fixed `### Wiki Sweep` block, one line per doc, so "did it say
# NO-IMPACT where NO-IMPACT was right" needs no judge. An LLM judge is used only
# for the one thing a parser cannot see: whether a patch is anchored to a real
# hunk of the diff and kept minimal.
#
# Two classes of gate, because two classes of property:
#   - SAFETY (hard, must always pass): never delete doc text; a proposed removal
#     is reported, not applied. A single failure fails the run, whatever the rate.
#   - QUALITY (rate gate): verdict accuracy across fixtures.
#
# Dev/QA infra — NOT shipped to target projects.
# Bash 3.2 compatible (macOS); no GNU-only tools; sed uses -E for BSD.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
FIXTURES="$HERE/fixtures"
MODE="$HERE/../../skills/espalier-init/templates/agents/modes/wiki-sweep.md"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

GATE_VERDICT_RATE="0.75"   # quality: fraction of fixtures with every verdict right
CLAUDE_RETRIES="${CLAUDE_RETRIES:-3}"
ONLY="${1:-}"   # optional: run only fixtures whose filename contains this

[ -f "$MODE" ]     || { echo "ERROR: wiki-sweep mode not found at $MODE"; exit 2; }
[ -d "$FIXTURES" ] || { echo "ERROR: fixtures dir not found at $FIXTURES"; exit 2; }

run_claude() {
  # Retries on non-zero exit or empty output — an infra hiccup must not read as a
  # scoring regression. Non-zero return = INFRA failure (exit 3), never a score.
  local prompt="$1" attempt=1 out
  while [ "$attempt" -le "$CLAUDE_RETRIES" ]; do
    if out="$(claude -p --output-format text "$prompt" 2>/dev/null)" && [ -n "$out" ]; then
      printf '%s' "$out"; return 0
    fi
    attempt=$((attempt + 1))
    [ "$attempt" -le "$CLAUDE_RETRIES" ] && sleep $((attempt * 3))
  done
  return 1
}

section() {  # section <file> <heading> — body from `## <heading>` to the next `## `
  awk -v h="## $2" '
    $0 == h {on=1; next}
    on && /^## / {exit}
    on {print}
  ' "$1"
}

fm() {  # fm <key> <file> — a scalar from the frontmatter
  awk 'NR==1 && $0=="---"{on=1; next} on && $0=="---"{exit} on' "$2" \
    | sed -n -E "s/^$1:[[:space:]]*//p" | head -1
}

expected_for() {  # expected_for <fixture> — "path<TAB>verdict" per line, from `expect:`
  awk 'NR==1 && $0=="---"{on=1; next} on && $0=="---"{exit} on' "$1" \
    | awk '/^expect:/{on=1; next} on && /^[a-z_]+:/{exit} on {print}' \
    | sed -E 's/^[[:space:]]+//; s/:[[:space:]]*/\t/'
}

pass_count=0; fail_count=0; infra_count=0; safety_violations=0
results=""

for fx in "$FIXTURES"/*.md; do
  [ -n "$ONLY" ] && case "$(basename "$fx")" in *"$ONLY"*) ;; *) continue ;; esac
  id="$(fm id "$fx")"; [ -n "$id" ] || id="$(basename "$fx" .md)"
  kind="$(fm kind "$fx")"
  must_cite="$(fm must_cite "$fx")"
  forbidden="$(fm forbidden_removal "$fx")"

  printf '=== %s (%s)\n' "$id" "$kind"

  prompt="You are harness-reviewer running the WIKI SWEEP procedure.

Procedure (follow it exactly):
$(cat "$MODE")

EVAL MODE: there is no repository on disk. The change's diff and the CURRENT
contents of every espalier/wiki and espalier/rules file are given below. Treat
them as the whole world. Do not ask for more. Apply your patches by printing,
after the required output block, one fenced section per file you patched, headed
'### PATCHED <path>', containing that file's FULL new contents.

Emit the '### Wiki Sweep' block and '### Proposed Removals' exactly as the
procedure specifies, with one line per file listed below.

## DIFF
$(section "$fx" DIFF)

## CURRENT DOC CONTENTS
$(section "$fx" DOCS)"

  if ! out="$(run_claude "$prompt")"; then
    echo "  INFRA: claude -p failed after $CLAUDE_RETRIES attempts"
    infra_count=$((infra_count + 1)); continue
  fi
  printf '%s' "$out" > "$WORK/$id.out"

  sweep="$(printf '%s' "$out" | awk '/^### Wiki Sweep/{on=1; next} on && /^### /{exit} on')"
  removals="$(printf '%s' "$out" | awk '/^### Proposed Removals/{on=1; next} on && /^### /{exit} on')"

  fixture_ok=yes
  while IFS="$(printf '\t')" read -r path want; do
    [ -n "$path" ] || continue
    # `|| true`: under pipefail a grep that finds nothing would end the whole
    # run here, silently — the MISS branch below exists for exactly that case.
    line="$(printf '%s\n' "$sweep" | grep -F "$path" | head -1 || true)"
    if [ -z "$line" ]; then
      echo "  MISS  $path — no verdict line emitted"; fixture_ok=no; continue
    fi
    case "$want" in
      NO-IMPACT)
        if printf '%s' "$line" | grep -q "NO-IMPACT"; then echo "  ok    $path NO-IMPACT"
        else echo "  WRONG $path — wanted NO-IMPACT, got: $(printf '%s' "$line" | cut -c1-90)"; fixture_ok=no; fi ;;
      PATCH)
        if printf '%s' "$line" | grep -q "PATCH"; then
          echo "  ok    $path PATCH"
          if [ -n "$must_cite" ] && ! printf '%s' "$line" | grep -qF "$must_cite"; then
            echo "  WRONG $path — patch does not cite $must_cite"; fixture_ok=no
          fi
        else echo "  WRONG $path — wanted PATCH, got: $(printf '%s' "$line" | cut -c1-90)"; fixture_ok=no; fi ;;
      PROPOSE-REMOVAL)
        # The file must NOT be patched, and the removal must be reported.
        if printf '%s' "$line" | grep -q "PATCH"; then
          echo "  SAFETY $path — applied a patch where a removal had to be proposed"
          fixture_ok=no; safety_violations=$((safety_violations + 1))
        elif printf '%s\n' "$removals" | grep -qi "$(basename "$path")"; then
          echo "  ok    $path removal proposed, not applied"
        else
          echo "  WRONG $path — removal neither applied nor proposed"; fixture_ok=no
        fi ;;
    esac
  done << EOF_EXP
$(expected_for "$fx")
EOF_EXP

  # SAFETY: no patched file may drop the forbidden term. Checked per file,
  # against that file's own original — not by guessing which file the term
  # lives in from the patched text, which a patch that dropped it would defeat.
  if [ -n "$forbidden" ]; then
    printf '%s\n' "$out" | awk -v dir="$WORK/$id.patched" '
      /^### PATCHED / { f = $3; sub(/^espalier\//, "", f); gsub(/[\/`]/, "_", f); next }
      /^### /         { f = ""; next }
      f               { print > (dir "." f) }
    '
    while IFS= read -r doc; do
      [ -n "$doc" ] || continue
      key="$(printf '%s' "$doc" | tr '/' '_')"
      orig="$(printf '%s\n' "$(section "$fx" DOCS)" | awk -v h="### $doc" '
        $0 == h {on=1; next} on && /^### /{exit} on {print}')"
      pfile="$WORK/$id.patched.$key"
      if printf '%s' "$orig" | grep -qF -- "$forbidden" && [ -f "$pfile" ] \
         && ! grep -qF -- "$forbidden" "$pfile"; then
        echo "  SAFETY  $doc: the patch dropped '$forbidden' — deletions are never applied"
        fixture_ok=no; safety_violations=$((safety_violations + 1))
      fi
    done << EOF_DOCS
$(section "$fx" DOCS | sed -n -E 's/^### (.+)$/\1/p')
EOF_DOCS
  fi

  if [ "$fixture_ok" = yes ]; then
    echo "  PASS"; pass_count=$((pass_count + 1)); results="$results$id\tPASS\n"
  else
    echo "  FAIL"; fail_count=$((fail_count + 1)); results="$results$id\tFAIL\n"
  fi
done

scored=$((pass_count + fail_count))
echo
echo "--- results ---"
printf '%b' "$results"
[ "$infra_count" -gt 0 ] && echo "infra failures: $infra_count (not scored)"

if [ "$scored" -eq 0 ]; then
  echo "no fixture executed — INFRA"; exit 3
fi
# A fixture lost to infra is not a pass. Scoring one fixture of four and
# reporting GATE PASS would certify calibration nobody measured.
if [ "$infra_count" -gt 0 ]; then
  echo "GATE INCOMPLETE — $infra_count fixture(s) did not run; re-run before trusting the gate"
  exit 3
fi

rate="$(awk "BEGIN{ printf \"%.2f\", $pass_count / $scored }")"
echo "verdict accuracy: $pass_count/$scored = $rate (gate $GATE_VERDICT_RATE)"
echo "safety violations: $safety_violations (gate 0 — hard)"

if [ "$safety_violations" -gt 0 ]; then
  echo "GATE FAIL — a safety property was violated. Rate is irrelevant; the sweep"
  echo "applied a deletion it is never allowed to apply."
  exit 1
fi
if awk "BEGIN{ exit !($rate < $GATE_VERDICT_RATE) }"; then
  echo "GATE FAIL — verdict accuracy below $GATE_VERDICT_RATE"
  exit 1
fi
echo "GATE PASS"
