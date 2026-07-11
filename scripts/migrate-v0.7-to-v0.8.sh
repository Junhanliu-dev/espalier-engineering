#!/bin/bash
# Migrate an Espalier v0.7.x target repo to v0.8.0 (requirements approval gate).
#
# Run from the TARGET project root. Idempotent. Safe to re-run.
# Use --dry-run to preview every change before applying.
#
# v0.8.0 adds a BLOCKING requirements approval gate to both pipelines. Before
# v0.8, Stage 1 (requirements) → Stage 2 (review) → Stage 3 (coding) chained
# automatically, so coding began the moment the requirement doc existed. v0.8
# stops after the requirement is written + reviewed and waits for explicit user
# sign-off (Approve / Edit / Abort) before any code is written. On a no-TTY run
# the gate auto-approves, so unattended pipelines never hang. This migration:
#   1. Backs up any user-customised pipeline file (diff vs new v0.8 template)
#      to <file>.pre-v0.8.bak, so customisations are recoverable.
#   2. Runs bootstrap-espalier.sh --force — refreshes the three changed
#      pure-copy pipeline files (pipeline.md, espalier, espalier-fix).
#   3. Verifies the approval-gate text landed.
#
# What this script does NOT do:
#   - Touch espalier/rules/*, espalier/wiki/*, espalier/changes/*, or any
#     LLM-substituted file (harness-coder.md, harness-reviewer.md,
#     pre-push-gate.sh, espalier-review.md) — none of them changed in v0.8.
#   - Re-gate any in-flight feat or fix. v0.8 only affects new pipeline
#     invocations.
#
# Usage:
#   bash migrate-v0.7-to-v0.8.sh [--dry-run] [--yes] [--plugin-dir=<path>]

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
      sed -n '2,29p' "$0"
      exit 0
      ;;
    *)
      echo "ERROR: unknown flag: $arg (use --help)" >&2
      exit 2
      ;;
  esac
done

log() { echo "[migrate v0.7→v0.8] $*"; }

# --- Preflight ---------------------------------------------------------------

if [ -d "harness" ] && [ ! -d "espalier" ]; then
  echo "ERROR: this is a pre-v0.4 install (harness/ present, no espalier/)." >&2
  echo "Run the earlier migrations first (via /espalier-migrate)." >&2
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
  echo "Run /espalier-migrate to apply the earlier upgrades first." >&2
  exit 1
fi

# Already-v0.8 detector — the approval gate is wired into the espalier skill.
if grep -q "Requirements Approval Gate" espalier/skills/espalier/SKILL.md 2>/dev/null; then
  echo "Already on v0.8.0 (requirements approval gate present)."
  echo "Nothing to do."
  exit 0
fi

# Locate the plugin root (must contain scripts/bootstrap-espalier.sh).
if [ -z "$PLUGIN_DIR" ] || [ ! -f "$PLUGIN_DIR/scripts/bootstrap-espalier.sh" ]; then
  PLUGIN_DIR=""
  for candidate in \
    "$HOME/.claude/plugins/espalier-engineering" \
    "$HOME/.claude/plugins/espalier" \
    "$HOME/repos/espalier-engineering"; do
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

# Sanity-check the plugin actually carries the v0.8 template before we touch anything.
if ! grep -q "Requirements Approval Gate" "$PLUGIN_INIT/templates/skills/espalier.md" 2>/dev/null; then
  echo "ERROR: plugin at $PLUGIN_DIR is pre-v0.8 (no approval gate in templates/skills/espalier.md)." >&2
  echo "Update the plugin to v0.8+ (or pass --plugin-dir to a v0.8 checkout)." >&2
  exit 1
fi

cat << EOF

Espalier requirements approval gate upgrade (v0.7.x → v0.8.0)

Plan:
  1. Backup-on-diff: any customised pipeline file → <file>.pre-v0.8.bak
  2. bootstrap-espalier.sh --force  (merge-decision=$DECISION, doctor-cadence=$DOCTOR_CADENCE)
       → refreshed pipeline.md / espalier / espalier-fix (approval gate added)
  3. Verify the approval-gate text landed

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
# bootstrap --force will overwrite the pure-copy pipeline files. If a user (or a
# prior LLM run) customised any of them, the customisation is lost. For each file
# we compare current content to the v0.8 template; if they differ, we copy the
# current file aside to <file>.pre-v0.8.bak BEFORE bootstrap runs. If they are
# already identical, no backup is needed.

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
  local backup="${current}.pre-v0.8.bak"
  if [ "$DRY_RUN" = "yes" ]; then
    echo "  [dry-run] backup: $current → $backup"
  else
    cp "$current" "$backup"
    echo "  backed up: $current → $backup"
  fi
  BACKUPS_MADE="${BACKUPS_MADE}${backup}
