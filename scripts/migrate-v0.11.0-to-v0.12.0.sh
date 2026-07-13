#!/bin/bash
# Migrate a v0.11.0 Espalier install to v0.12.0.
#
# v0.12.0 adds the grill blind-spot pass (Step 1.5): Stage 1 grilling now
# cross-references the requirement against the project's own espalier/rules/ and
# espalier/wiki/ and surfaces a collision — a rule the requirement would violate,
# a capability the wiki already documents, an unstated downstream ripple — as a
# Stage 1 question, before any code is written.
#
# The change is confined to ONE file: the pure-copy pipeline skill
# espalier/skills/espalier-grill/SKILL.md. So this migration is a single
# backup-and-refresh of that file from the v0.12.0 template. It is a no-op on an
# install already carrying Step 1.5, and it never touches user-customised files
# (the grill skill is plugin-owned — a pure copy, never substituted).
#
# Usage:
#   bash migrate-v0.11.0-to-v0.12.0.sh [--dry-run] [--yes] [--plugin-dir=<path>]

set -u

DRY_RUN=no
SKIP_PROMPT=no
PLUGIN_DIR="${ESPALIER_PLUGIN_DIR:-}"

for arg in "$@"; do
  case "$arg" in
    --dry-run)      DRY_RUN=yes ;;
    --yes)          SKIP_PROMPT=yes ;;
    --plugin-dir=*) PLUGIN_DIR="${arg#--plugin-dir=}" ;;
    -h|--help)      sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown flag: $arg (use --help)" >&2; exit 2 ;;
  esac
done

log() { echo "[migrate v0.11.0→v0.12.0] $*"; }
die() { echo "[migrate v0.11.0→v0.12.0] ERROR: $*" >&2; exit 1; }

[ -d espalier ] || die "no espalier/ dir — run from the target project root."

# --- Locate plugin templates -------------------------------------------------
if [ -z "$PLUGIN_DIR" ]; then
  _self_root="$(cd "$(dirname "$0")/.." && pwd)"
  [ -d "$_self_root/skills/espalier-init/templates/skills" ] && PLUGIN_DIR="$_self_root"
fi
[ -n "$PLUGIN_DIR" ] || die "cannot locate the plugin. Pass --plugin-dir=<espalier-engineering root>."
TPL="$PLUGIN_DIR/skills/espalier-init"
GRILL_TPL="$TPL/templates/skills/espalier-grill.md"
[ -f "$GRILL_TPL" ] || die "plugin dir $PLUGIN_DIR has no grill template at $GRILL_TPL."

# The template must actually be v0.12.0 (carry Step 1.5) — otherwise a stale
# plugin would "migrate" the install straight back to pre-v0.12 behaviour.
grep -qF 'Step 1.5 — Blind-spot pass' "$GRILL_TPL" || \
  die "template at $PLUGIN_DIR is not v0.12.0 (grill template lacks Step 1.5). Update the plugin first."

GRILL="espalier/skills/espalier-grill/SKILL.md"

# --- Idempotency: already migrated? ------------------------------------------
if [ -f "$GRILL" ] && grep -qF 'Step 1.5 — Blind-spot pass' "$GRILL"; then
  log "already at v0.12.0 (grill skill carries Step 1.5). Nothing to do."
  exit 0
fi

if [ "$DRY_RUN" = yes ]; then
  log "DRY RUN — would:"
  if [ -f "$GRILL" ]; then
    log "  refresh $GRILL from the v0.12.0 template (backup .pre-v0.12.bak) — adds Step 1.5 blind-spot pass"
  else
    log "  create $GRILL from the v0.12.0 template (install had no grill skill — pre-v0.6?)"
    log "  NOTE: a pre-v0.6 install should run the full chain; this step only writes the grill skill."
  fi
  exit 0
fi

if [ "$SKIP_PROMPT" != yes ]; then
  printf "Apply the v0.12.0 migration (grill blind-spot pass — rules/wiki cross-check)? [y/N] "
  read -r reply
  case "$reply" in [yY]*) ;; *) echo "Aborted."; exit 0 ;; esac
fi

# --- Refresh the grill skill (pure copy) -------------------------------------
mkdir -p "$(dirname "$GRILL")"
if [ -f "$GRILL" ]; then
  cp "$GRILL" "$GRILL.pre-v0.12.bak"
  log "backed up -> $GRILL.pre-v0.12.bak"
fi
cp "$GRILL_TPL" "$GRILL"
log "refreshed $GRILL from the v0.12.0 template"

# --- Verification ------------------------------------------------------------
pass=0; fail=0
check() { if eval "$2" >/dev/null 2>&1; then pass=$((pass+1)); echo "  ✓ $1"; else fail=$((fail+1)); echo "  ✗ $1"; fi; }

log "verification"
check "grill skill has the Step 1.5 blind-spot pass" "grep -qF 'Step 1.5 — Blind-spot pass' '$GRILL'"
check "grill skill cross-checks espalier/rules"      "grep -qF 'espalier/rules/' '$GRILL'"
check "grill skill cross-checks espalier/wiki"       "grep -qF 'espalier/wiki/' '$GRILL'"
check "grill skill keeps the verify-before-raise (mark_stale) rule" "grep -qF 'mark_stale' '$GRILL'"
check "grill skill is not empty"                     "[ -s '$GRILL' ]"

echo
log "Verification: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || die "verification failed — the previous file is at $GRILL.pre-v0.12.bak"
log "v0.12.0 migration complete. Backup: $GRILL.pre-v0.12.bak (delete when satisfied)."
