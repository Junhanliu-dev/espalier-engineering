#!/bin/bash
# Migrate an Espalier v0.5.x target repo to v0.6.0 (Stage 1 grill).
#
# Run from the TARGET project root. Idempotent. Safe to re-run.
# Use --dry-run to preview every change before applying.
#
# v0.6.0 adds the espalier-grill skill — an adaptive Stage 1 interrogation
# that pressure-tests requirements (feat lane) and root-cause diagnoses
# (fix lane) before downstream stages run. This migration:
#   1. Backs up any user-customised pipeline skill (diff vs new v0.6
#      template) to <file>.pre-v0.6.bak, so customisations are recoverable.
#   2. Runs bootstrap-espalier.sh --force — creates the espalier-grill
#      skill directory, copies the new SKILL.md, refreshes the four
#      changed pipeline skills (pipeline.md, espalier, espalier-fix,
#      espalier-requirements), and symlinks .claude/skills/espalier-grill.
#   3. Verifies the result.
#
# What this script does NOT do:
#   - Touch espalier/rules/*, espalier/wiki/*, espalier/changes/*, or any
#     LLM-substituted file (harness-coder.md, harness-reviewer.md,
#     pre-push-gate.sh, espalier-review.md) — none of them changed in v0.6.
#   - Re-grill any in-flight feat or fix. v0.6 only affects new pipeline
#     invocations.
#
# Usage:
#   bash migrate-v0.5-to-v0.6.sh [--dry-run] [--yes] [--plugin-dir=<path>]

set -u

DRY_RUN=no
SKIP_PROMPT=no
PLUGIN_DIR="${ESPALIER_PLUGIN_DIR:-${HARNESS_PLUGIN_DIR:-}}"

for arg in "$@"; do
  case "$arg" in
    --dry-run)            DRY_RUN=yes ;;
    --yes)                SKIP_PROMPT=yes ;;
    --plugin-dir=*)       PLUGIN_DIR="${arg#--plugin-dir=}" ;;
    -h|--help)
      sed -n '2,28p' "$0"
      exit 0
      ;;
    *)
      echo "ERROR: unknown flag: $arg (use --help)" >&2
      exit 2
      ;;
  esac
done

log() { echo "[migrate v0.5→v0.6] $*"; }

# --- Preflight ---------------------------------------------------------------

if [ -d "harness" ] && [ ! -d "espalier" ]; then
  echo "ERROR: this is a pre-v0.4 install (harness/ present, no espalier/)." >&2
  echo "Run the v0.3→v0.4 rename migration first (via /espalier-migrate)." >&2
  exit 1
fi

if [ ! -d "espalier" ]; then
  echo "ERROR: no espalier/ directory — not an Espalier install." >&2
  echo "Use /espalier-init to set up Espalier in a fresh project." >&2
  exit 1
fi

if [ ! -f "espalier/.merge-hook-decision" ]; then
  echo "ERROR: espalier/.merge-hook-decision missing — install looks incomplete." >&2
  echo "Re-run /espalier-init (or bootstrap-espalier.sh --force) to repair it first." >&2
  exit 1
fi

# v0.5.x prerequisites — doc-drift detection must be present.
if [ ! -f "espalier/hooks/drift-detect.sh" ] || [ ! -f "espalier/.doctor-cadence" ]; then
  echo "ERROR: install looks pre-v0.5 (drift hooks or .doctor-cadence missing)." >&2
  echo "Run /espalier-migrate to apply the v0.4→v0.5 upgrade first." >&2
  exit 1
fi

# Already-v0.6 detector — grill skill present AND wired into requirements.
if [ -f "espalier/skills/espalier-grill/SKILL.md" ] \
   && grep -q "Grill the requirement" espalier/skills/espalier-requirements/SKILL.md 2>/dev/null; then
  echo "Already on v0.6.0 (espalier-grill skill present + Stage 1 wired)."
  echo "Nothing to do."
  exit 0
fi

