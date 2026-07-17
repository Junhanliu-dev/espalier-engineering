#!/bin/bash
# Migrate a v0.13.0 Espalier install to v0.13.1.
#
# v0.13.1 is the post-release polish round on the v0.13.0 minimalism release —
# the three residuals the v0.13.0 quality report named. No gate math, sentinel
# vocabulary, round cap, or review dimension changes; this sharpens what
# v0.13.0 already mandates.
#
# Files patched (backed up to <file>.pre-v0.13.1.bak):
#   espalier/skills/espalier-coding/SKILL.md  + "## How This Skill Applies by
#       Stage" — the stage-conditional guidance the frontmatter always promised
#       (Stage 3 implementation / Stage 5 testing mode / Stage 4-6 fix rounds),
#       including fix-round findings-only scope and "a test-only dependency is
#       still a NEW dependency".
#   espalier/agents/harness-reviewer.md       + the Stage 6 Security Abuse-Test
#       Coverage duty (shipped v0.9.0 as a section) becomes numbered Review
#       Process step 7, explicitly conditional — skipped on code-review rounds;
#       "Produce findings" renumbers to step 8. The duty itself is unchanged.
#   espalier/skills/espalier-review/SKILL.md  + the code-review loop gains the
#       Gate line its plan-review loop got in v0.13.0: PASS/PASS_WITH_FIXES
#       with p0=0 p1=0, P2/P3 advisory, rounds owned by pipeline Stage 4
#       (max-code-rounds).
#
# The touched files are PER-PROJECT (placeholder-substituted or scout-filled at
# init), so this migration is SURGICAL — anchored inserts and one line
# replacement, never a template overwrite. The By-Stage section body is
# extracted from the v0.13.1 plugin template at runtime (it is
# placeholder-free), so the script cannot drift from the template it installs.
# The anchors hold on both fresh v0.13.0 installs and installs migrated from
# v0.12.0 (verified against both shapes).
#
# NOT migrated (fresh-install only, cosmetic): the "{e.g., ...}" illustration
# under the espalier-coding Implementation Checklist — that block is an
# authoring hint for the init scout; an existing install's checklist was
# already scout-filled, so the hint has nothing to illustrate there.
#
# Usage:
#   bash migrate-v0.13.0-to-v0.13.1.sh [--dry-run] [--yes] [--plugin-dir=<path>]

set -u

DRY_RUN=no
SKIP_PROMPT=no
PLUGIN_DIR="${ESPALIER_PLUGIN_DIR:-}"

for arg in "$@"; do
  case "$arg" in
    --dry-run)      DRY_RUN=yes ;;
    --yes)          SKIP_PROMPT=yes ;;
    --plugin-dir=*) PLUGIN_DIR="${arg#--plugin-dir=}" ;;
    -h|--help)      sed -n '2,39p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown flag: $arg (use --help)" >&2; exit 2 ;;
  esac
done

log() { echo "[migrate v0.13.0→v0.13.1] $*"; }
die() { echo "[migrate v0.13.0→v0.13.1] ERROR: $*" >&2; exit 1; }

[ -d espalier ] || die "no espalier/ dir — run from the target project root."

# --- Locate plugin templates -------------------------------------------------
if [ -z "$PLUGIN_DIR" ]; then
  _self_root="$(cd "$(dirname "$0")/.." && pwd)"
  [ -d "$_self_root/skills/espalier-init/templates/agents" ] && PLUGIN_DIR="$_self_root"
fi
[ -n "$PLUGIN_DIR" ] || die "cannot locate the plugin. Pass --plugin-dir=<espalier-engineering root>."
TPL="$PLUGIN_DIR/skills/espalier-init/templates"
REVIEWER_TPL="$TPL/agents/harness-reviewer.md"
CODING_TPL="$TPL/skills/espalier-coding.md"
REVIEW_TPL="$TPL/skills/espalier-review.md"
for f in "$REVIEWER_TPL" "$CODING_TPL" "$REVIEW_TPL"; do
  [ -f "$f" ] || die "plugin dir $PLUGIN_DIR is missing template $f."
done

# The templates must actually be v0.13.1 — otherwise a stale plugin would
# "migrate" the install to nothing.
grep -qF -- '## How This Skill Applies by Stage' "$CODING_TPL" || \
  die "template at $PLUGIN_DIR is not v0.13.1 (coding template lacks the By-Stage section). Update the plugin first."