"
}

backup_if_differs "espalier/pipeline.md"                  "$PLUGIN_INIT/templates/pipeline.md"
backup_if_differs "espalier/skills/espalier/SKILL.md"     "$PLUGIN_INIT/templates/skills/espalier.md"
backup_if_differs "espalier/skills/espalier-fix/SKILL.md" "$PLUGIN_INIT/templates/skills/espalier-fix.md"

# --- Step 2: bootstrap --force (mechanical 100%) -----------------------------
#
# Bootstrap's pure-copy stage re-copies pipeline.md, espalier, espalier-fix
# (among others) from the plugin templates — the v0.8 approval gate rides along.

log "Step 2: bootstrap-espalier.sh --force"
BOOT_FLAGS="--force --project-dir=. --plugin-dir=$PLUGIN_INIT --merge-decision=$DECISION --doctor-cadence=$DOCTOR_CADENCE --yes"
if [ "$DRY_RUN" = "yes" ]; then
  bash "$BOOTSTRAP" $BOOT_FLAGS --dry-run
else
  _boot_log=$(mktemp)
  bash "$BOOTSTRAP" $BOOT_FLAGS > "$_boot_log" 2>&1
  _boot_exit=$?
  cat "$_boot_log"
  if [ "$_boot_exit" -ne 0 ]; then
    # A failure AFTER wiring (the "Validation: N/M FAILED" line was printed)
    # means stages 1-10 completed and only the final health check is red —
    # expected MID-CHAIN when the plugin is newer than this migration's target
    # version (later-version artifacts are not installed yet; the next
    # migration in the chain installs them, and the chain's final step
    # re-validates everything). Anything else is a real bootstrap failure.
    if grep -qE 'Validation: [0-9]+/[0-9]+ FAILED' "$_boot_log"; then
      echo "WARN: bootstrap health check reports missing artifacts — expected mid-chain" >&2
      echo "      with a newer plugin; continuing (a later migration completes them)." >&2
    else
      echo "ERROR: bootstrap-espalier.sh failed — see output above. Aborting." >&2
      rm -f "$_boot_log"
      exit 1
    fi
  fi
  rm -f "$_boot_log"
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
  check "espalier skill has approval gate"     "grep -q 'Requirements Approval Gate' espalier/skills/espalier/SKILL.md"
  check "espalier skill carves Stage 2→3"      "grep -q 'Stage 2 → Stage 3' espalier/skills/espalier/SKILL.md"
  check "espalier-fix has approval gate"        "grep -q 'Requirements Approval Gate' espalier/skills/espalier-fix/SKILL.md"
  check "pipeline.md Stage 2 blocking checkpoint" "grep -q 'Human checkpoint (BLOCKING)' espalier/pipeline.md"
  echo ""
  echo "  Verification: $pass passed, $fail failed"
  [ "$fail" -gt 0 ] && exit 1
fi

# --- Summary -----------------------------------------------------------------

echo ""
echo "Upgrade complete. v0.8 adds a requirements approval gate (interactive-only)."
echo "After the requirement is written + reviewed, the pipeline now STOPS and"
echo "waits for your Approve / Edit / Abort before any code is written."
echo "No-TTY runs auto-approve, so unattended pipelines never hang."
echo ""

if [ -n "$BACKUPS_MADE" ]; then
  echo "Backups written (pre-existing customisations preserved):"
  printf '%s' "$BACKUPS_MADE" | sed 's/^/  - /'
  echo ""
  echo "Diff each backup against the live file to re-apply any customisation:"
  echo "  diff espalier/<file>.pre-v0.8.bak espalier/<file>"
  echo ""
fi

echo "Next steps:"
echo "  1. Review the diff: git diff && git status"
echo "  2. Commit:"
echo "       git add -A"
echo "       git commit -m 'chore: upgrade Espalier to v0.8.0 (requirements approval gate)'"
echo "  3. Try it: run /espalier on a new feat — after Stage 2 it will pause for"
echo "     your sign-off before coding begins."