# Locate the plugin root (must contain scripts/bootstrap-espalier.sh).
if [ -z "$PLUGIN_DIR" ] || [ ! -f "$PLUGIN_DIR/scripts/bootstrap-espalier.sh" ]; then
  PLUGIN_DIR=""
  for candidate in \
    "$HOME/.claude/plugins/espalier-engineering" \
    "$HOME/.claude/plugins/espalier" \
    "$HOME/repos/espalier-engineering" \
    "$HOME/SBM_Projects/espalier-engineering"; do
    if [ -f "$candidate/scripts/bootstrap-espalier.sh" ]; then
      PLUGIN_DIR="$candidate"
      break
    fi
  done
fi

if [ -z "$PLUGIN_DIR" ] || [ ! -f "$PLUGIN_DIR/scripts/bootstrap-espalier.sh" ]; then
  echo "ERROR: couldn't find the Espalier plugin (scripts/bootstrap-espalier.sh)." >&2
  echo "Update the plugin first (/plugin update espalier-engineering), or pass" >&2
  echo "--plugin-dir=<path to espalier-engineering checkout>." >&2
  exit 1
fi

BOOTSTRAP="$PLUGIN_DIR/scripts/bootstrap-espalier.sh"
PLUGIN_INIT="$PLUGIN_DIR/skills/espalier-init"
DECISION=$(cat espalier/.merge-hook-decision 2>/dev/null)
DOCTOR_CADENCE=$(sed -n 's/^cadence: //p' espalier/.doctor-cadence 2>/dev/null)
[ -z "$DOCTOR_CADENCE" ] && DOCTOR_CADENCE=weekly

# Sanity-check the plugin actually contains v0.6 assets before we touch anything.
if [ ! -f "$PLUGIN_INIT/templates/skills/espalier-grill.md" ]; then
  echo "ERROR: plugin at $PLUGIN_DIR is pre-v0.6 (no templates/skills/espalier-grill.md)." >&2
  echo "Update the plugin to v0.6+ (or pass --plugin-dir to a v0.6 checkout)." >&2
  exit 1
fi

cat << EOF

Espalier Stage 1 grill upgrade (v0.5.x → v0.6.0)

Plan:
  1. Backup-on-diff: any user-customised pipeline skill → <file>.pre-v0.6.bak
  2. bootstrap-espalier.sh --force  (merge-decision=$DECISION, doctor-cadence=$DOCTOR_CADENCE)
       → new espalier-grill skill, refreshed pipeline / espalier /
         espalier-fix / espalier-requirements, .claude/skills/espalier-grill link
  3. Verify

Plugin: $PLUGIN_DIR
EOF

if [ "$DRY_RUN" = "yes" ]; then
  echo "Mode: DRY RUN (no changes will be written)"
elif [ "$SKIP_PROMPT" != "yes" ]; then
  printf 'Apply upgrade? [y/N]: '
  read -r confirm
  case "$confirm" in
    y|Y|yes) ;;
    *) echo "Cancelled."; exit 0 ;;
  esac
fi

# --- Step 1: backup-on-diff --------------------------------------------------
#
# bootstrap --force will overwrite the four pure-copy pipeline files. If a user
# (or a prior LLM run) customised any of them, the customisation is lost. For
# each file we compare current content to the v0.6 template; if they differ,
# we copy the current file aside to <file>.pre-v0.6.bak BEFORE bootstrap runs.
# If they are already identical (clean v0.5 install on a flat-pipeline skill
# that did not change in v0.6), no backup is needed.

log "Step 1: backup-on-diff for pure-copy pipeline files"
BACKUPS_MADE=""

backup_if_differs() {
  local current="$1"
  local new_template="$2"
  if [ ! -f "$current" ]; then
    return 0
  fi
  if [ ! -f "$new_template" ]; then
    echo "  WARN: plugin template missing: $new_template (skipping backup check)" >&2
    return 0
  fi
  if cmp -s "$current" "$new_template"; then
    echo "  unchanged: $current (no backup needed)"
    return 0
  fi
  local backup="${current}.pre-v0.6.bak"
  if [ "$DRY_RUN" = "yes" ]; then
    echo "  [dry-run] backup: $current → $backup"
  else
    cp "$current" "$backup"
    echo "  backed up: $current → $backup"
  fi
  BACKUPS_MADE="${BACKUPS_MADE}${backup}
"
}