grep -qF -- 'run the **Security Abuse-Test Coverage**' "$REVIEWER_TPL" || \
  die "template at $PLUGIN_DIR is not v0.13.1 (reviewer template lacks the step-7 abuse-test line). Update the plugin first."
grep -qF -- 'max-code-rounds' "$REVIEW_TPL" || \
  die "template at $PLUGIN_DIR is not v0.13.1 (review template lacks the code-review Gate line). Update the plugin first."

CODING="espalier/skills/espalier-coding/SKILL.md"
REVIEWER="espalier/agents/harness-reviewer.md"
REVIEW="espalier/skills/espalier-review/SKILL.md"
for f in "$CODING" "$REVIEWER" "$REVIEW"; do
  [ -f "$f" ] || die "$f not found — is this a v0.13.0 install? Run the earlier chain steps first."
done

# --- Prerequisite: the install must be v0.13.0 --------------------------------
# (same markers the espalier-migrate chain uses for v0.13.0 detection)
grep -qF -- '## Minimalism Review' "$REVIEWER" || \
  die "install is pre-v0.13.0 (reviewer lacks the Minimalism Review) — run migrate-v0.12.0-to-v0.13.0.sh first."
grep -qF -- '## Solution Selection (keep it lean)' "$CODING" || \
  die "install is pre-v0.13.0 (coding skill lacks the Solution Selection summary) — run migrate-v0.12.0-to-v0.13.0.sh first."
grep -qF -- 'Gate (pass condition)' "$REVIEW" || \
  die "install is pre-v0.13.0 (review skill lacks the plan-review gate) — run migrate-v0.12.0-to-v0.13.0.sh first."

# --- Idempotency: already migrated? ------------------------------------------
if grep -qF -- '## How This Skill Applies by Stage' "$CODING" \
   && grep -qF -- 'run the **Security Abuse-Test Coverage**' "$REVIEWER" \
   && grep -qF -- 'max-code-rounds' "$REVIEW"; then
  log "already at v0.13.1 (all three markers present). Nothing to do."
  exit 0
fi

# --- Plan ----------------------------------------------------------------------
log "will patch (surgical, anchored):"
grep -qF -- '## How This Skill Applies by Stage' "$CODING" || \
  log "  $CODING: + How This Skill Applies by Stage section"
grep -qF -- 'run the **Security Abuse-Test Coverage**' "$REVIEWER" || \
  log "  $REVIEWER: + abuse-test coverage as Review Process step 7 (findings -> 8)"
grep -qF -- 'max-code-rounds' "$REVIEW" || \
  log "  $REVIEW: + code-review Gate (pass condition) line"

if [ "$DRY_RUN" = yes ]; then
  log "dry-run: no files changed."
  exit 0
fi
if [ "$SKIP_PROMPT" != yes ]; then
  printf '[migrate v0.13.0→v0.13.1] proceed? [y/N] '
  read -r reply
  case "$reply" in y|Y|yes|YES) ;; *) log "aborted."; exit 0 ;; esac
fi

# --- Helpers -----------------------------------------------------------------
# extract_span <file> <start-regex> <end-regex>  — prints lines from start
# (inclusive) to end (exclusive).
extract_span() {
  awk -v s="$2" -v e="$3" '$0 ~ s {on=1} on && $0 ~ e && $0 !~ s {exit} on {print}' "$1"
}
backup_once() { [ -f "$1.pre-v0.13.1.bak" ] || cp "$1" "$1.pre-v0.13.1.bak"; }

# --- Patch A: espalier-coding SKILL.md — By-Stage section ----------------------
if ! grep -qF -- '## How This Skill Applies by Stage' "$CODING"; then
  backup_once "$CODING"
  # Insert the section (from the template) before "## Solution Selection (keep
  # it lean)". Dot wildcards for the parens in the -v span args — awk -v strips
  # backslash escapes (same caveat as the v0.13.0 script).
  extract_span "$CODING_TPL" '^## How This Skill Applies by Stage' '^## Solution Selection .keep it lean.' > /tmp/espalier-bystage.$$
  awk -v ins="/tmp/espalier-bystage.$$" '
    /^## Solution Selection \(keep it lean\)/ && !done {
      while ((getline line < ins) > 0) print line
      close(ins); done=1
    }
    {print}
  ' "$CODING" > "$CODING.tmp" && mv "$CODING.tmp" "$CODING"
  rm -f /tmp/espalier-bystage.$$
  log "patched $CODING: + How This Skill Applies by Stage"
