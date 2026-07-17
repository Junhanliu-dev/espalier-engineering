#!/bin/bash
# Migrate a v0.12.0 Espalier install to v0.13.0.
#
# v0.13.0 gives the coder a Solution Selection Ladder (convention-bounded
# minimalism: conventions first, correctness within them, brevity only breaks
# ties) and the reviewer an advisory Minimalism Review (delete/stdlib/native/
# yagni findings capped at P2/P3, one P1 exception for a NEW dependency that
# stdlib / a native feature / an installed dep already covers). It also binds
# the sentinel's p1= count to the P1 row count and restores the fan-out P1
# bullet that had drifted from production-standards.md.
#
# The four touched files are PER-PROJECT files (placeholder-substituted or
# scout-filled at init), so this migration is SURGICAL — anchored section
# inserts and line replacements, never a template overwrite. New section
# bodies are extracted from the v0.13.0 plugin templates at runtime, so the
# script cannot drift from the templates it installs.
#
# Files patched (backed up to <file>.pre-v0.13.bak):
#   espalier/agents/harness-coder.md          + Solution Selection Ladder, ladder checklist step
#   espalier/agents/harness-reviewer.md       + Minimalism Review, process step, Summary line,
#                                               p1= binding, fan-out P1 bullet, Must-NOT bullet,
#                                               full espalier-security citation path
#   espalier/skills/espalier-coding/SKILL.md  + Solution Selection summary, Before-Writing pointer
#   espalier/skills/espalier-review/SKILL.md  + plan-review pass condition, Leanness checklist,
#                                               Minimalism in the panel description
#
# NOT migrated (fresh-install only, cosmetic): the richer frontmatter
# descriptions on harness-coder/harness-reviewer/espalier-coding — they carry
# per-project substitutions this script cannot re-derive. Functional parity is
# complete without them.
#
# Usage:
#   bash migrate-v0.12.0-to-v0.13.0.sh [--dry-run] [--yes] [--plugin-dir=<path>]

set -u

DRY_RUN=no
SKIP_PROMPT=no
PLUGIN_DIR="${ESPALIER_PLUGIN_DIR:-}"

for arg in "$@"; do
  case "$arg" in
    --dry-run)      DRY_RUN=yes ;;
    --yes)          SKIP_PROMPT=yes ;;
    --plugin-dir=*) PLUGIN_DIR="${arg#--plugin-dir=}" ;;
    -h|--help)      sed -n '2,35p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown flag: $arg (use --help)" >&2; exit 2 ;;
  esac
done

log() { echo "[migrate v0.12.0→v0.13.0] $*"; }
die() { echo "[migrate v0.12.0→v0.13.0] ERROR: $*" >&2; exit 1; }

[ -d espalier ] || die "no espalier/ dir — run from the target project root."

# --- Locate plugin templates -------------------------------------------------
if [ -z "$PLUGIN_DIR" ]; then
  _self_root="$(cd "$(dirname "$0")/.." && pwd)"
  [ -d "$_self_root/skills/espalier-init/templates/agents" ] && PLUGIN_DIR="$_self_root"
fi
[ -n "$PLUGIN_DIR" ] || die "cannot locate the plugin. Pass --plugin-dir=<espalier-engineering root>."
TPL="$PLUGIN_DIR/skills/espalier-init/templates"
CODER_TPL="$TPL/agents/harness-coder.md"
REVIEWER_TPL="$TPL/agents/harness-reviewer.md"
CODING_TPL="$TPL/skills/espalier-coding.md"
for f in "$CODER_TPL" "$REVIEWER_TPL" "$CODING_TPL"; do
  [ -f "$f" ] || die "plugin dir $PLUGIN_DIR is missing template $f."
done

# The templates must actually be v0.13.0 — otherwise a stale plugin would
# "migrate" the install to nothing.
grep -qF -- '## Solution Selection Ladder' "$CODER_TPL" || \
  die "template at $PLUGIN_DIR is not v0.13.0 (coder template lacks the Solution Selection Ladder). Update the plugin first."
grep -qF -- '## Minimalism Review' "$REVIEWER_TPL" || \
  die "template at $PLUGIN_DIR is not v0.13.0 (reviewer template lacks the Minimalism Review). Update the plugin first."

CODER="espalier/agents/harness-coder.md"
REVIEWER="espalier/agents/harness-reviewer.md"
CODING="espalier/skills/espalier-coding/SKILL.md"
REVIEW="espalier/skills/espalier-review/SKILL.md"
for f in "$CODER" "$REVIEWER" "$CODING" "$REVIEW"; do
  [ -f "$f" ] || die "$f not found — is this a v0.12.0 install? Run the earlier chain steps first."
