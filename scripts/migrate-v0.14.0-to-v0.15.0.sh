#!/bin/bash
# Migrate a v0.14.0 Espalier install to v0.15.0.
#
# v0.15.0 adds GitHub Copilot platform support. Two parts:
#
#   1. ALWAYS: copy the new plugin-owned Copilot hook shim into the install —
#        espalier/hooks/copilot-hook-adapter.sh
#      It translates Copilot's camelCase hook payload (toolName/toolArgs) into
#      the Claude Code / Codex shape (tool_name/tool_input) and dispatches to
#      the shared wrappers. Inert until Copilot hooks reference it.
#
#   2. ONLY with --with-copilot: wire the copilot platform into this repo via
#      bootstrap --wire-only --platforms=copilot (unioned with the existing
#      platform set — never unwires claude/codex): .github/skills/ symlinks,
#      .github/copilot-instructions.md section, .github/agents/*.agent.md,
#      .github/hooks/espalier-gates.json, checks 52-56.
#      The /espalier-migrate skill asks the user; this script never prompts
#      for it (pass the flag).
#
# Usage:
#   bash migrate-v0.14.0-to-v0.15.0.sh [--dry-run] [--yes] [--with-copilot] [--plugin-dir=<path>]

set -u

DRY_RUN=no
SKIP_PROMPT=no
WITH_COPILOT=no
PLUGIN_DIR="${ESPALIER_PLUGIN_DIR:-}"

for arg in "$@"; do
  case "$arg" in
    --dry-run)       DRY_RUN=yes ;;
    --yes)           SKIP_PROMPT=yes ;;
    --with-copilot)  WITH_COPILOT=yes ;;
    --plugin-dir=*)  PLUGIN_DIR="${arg#--plugin-dir=}" ;;
    -h|--help)       sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown flag: $arg (use --help)" >&2; exit 2 ;;
  esac
done

log() { echo "[migrate v0.14.0→v0.15.0] $*"; }
die() { echo "[migrate v0.14.0→v0.15.0] ERROR: $*" >&2; exit 1; }

[ -d espalier ] || die "no espalier/ dir — run from the target project root."

# --- Locate plugin templates -------------------------------------------------
if [ -z "$PLUGIN_DIR" ]; then
  _self_root="$(cd "$(dirname "$0")/.." && pwd)"
  [ -d "$_self_root/skills/espalier-init/hook-templates" ] && PLUGIN_DIR="$_self_root"
fi
[ -n "$PLUGIN_DIR" ] || die "cannot locate the plugin. Pass --plugin-dir=<espalier-engineering root>."
TPL="$PLUGIN_DIR/skills/espalier-init"
ADAPTER_TPL="$TPL/hook-templates/copilot-hook-adapter.sh"
[ -f "$ADAPTER_TPL" ] || die "plugin dir $PLUGIN_DIR is not v0.15.0 (no copilot-hook-adapter template). Update the plugin first."

ADAPTER="espalier/hooks/copilot-hook-adapter.sh"

# --- Idempotency --------------------------------------------------------------
ADAPTER_DONE=no
[ -f "$ADAPTER" ] && ADAPTER_DONE=yes
COPILOT_DONE=no
grep -q copilot espalier/.platforms 2>/dev/null && COPILOT_DONE=yes

if [ "$ADAPTER_DONE" = yes ] && { [ "$WITH_COPILOT" = no ] || [ "$COPILOT_DONE" = yes ]; }; then
  log "already at v0.15.0 (adapter present$( [ "$COPILOT_DONE" = yes ] && echo '; copilot wired' )). Nothing to do."
  exit 0
fi

if [ "$DRY_RUN" = yes ]; then
  log "DRY RUN — would:"
  [ "$ADAPTER_DONE" = no ] && log "  copy $ADAPTER from the v0.15.0 template (new file — Copilot camelCase hook shim)"
  if [ "$WITH_COPILOT" = yes ] && [ "$COPILOT_DONE" = no ]; then
    log "  wire the copilot platform: bootstrap --wire-only --platforms=copilot (additive)"
  fi
  exit 0
fi

if [ "$SKIP_PROMPT" != yes ]; then
  printf "Apply the v0.15.0 migration (Copilot hook adapter%s)? [y/N] " \
    "$( [ "$WITH_COPILOT" = yes ] && echo ' + copilot wiring' )"
  read -r reply
  case "$reply" in [yY]*) ;; *) echo "Aborted."; exit 0 ;; esac
fi

# --- Part 1: install the adapter (new file — nothing to back up) --------------
if [ "$ADAPTER_DONE" = no ]; then
  mkdir -p espalier/hooks
  cp "$ADAPTER_TPL" "$ADAPTER"
  chmod +x "$ADAPTER"
  log "installed $ADAPTER"
else
  log "adapter already present — skipping copy"
fi

# --- Part 2: copilot wiring (only on request) ----------------------------------
if [ "$WITH_COPILOT" = yes ] && [ "$COPILOT_DONE" = no ]; then
  log "wiring copilot platform (bootstrap --wire-only, additive)"
  # --platforms=copilot unions with the existing platform set (bootstrap infers
  # "claude" for a complete pre-v0.14 install) — nothing is ever unwired.
  bash "$PLUGIN_DIR/scripts/bootstrap-espalier.sh" \
    --project-dir=. \
    --plugin-dir="$TPL" \
    --wire-only \
    --platforms=copilot \
    --yes \
    || die "copilot wiring failed — see bootstrap output above"
fi

# --- Verification --------------------------------------------------------------
pass=0; fail=0
check() { if eval "$2" >/dev/null 2>&1; then pass=$((pass+1)); echo "  ✓ $1"; else fail=$((fail+1)); echo "  ✗ $1"; fi; }

log "verification"
check "adapter present + executable"                "test -x '$ADAPTER'"
check "adapter translates toolArgs"                 "grep -qF 'toolArgs' '$ADAPTER'"
if [ "$WITH_COPILOT" = yes ]; then
  check "espalier/.platforms includes copilot"      "grep -q copilot espalier/.platforms"
  check ".github/skills wired"                      "[ -L .github/skills/espalier ]"
  check ".github/hooks/espalier-gates.json present" "grep -q 'copilot-hook-adapter' .github/hooks/espalier-gates.json"
  check ".github/agents custom agents present"      "test -f .github/agents/harness-coder.agent.md && test -f .github/agents/harness-reviewer.agent.md && test -f .github/agents/harness-security.agent.md"
  check "copilot-instructions Espalier section"     "grep -q '## Espalier' .github/copilot-instructions.md"
fi

echo
log "Verification: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || die "verification failed"
log "v0.15.0 migration complete.$( [ "$WITH_COPILOT" = yes ] && echo ' Copilot: reload VS Code / restart Copilot CLI so skills register; gates run in CLI + cloud agent.' )"