fi

# --- Patch B: harness-reviewer.md — abuse-test step 7, findings -> 8 -----------
# Anchor note: a fresh v0.13.0 install has "7. Produce findings..." from the
# template; a v0.12-migrated install has the same line spliced in by
# migrate-v0.12.0-to-v0.13.0.sh Patch B2. Both shapes match here.
if ! grep -qF -- 'run the **Security Abuse-Test Coverage**' "$REVIEWER"; then
  backup_once "$REVIEWER"
  awk '
    /^7\. Produce findings in the required format/ && !done {
      print "7. Test-review rounds only (Stage 6): run the **Security Abuse-Test Coverage**"
      print "   check (see section below) — every contracted security-sensitive field needs"
      print "   its passing negative test; a gap is a P0 back to Stage 5. Skip this step on"
      print "   code-review rounds."
      print "8. Produce findings in the required format"
      done=1; next
    }
    {print}
  ' "$REVIEWER" > "$REVIEWER.tmp" && mv "$REVIEWER.tmp" "$REVIEWER"
  log "patched $REVIEWER: abuse-test coverage as step 7; findings -> step 8"
fi

# --- Patch C: espalier-review SKILL.md — code-review Gate line -----------------
# Anchor note: the Code Review loop's "- **Who:** `harness-reviewer`, ..." line
# is identical in fresh v0.13.0 installs and v0.12-migrated ones (the v0.13.0
# migration never touched it). The plan-review loop's Who line reads "runs
# inline" and cannot collide.
if ! grep -qF -- 'max-code-rounds' "$REVIEW"; then
  backup_once "$REVIEW"
  awk '
    /^- \*\*Who:\*\* `harness-reviewer`, re-spawned each fix round until the verdict is clean\.$/ && !done {
      print "- **Gate (pass condition):** verdict `PASS`/`PASS_WITH_FIXES` with `p0=0 p1=0`"
      print "  on the sentinel — P2/P3 (minimalism advisories included) are recorded, never"
      print "  blocking. On a non-pass, the coder fixes and the change is re-reviewed; round"
      print "  counting and escalation are owned by pipeline Stage 4 (`max-code-rounds`),"
      print "  not this skill."
      done=1
    }
    {print}
  ' "$REVIEW" > "$REVIEW.tmp" && mv "$REVIEW.tmp" "$REVIEW"
  log "patched $REVIEW: + code-review Gate line"
fi

# --- Verify -------------------------------------------------------------------
pass=0; fail=0
check() {
  if grep -qF -- "$2" "$1"; then pass=$((pass+1)); echo "  ✓ $1: $3"
  else fail=$((fail+1)); echo "  ✗ $1: $3"; fi
}
check_absent() {
  if grep -qF -- "$2" "$1"; then fail=$((fail+1)); echo "  ✗ $1: $3"
  else pass=$((pass+1)); echo "  ✓ $1: $3"; fi
}
log "verification:"
check        "$CODING"   '## How This Skill Applies by Stage'             "by-stage section"
check        "$CODING"   'Stage 5 — testing mode.'                        "stage-5 guidance"
check        "$CODING"   'Fix rounds — Stage 4/6 re-spawns.'              "fix-round guidance"
check        "$REVIEWER" 'run the **Security Abuse-Test Coverage**'       "step-7 abuse-test line"
check        "$REVIEWER" '8. Produce findings in the required format'     "findings renumbered to 8"
check_absent "$REVIEWER" '7. Produce findings in the required format'     "old step-7 findings line gone"
check        "$REVIEW"   'max-code-rounds'                                "code-review gate line"
check        "$REVIEW"   'p0=0 p1=0'                                      "gate sentinel condition"
log "$pass passed, $fail failed"
[ "$fail" -eq 0 ] || die "verification failed — inspect the ✗ lines; backups at <file>.pre-v0.13.1.bak."
log "done. Backups: <file>.pre-v0.13.1.bak. Review with: git diff"