done

# --- Idempotency: already migrated? ------------------------------------------
if grep -qF -- '## Solution Selection Ladder' "$CODER" \
   && grep -qF -- '## Minimalism Review' "$REVIEWER" \
   && grep -qF -- '## Solution Selection (keep it lean)' "$CODING" \
   && grep -qF -- 'Gate (pass condition)' "$REVIEW"; then
  log "already at v0.13.0 (all four markers present). Nothing to do."
  exit 0
fi

# --- Plan --------------------------------------------------------------------
log "will patch (surgical, anchored):"
grep -qF -- '## Solution Selection Ladder' "$CODER"  || log "  $CODER: + Solution Selection Ladder section, + ladder checklist step"
grep -qF -- '## Minimalism Review' "$REVIEWER"       || log "  $REVIEWER: + Minimalism Review section, process step, Summary line, p1= binding, fan-out P1, Must-NOT bullet, citation path"
grep -qF -- '## Solution Selection (keep it lean)' "$CODING" || log "  $CODING: + Solution Selection summary, Before-Writing steps -> canonical pointer"
grep -qF -- 'Gate (pass condition)' "$REVIEW"        || log "  $REVIEW: + plan-review pass condition, Leanness checklist, Minimalism in panel description"

if [ "$DRY_RUN" = yes ]; then
  log "dry-run: no files changed."
  exit 0
fi
if [ "$SKIP_PROMPT" != yes ]; then
  printf '[migrate v0.12.0→v0.13.0] proceed? [y/N] '
  read -r reply
  case "$reply" in y|Y|yes|YES) ;; *) log "aborted."; exit 0 ;; esac
fi

# --- Helpers -----------------------------------------------------------------
# extract_span <file> <start-regex> <end-regex>  — prints lines from start
# (inclusive) to end (exclusive).
extract_span() {
  awk -v s="$2" -v e="$3" '$0 ~ s {on=1} on && $0 ~ e && $0 !~ s {exit} on {print}' "$1"
}
backup_once() { [ -f "$1.pre-v0.13.bak" ] || cp "$1" "$1.pre-v0.13.bak"; }

# --- Patch A: harness-coder.md ------------------------------------------------
if ! grep -qF -- '## Solution Selection Ladder' "$CODER"; then
  backup_once "$CODER"
  # A1: insert the ladder section (from the template) before "## Output Format".
  extract_span "$CODER_TPL" '^## Solution Selection Ladder' '^## Output Format' > /tmp/espalier-ladder.$$
  awk -v ins="/tmp/espalier-ladder.$$" '
    /^## Output Format \(when task complete\)/ && !done {
      while ((getline line < ins) > 0) print line
      close(ins); done=1
    }
    {print}
  ' "$CODER" > "$CODER.tmp" && mv "$CODER.tmp" "$CODER"
  rm -f /tmp/espalier-ladder.$$
  log "patched $CODER: + Solution Selection Ladder"
fi
if ! grep -qF -- 'Climb the Solution Selection Ladder' "$CODER"; then
  backup_once "$CODER"
  # A2: add checklist step 7 after the stale-doc step's final line.
  awk '
    {print}
    /do NOT refresh the doc yourself\.$/ && !done {
      print "7. Climb the Solution Selection Ladder (below) before choosing the SHAPE of the"
      print "   change — after you understand it, never instead of understanding it."
      done=1
    }
  ' "$CODER" > "$CODER.tmp" && mv "$CODER.tmp" "$CODER"
  log "patched $CODER: + ladder checklist step"
fi

# --- Patch B: harness-reviewer.md ----------------------------------------------
if ! grep -qF -- '## Minimalism Review' "$REVIEWER"; then
  backup_once "$REVIEWER"
  # B1: insert the Minimalism Review section (from the template) before the
  # Security Abuse-Test Coverage section.
  extract_span "$REVIEWER_TPL" '^## Minimalism Review' '^## Security Abuse-Test Coverage' > /tmp/espalier-minrev.$$
  awk -v ins="/tmp/espalier-minrev.$$" '
    /^## Security Abuse-Test Coverage/ && !done {
      while ((getline line < ins) > 0) print line
      close(ins); done=1
    }
    {print}
  ' "$REVIEWER" > "$REVIEWER.tmp" && mv "$REVIEWER.tmp" "$REVIEWER"
  rm -f /tmp/espalier-minrev.$$
  log "patched $REVIEWER: + Minimalism Review section"
