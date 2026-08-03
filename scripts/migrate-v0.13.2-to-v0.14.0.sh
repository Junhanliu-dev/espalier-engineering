#!/bin/bash
# Migrate a v0.13.2 Espalier install to v0.14.0.
#
# v0.14.0 adds Codex platform support. Two parts:
#
#   1. ALWAYS: refresh the two platform-neutral hook wrappers from the v0.14.0
#      templates (pure copies, plugin-owned — never user-substituted):
#        espalier/hooks/post-edit-wrapper.sh   — now also parses Codex
#          apply_patch hook input ("*** Add|Update File:" lines, argv arrays)
#          and resolves the repo root without $CLAUDE_PROJECT_DIR
#        espalier/hooks/pre-push-gate-wrapper.sh — now joins argv-array
#          commands (Codex shell tool) before the git-push pattern match
#      Both changes are inert on Claude Code (same fields, same exit codes).
#
#   2. ONLY with --with-codex: wire the codex platform into this repo via
#      bootstrap --wire-only --platforms=codex (unioned with the existing
#      platform set — never unwires claude): .agents/skills/ symlinks,
#      AGENTS.md section, .codex/config.toml hook block,
#      .codex/agents/harness-*.toml sub-agents, checks 47-51.
#      The /espalier-migrate skill asks the user; this script never prompts
#      for it (pass the flag).
#
# Usage:
#   bash migrate-v0.13.2-to-v0.14.0.sh [--dry-run] [--yes] [--with-codex] [--plugin-dir=<path>]

set -u

DRY_RUN=no
SKIP_PROMPT=no
WITH_CODEX=no
PLUGIN_DIR="${ESPALIER_PLUGIN_DIR:-}"

for arg in "$@"; do
  case "$arg" in
    --dry-run)      DRY_RUN=yes ;;
    --yes)          SKIP_PROMPT=yes ;;
    --with-codex)   WITH_CODEX=yes ;;
    --plugin-dir=*) PLUGIN_DIR="${arg#--plugin-dir=}" ;;
    -h|--help)      sed -n '2,24p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown flag: $arg (use --help)" >&2; exit 2 ;;
  esac
done

log() { echo "[migrate v0.13.2→v0.14.0] $*"; }
die() { echo "[migrate v0.13.2→v0.14.0] ERROR: $*" >&2; exit 1; }

[ -d espalier ] || die "no espalier/ dir — run from the target project root."

# --- Locate plugin templates -------------------------------------------------
if [ -z "$PLUGIN_DIR" ]; then
  _self_root="$(cd "$(dirname "$0")/.." && pwd)"
  [ -d "$_self_root/skills/espalier-init/hook-templates" ] && PLUGIN_DIR="$_self_root"
fi
[ -n "$PLUGIN_DIR" ] || die "cannot locate the plugin. Pass --plugin-dir=<espalier-engineering root>."
TPL="$PLUGIN_DIR/skills/espalier-init"
POST_TPL="$TPL/hook-templates/post-edit-wrapper.sh"
PUSH_TPL="$TPL/hook-templates/pre-push-gate-wrapper.sh"
[ -f "$POST_TPL" ] || die "plugin dir $PLUGIN_DIR has no post-edit-wrapper template at $POST_TPL."
[ -f "$PUSH_TPL" ] || die "plugin dir $PLUGIN_DIR has no pre-push-gate-wrapper template at $PUSH_TPL."

# The templates must actually be v0.14.0 — otherwise a stale plugin would
# "migrate" the wrappers straight back to Claude-only parsing.
grep -qF 'apply_patch' "$POST_TPL" || \
  die "template at $PLUGIN_DIR is not v0.14.0 (post-edit-wrapper lacks apply_patch parsing). Update the plugin first."
grep -qF 'isinstance(c, list)' "$PUSH_TPL" || \
  die "template at $PLUGIN_DIR is not v0.14.0 (pre-push-gate-wrapper lacks argv-array join). Update the plugin first."

POST="espalier/hooks/post-edit-wrapper.sh"
PUSH="espalier/hooks/pre-push-gate-wrapper.sh"

# --- Idempotency --------------------------------------------------------------
WRAPPERS_DONE=no
if [ -f "$POST" ] && grep -qF 'apply_patch' "$POST" && \
   [ -f "$PUSH" ] && grep -qF 'isinstance(c, list)' "$PUSH"; then
  WRAPPERS_DONE=yes
fi
CODEX_DONE=no
if grep -q codex espalier/.platforms 2>/dev/null; then
  CODEX_DONE=yes
fi