backup_if_differs "espalier/pipeline.md"                                "$PLUGIN_INIT/templates/pipeline.md"
backup_if_differs "espalier/skills/espalier/SKILL.md"                   "$PLUGIN_INIT/templates/skills/espalier.md"
backup_if_differs "espalier/skills/espalier-fix/SKILL.md"               "$PLUGIN_INIT/templates/skills/espalier-fix.md"
backup_if_differs "espalier/skills/espalier-requirements/SKILL.md"      "$PLUGIN_INIT/templates/skills/espalier-requirements.md"

# --- Step 2: bootstrap --force (mechanical 100%) -----------------------------
#
# Bootstrap stages relevant to v0.6:
#   Stage 2: mkdir espalier/skills/espalier-grill
#   Stage 3: cp templates/skills/espalier-grill.md → espalier/skills/espalier-grill/SKILL.md
#            + refresh the four changed pure-copy files
#   Stage 5: symlink .claude/skills/espalier-grill → espalier/skills/espalier-grill

log "Step 2: bootstrap-espalier.sh --force"
BOOT_FLAGS="--force --project-dir=. --plugin-dir=$PLUGIN_INIT --merge-decision=$DECISION --doctor-cadence=$DOCTOR_CADENCE --yes"
if [ "$DRY_RUN" = "yes" ]; then
  bash "$BOOTSTRAP" $BOOT_FLAGS --dry-run
else
  if ! bash "$BOOTSTRAP" $BOOT_FLAGS; then
    echo "ERROR: bootstrap-espalier.sh failed — see output above. Aborting." >&2
    exit 1
  fi
fi

# --- Step 3: verification ----------------------------------------------------

log "Step 3: verification"
if [ "$DRY_RUN" = "yes" ]; then
  echo "(dry run — skipping verification)"
else
  pass=0; fail=0
  check() {
    if eval "$2" >/dev/null 2>&1; then pass=$((pass+1)); echo "  ✓ $1"
    else fail=$((fail+1)); echo "  ✗ $1"; fi
  }
  check "espalier-grill skill present"      "test -f espalier/skills/espalier-grill/SKILL.md"
  check ".claude/skills/espalier-grill link" "test -L .claude/skills/espalier-grill"
  check "espalier-requirements wires grill" "grep -q 'Grill the requirement' espalier/skills/espalier-requirements/SKILL.md"
  check "espalier-fix wires grill"          "grep -q 'Grill the diagnosis' espalier/skills/espalier-fix/SKILL.md"
  check "espalier-fix has --no-grill flag"  "grep -q 'no-grill' espalier/skills/espalier-fix/SKILL.md"
  check "espalier.md has flag parser"       "grep -q 'GRILL_DISABLED' espalier/skills/espalier/SKILL.md"
  check "pipeline.md refreshed"             "test -f espalier/pipeline.md"
  echo ""
  echo "  Verification: $pass passed, $fail failed"
fi

# --- Summary -----------------------------------------------------------------

echo ""
echo "Upgrade complete. v0.6 adds Stage 1 grilling (adaptive, on by default)."
echo "Per-run opt-out: pass --no-grill to /espalier or /espalier-fix."
echo ""

if [ -n "$BACKUPS_MADE" ]; then
  echo "Backups written (pre-existing customisations preserved):"
  printf '%s' "$BACKUPS_MADE" | sed 's/^/  - /'
  echo ""
  echo "Diff each backup against the live file to re-apply any customisation:"
  echo "  diff espalier/<file>.pre-v0.6.bak espalier/<file>"
  echo ""
fi

echo "Next steps:"
echo "  1. Review the diff: git diff && git status"
echo "  2. Commit:"
echo "       git add -A"
echo "       git commit -m 'chore: upgrade Espalier to v0.6.0 (Stage 1 grill)'"
echo "  3. Try it: run /espalier on a new feat — Stage 1 will grill the requirement."
echo "     Skip the grill for an invocation with the --no-grill flag."