fi
if ! grep -qF -- 'Run the **Minimalism Review**' "$REVIEWER"; then
  backup_once "$REVIEWER"
  # B2: slot the Minimalism step into the numbered Review Process.
  awk '
    /^6\. Produce findings in the required format/ && !done {
      print "6. Run the **Minimalism Review** (see section below) — advisory P2/P3 notes,"
      print "   plus the single new-dependency P1 rule."
      print "7. Produce findings in the required format"
      done=1; next
    }
    {print}
  ' "$REVIEWER" > "$REVIEWER.tmp" && mv "$REVIEWER.tmp" "$REVIEWER"
  log "patched $REVIEWER: + Minimalism process step"
fi
if ! grep -qF -- '- Minimalism: {lean / N advisory notes}' "$REVIEWER"; then
  backup_once "$REVIEWER"
  # B3: add the Minimalism line to the Summary block.
  awk '
    {print}
    /^- Production readiness: \{seeds verified \/ findings filed\}/ && !done {
      print "- Minimalism: {lean / N advisory notes}"
      done=1
    }
  ' "$REVIEWER" > "$REVIEWER.tmp" && mv "$REVIEWER.tmp" "$REVIEWER"
  log "patched $REVIEWER: + Summary Minimalism line"
fi
if ! grep -qF -- 'and `p1=` the number of P1 rows' "$REVIEWER"; then
  backup_once "$REVIEWER"
  # B4: bind p1= to the P1 row count like p0= (replaces the two v0.12 lines).
  awk '
    /^fixpoint exit deterministically\. `p0=` must equal the number of P0 rows in your$/ && !done {
      print "fixpoint exit deterministically. `p0=` must equal the number of P0 rows in your"
      print "table, and `p1=` the number of P1 rows (the gate reads both counts — a"
      print "minimalism new-dependency P1 counts like any other P1); a missing or"
      print "mismatched sentinel is treated as an incomplete review and"
      getline  # consume the old "table; a missing or mismatched sentinel ..." line
      done=1; next
    }
    {print}
  ' "$REVIEWER" > "$REVIEWER.tmp" && mv "$REVIEWER.tmp" "$REVIEWER"
  log "patched $REVIEWER: p1= bound to P1 row count"
fi
if ! grep -qF -- 'unbounded fan-out (N calls in a loop) on a request path' "$REVIEWER"; then
  backup_once "$REVIEWER"
  # B5: restore the fan-out P1 bullet (drifted from production-standards.md).
  awk '
    {print}
    /^- an unbounded list query on a request path \(no pagination\/limit\/cap\);$/ && !done {
      print "- unbounded fan-out (N calls in a loop) on a request path;"
      done=1
    }
  ' "$REVIEWER" > "$REVIEWER.tmp" && mv "$REVIEWER.tmp" "$REVIEWER"
  log "patched $REVIEWER: + fan-out P1 bullet"
fi
if ! grep -qF -- 'File a minimalism finding above P2' "$REVIEWER"; then
  backup_once "$REVIEWER"
  # B6: extend the You Must NOT list.
  awk '
    {print}
    /^  production-standards tier \(run the Production-Readiness Review\)$/ && !done {
      print "- File a minimalism finding above P2 (sole exception: the new-dependency P1),"
      print "  or against a construct the rules/specs mandate (that is a Convention"
      print "  Observation, not a finding)"
      done=1
    }
  ' "$REVIEWER" > "$REVIEWER.tmp" && mv "$REVIEWER.tmp" "$REVIEWER"
  log "patched $REVIEWER: + Must-NOT minimalism bullet"
fi
if ! grep -qF -- 'espalier/skills/espalier-security/SKILL.md`: `FAIL`' "$REVIEWER"; then
  backup_once "$REVIEWER"
  # B7: give the espalier-security citation its full path (v0.12 wrote it bare).
  sed -e 's|^espalier-security\.md: `FAIL` (any P0/P1) / `PASS_WITH_FIXES` (only P2/P3)\.) The$|`espalier/skills/espalier-security/SKILL.md`: `FAIL` (any P0/P1) /\n`PASS_WITH_FIXES` (only P2/P3).) The|' \
      "$REVIEWER" > "$REVIEWER.tmp" && mv "$REVIEWER.tmp" "$REVIEWER"
  log "patched $REVIEWER: full espalier-security citation path (no-op if already prefixed)"
fi

