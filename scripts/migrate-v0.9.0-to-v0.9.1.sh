#!/bin/bash
# Migrate an Espalier v0.9.0 target repo to v0.9.1.
#
# Run from the TARGET project root. Idempotent. Safe to re-run.
# Use --dry-run to preview before applying.
#
# v0.9.1 makes the review-round + rollback escalation caps configurable. They
# used to be hardcoded prose ("Max 2 P0 rounds", "Max 3 review rounds", ">3
# rollbacks") in the pipeline templates; they now live in a tracked config file
# the orchestrator reads at runtime:
#
#   espalier/.espalier-config   (max-req-rounds / max-code-rounds /
#                                max-test-rounds / max-rollbacks — all default 3)
#
# This migration:
#   1. Creates espalier/.espalier-config if absent (extracted from the plugin's
#      bootstrap so the two can't drift). A user's existing file is preserved.
#   2. Refreshes the three PURE-COPY pipeline files from the plugin so their prose
#      references the config keys (otherwise the old "Max 2" text ignores it):
#        espalier/pipeline.md
#        espalier/skills/espalier/SKILL.md
#        espalier/skills/espalier-fix/SKILL.md
#      A customised file is backed up to <file>.pre-v0.9.1.bak before overwrite.
#
# Non-breaking: the new prose falls back to 3 when a key is absent.
#
# Usage: bash migrate-v0.9.0-to-v0.9.1.sh [--dry-run] [--yes] [--plugin-dir=<path>]

set -u

DRY_RUN=no
SKIP_PROMPT=no
PLUGIN_DIR="${ESPALIER_PLUGIN_DIR:-${HARNESS_PLUGIN_DIR:-}}"
for arg in "$@"; do
  case "$arg" in
    --dry-run)      DRY_RUN=yes ;;
    --yes)          SKIP_PROMPT=yes ;;
    --plugin-dir=*) PLUGIN_DIR="${arg#--plugin-dir=}" ;;
    -h|--help)      sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown flag: $arg (use --help)" >&2; exit 2 ;;
  esac
done

log() { echo "[migrate-v0.9.1] $*"; }

CONFIG="espalier/.espalier-config"
PIPELINE="espalier/pipeline.md"
ORCH="espalier/skills/espalier/SKILL.md"
FIX="espalier/skills/espalier-fix/SKILL.md"

# --- Preflight (target) -----------------------------------------------------
if [ -d "harness" ] && [ ! -d "espalier" ]; then
  echo "ERROR: pre-v0.4 install detected (harness/ directory)." >&2
  echo "Run /espalier-migrate first to apply the v0.1->v0.8 chain, then re-run." >&2
  exit 1
fi
if [ ! -f "$PIPELINE" ]; then
  echo "ERROR: $PIPELINE not found — run this from the target project root." >&2
  exit 1
fi

# --- Locate the plugin (must contain scripts/bootstrap-espalier.sh) ----------
if [ -z "$PLUGIN_DIR" ] || [ ! -f "$PLUGIN_DIR/scripts/bootstrap-espalier.sh" ]; then
  PLUGIN_DIR=""
  # search upward from this script's own location
  self_dir="$(cd "$(dirname "$0")" && pwd)"
  candidate="$(cd "$self_dir/.." 2>/dev/null && pwd)"
  if [ -n "$candidate" ] && [ -f "$candidate/scripts/bootstrap-espalier.sh" ]; then
    PLUGIN_DIR="$candidate"
  fi
fi
if [ -z "$PLUGIN_DIR" ] || [ ! -f "$PLUGIN_DIR/scripts/bootstrap-espalier.sh" ]; then
  echo "ERROR: couldn't find the Espalier plugin (scripts/bootstrap-espalier.sh)." >&2
  echo "Pass --plugin-dir=<path to espalier-engineering checkout>." >&2
  exit 1
fi
BOOTSTRAP="$PLUGIN_DIR/scripts/bootstrap-espalier.sh"
PLUGIN_INIT="$PLUGIN_DIR/skills/espalier-init"
SRC_PIPELINE="$PLUGIN_INIT/templates/pipeline.md"
SRC_ORCH="$PLUGIN_INIT/templates/skills/espalier.md"
SRC_FIX="$PLUGIN_INIT/templates/skills/espalier-fix.md"