if [ "$WRAPPERS_DONE" = yes ] && { [ "$WITH_CODEX" = no ] || [ "$CODEX_DONE" = yes ]; }; then
  log "already at v0.14.0 (wrappers platform-neutral$( [ "$CODEX_DONE" = yes ] && echo '; codex wired' )). Nothing to do."
  exit 0
fi

if [ "$DRY_RUN" = yes ]; then
  log "DRY RUN — would:"
  [ "$WRAPPERS_DONE" = no ] && {
    log "  refresh $POST from the v0.14.0 template (backup .pre-v0.14.bak) — Codex apply_patch parsing"
    log "  refresh $PUSH from the v0.14.0 template (backup .pre-v0.14.bak) — argv-array command join"
  }
  if [ "$WITH_CODEX" = yes ] && [ "$CODEX_DONE" = no ]; then
    log "  wire the codex platform: bootstrap --wire-only --platforms=codex (additive)"
  fi
  exit 0
fi

if [ "$SKIP_PROMPT" != yes ]; then
  printf "Apply the v0.14.0 migration (platform-neutral hook wrappers%s)? [y/N] " \
    "$( [ "$WITH_CODEX" = yes ] && echo ' + codex wiring' )"
  read -r reply
  case "$reply" in [yY]*) ;; *) echo "Aborted."; exit 0 ;; esac
fi

# --- Part 1: refresh the two wrappers (pure copy) -----------------------------
if [ "$WRAPPERS_DONE" = no ]; then
  for pair in "$POST_TPL:$POST" "$PUSH_TPL:$PUSH"; do
    src="${pair%%:*}"; dst="${pair#*:}"
    mkdir -p "$(dirname "$dst")"
    if [ -f "$dst" ]; then
      cp "$dst" "$dst.pre-v0.14.bak"
      log "backed up -> $dst.pre-v0.14.bak"
    fi
    cp "$src" "$dst"
    chmod +x "$dst"
    log "refreshed $dst from the v0.14.0 template"
  done
else
  log "wrappers already v0.14.0 — skipping refresh"
fi

# --- Part 2: codex wiring (only on request) -----------------------------------
if [ "$WITH_CODEX" = yes ] && [ "$CODEX_DONE" = no ]; then
  log "wiring codex platform (bootstrap --wire-only, additive)"
  # --platforms=codex unions with the existing platform set (bootstrap infers
  # "claude" for a complete pre-v0.14 install) — claude wiring is never lost.
  bash "$PLUGIN_DIR/scripts/bootstrap-espalier.sh" \
    --project-dir=. \
    --plugin-dir="$TPL" \
    --wire-only \
    --platforms=codex \
    --yes \
    || die "codex wiring failed — see bootstrap output above ($POST.pre-v0.14.bak / $PUSH.pre-v0.14.bak hold the previous wrappers)"
fi

# --- Verification --------------------------------------------------------------
pass=0; fail=0
check() { if eval "$2" >/dev/null 2>&1; then pass=$((pass+1)); echo "  ✓ $1"; else fail=$((fail+1)); echo "  ✗ $1"; fi; }

log "verification"
check "post-edit-wrapper parses apply_patch input"   "grep -qF 'apply_patch' '$POST'"
check "post-edit-wrapper resolves root without CLAUDE_PROJECT_DIR" "grep -qF 'git rev-parse --show-toplevel' '$POST'"
check "pre-push-gate-wrapper joins argv arrays"      "grep -qF 'isinstance(c, list)' '$PUSH'"
check "both wrappers executable"                     "test -x '$POST' && test -x '$PUSH'"
if [ "$WITH_CODEX" = yes ]; then
  check "espalier/.platforms includes codex"         "grep -q codex espalier/.platforms"
  check ".agents/skills wired"                       "[ -L .agents/skills/espalier ]"
  check ".codex/config.toml hook block present"      "grep -q 'espalier/hooks' .codex/config.toml"
  check ".codex/agents sub-agents present"           "test -f .codex/agents/harness-coder.toml && test -f .codex/agents/harness-reviewer.toml && test -f .codex/agents/harness-security.toml"
  check "AGENTS.md Espalier section present"         "grep -q '## Espalier' AGENTS.md"
fi

echo
log "Verification: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || die "verification failed — previous wrappers are at $POST.pre-v0.14.bak / $PUSH.pre-v0.14.bak"
log "v0.14.0 migration complete.$( [ "$WITH_CODEX" = yes ] && echo ' Codex: restart Codex, trust the project, run /hooks to trust the gates.' ) Backups: *.pre-v0.14.bak (delete when satisfied)."