# --- Patch C: espalier-coding SKILL.md -----------------------------------------
if ! grep -qF -- '## Solution Selection (keep it lean)' "$CODING"; then
  backup_once "$CODING"
  # C1: replace the duplicated Before-Writing steps with the canonical pointer,
  # then append the Solution Selection summary section (both from the template).
  awk '
    /^1\. Identify which layer\(s\) this change touches/ {skip=1}
    skip && /^4\. Follow the template structure exactly/ {
      print "The canonical pre-coding sequence (identify layer → read spec → find 1-2"
      print "reference files → follow the template exactly → climb the Solution Selection"
      print "Ladder) lives in `espalier/agents/harness-coder.md` (\"Before Writing ANY"
      print "Code\") — follow it from there; it is deliberately not restated here so the two"
      print "files cannot drift. This skill adds the project-specific parts: the Layer"
      print "Specs map and the Implementation Checklist above."
      skip=0; next
    }
    skip {next}
    {print}
  ' "$CODING" > "$CODING.tmp" && mv "$CODING.tmp" "$CODING"
  # NB: dot wildcards for the parens — awk -v strips backslash escapes, so an
  # escaped-paren regex would turn into a grouping metachar and never match.
  echo "" >> "$CODING"
  extract_span "$CODING_TPL" '^## Solution Selection .keep it lean.' '^## Before Writing Code' >> "$CODING"
  log "patched $CODING: Before-Writing pointer + Solution Selection summary"
fi

# --- Patch D: espalier-review SKILL.md ------------------------------------------
if ! grep -qF -- 'Gate (pass condition)' "$REVIEW"; then
  backup_once "$REVIEW"
  awk '
    {print}
    /that gate the start of implementation\.$/ && !done {
      print "- **Gate (pass condition):** zero P0/P1 findings against the current plan —"
      print "  P2/P3 are recorded, never blocking. On a non-pass, the plan is revised and"
      print "  re-reviewed; round counting and escalation are owned by pipeline Stage 2"
      print "  (`max-req-rounds`), not this skill."
      done=1
    }
  ' "$REVIEW" > "$REVIEW.tmp" && mv "$REVIEW.tmp" "$REVIEW"
  log "patched $REVIEW: + plan-review pass condition"
fi
if ! grep -qF -- 'Leanness:' "$REVIEW"; then
  backup_once "$REVIEW"
  awk '
    {print}
    /^- \[ \] Completeness: Edge cases handled\?$/ && !done {
      print "- [ ] Leanness: nothing built beyond the requirement (no speculative"
      print "      abstraction/config); no NEW dependency where stdlib, a native feature, or"
      print "      an installed dependency covers it. Advisory P2/P3 except the new-dependency"
      print "      P1 — canonical rules in `espalier/agents/harness-reviewer.md` (Minimalism"
      print "      Review). Never flag a construct the rules/specs mandate."
      done=1
    }
  ' "$REVIEW" > "$REVIEW.tmp" && mv "$REVIEW.tmp" "$REVIEW"
  log "patched $REVIEW: + Leanness checklist item"
fi
if ! grep -qF -- '(advisory) Minimalism reviews' "$REVIEW"; then
  backup_once "$REVIEW"
  sed -e 's|^  Runtime-Surface and Production-Readiness reviews and writes `review-record\.md`\.$|  Runtime-Surface, Production-Readiness, and (advisory) Minimalism reviews and\n  writes `review-record.md`.|' \
      "$REVIEW" > "$REVIEW.tmp" && mv "$REVIEW.tmp" "$REVIEW"
  log "patched $REVIEW: panel description names the Minimalism review (no-op if custom)"
fi

# --- Verify -------------------------------------------------------------------
pass=0; fail=0
check() {
  if grep -qF -- "$2" "$1"; then pass=$((pass+1)); echo "  ✓ $1: $3"
  else fail=$((fail+1)); echo "  ✗ $1: $3"; fi
}
log "verification:"
check "$CODER"    '## Solution Selection Ladder'            "ladder section"
check "$CODER"    'Climb the Solution Selection Ladder'     "ladder checklist step"
check "$CODER"    'conventions first, correctness'           "governing rule text"
check "$REVIEWER" '## Minimalism Review'                    "minimalism section"
check "$REVIEWER" 'Run the **Minimalism Review**'           "process step"
check "$REVIEWER" '- Minimalism: {lean / N advisory notes}' "summary line"
check "$REVIEWER" 'and `p1=` the number of P1 rows'         "p1= binding"
check "$REVIEWER" 'unbounded fan-out (N calls in a loop)'   "fan-out P1 bullet"
check "$REVIEWER" 'File a minimalism finding above P2'      "must-not bullet"
check "$CODING"   '## Solution Selection (keep it lean)'    "lean summary section"
check "$CODING"   'canonical pre-coding sequence'           "before-writing pointer"
check "$REVIEW"   'Gate (pass condition)'                   "plan-review pass condition"
check "$REVIEW"   'Leanness:'                               "leanness checklist"
log "$pass passed, $fail failed"
[ "$fail" -eq 0 ] || die "verification failed — inspect the ✗ lines; backups at <file>.pre-v0.13.bak."
log "done. Backups: <file>.pre-v0.13.bak. Review with: git diff"