# Plugin must be v0.9.1+ (its pipeline template references the config key).
if ! grep -qF "max-code-rounds" "$SRC_PIPELINE" 2>/dev/null; then
  echo "ERROR: plugin at $PLUGIN_DIR is pre-v0.9.1 (no 'max-code-rounds' in pipeline.md)." >&2
  echo "Update the plugin (or pass --plugin-dir to a v0.9.1+ checkout)." >&2
  exit 1
fi
for f in "$SRC_ORCH" "$SRC_FIX"; do
  if [ ! -f "$f" ]; then
    echo "ERROR: plugin template missing: $f" >&2
    exit 1
  fi
done

# --- Extract the canonical .espalier-config body from the plugin bootstrap ---
# (between the `<< 'ESPALIERCFG'` heredoc markers — single source of truth.)
config_body() {
  awk "/<< 'ESPALIERCFG'/{f=1;next} /^ESPALIERCFG/{f=0} f" "$BOOTSTRAP"
}

# --- Idempotency ------------------------------------------------------------
CONFIG_DONE=no
PROSE_DONE=no
[ -f "$CONFIG" ] && CONFIG_DONE=yes
grep -qF "max-code-rounds" "$PIPELINE" 2>/dev/null && PROSE_DONE=yes

if [ "$CONFIG_DONE" = yes ] && [ "$PROSE_DONE" = yes ]; then
  log "Already at v0.9.1 — .espalier-config present and pipeline prose references it. Nothing to do."
  exit 0
fi

# --- Dry run ----------------------------------------------------------------
if [ "$DRY_RUN" = "yes" ]; then
  if [ "$CONFIG_DONE" = no ]; then
    log "[dry-run] would create $CONFIG:"
    config_body | sed 's/^/  | /'
  else
    log "[dry-run] $CONFIG already exists — preserve."
  fi
  for pair in "$PIPELINE:$SRC_PIPELINE" "$ORCH:$SRC_ORCH" "$FIX:$SRC_FIX"; do
    dst="${pair%%:*}"; src="${pair##*:}"
    if [ ! -f "$dst" ]; then
      log "[dry-run] $dst missing — would create from plugin."
    elif cmp -s "$dst" "$src"; then
      log "[dry-run] $dst already matches plugin — skip."
    else
      log "[dry-run] would back up $dst -> $dst.pre-v0.9.1.bak and refresh from plugin."
    fi
  done
  exit 0
fi

# --- Confirm ----------------------------------------------------------------
if [ "$SKIP_PROMPT" != "yes" ]; then
  ANS=""
  printf 'Apply the v0.9.1 configurable-caps upgrade (write .espalier-config + refresh 3 pipeline files)? [y/N] '
  read -r ANS || true
  case "$ANS" in
    y|Y|yes|YES) ;;
    *) echo "Aborted — nothing changed."; exit 0 ;;
  esac
fi

# --- Apply ------------------------------------------------------------------
if [ "$CONFIG_DONE" = no ]; then
  config_body > "$CONFIG"
  log "Wrote $CONFIG (review-round + rollback caps, default 3)"
else
  log "$CONFIG already exists — preserved."
fi

refresh_file() {
  _dst="$1"; _src="$2"
  if [ -f "$_dst" ] && ! cmp -s "$_dst" "$_src"; then
    cp "$_dst" "$_dst.pre-v0.9.1.bak"
    log "Backed up customised $_dst -> $_dst.pre-v0.9.1.bak"
  fi
  mkdir -p "$(dirname "$_dst")"
  cp "$_src" "$_dst"
  log "Refreshed $_dst from plugin"
}
refresh_file "$PIPELINE" "$SRC_PIPELINE"
refresh_file "$ORCH" "$SRC_ORCH"
refresh_file "$FIX" "$SRC_FIX"

# --- Verify -----------------------------------------------------------------
PASS=0; FAIL=0
check() { if eval "$2"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "ERROR: $1" >&2; fi; }
check "$CONFIG missing"                      "[ -f '$CONFIG' ]"
check "max-code-rounds not readable from config" "grep -q '^max-code-rounds:' '$CONFIG'"
check "pipeline.md does not reference the config" "grep -qF 'max-code-rounds' '$PIPELINE'"
check "orchestrator SKILL.md does not reference the config" "grep -qF 'max-code-rounds' '$ORCH'"
check "fix SKILL.md does not reference the config" "grep -qF 'max-test-rounds' '$FIX'"
log "Verification: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
log "Done. Tune caps by editing $CONFIG (values survive re-bootstrap)."
exit 0
