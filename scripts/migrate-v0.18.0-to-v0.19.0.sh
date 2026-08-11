#!/bin/bash
# Migrate a v0.18.0 Espalier install to v0.19.0.
#
# v0.19.0 is the run-lane release: /espalier-maprun drives a CLEARED map's FILED
# slices to completion over hours/days — an interactive master dispatches
# headless pipeline workers (stages 1-6) in isolated push-blocked worktrees,
# merges what passes into an integration branch, and relays worker questions.
#
#   - New files: espalier/skills/espalier-maprun/SKILL.md (+ symlinks on every
#     platform in espalier/.platforms) and the run engine — espalier/hooks/
#     maprun.py + maprun-{dispatch,merge,integration,verify}.sh. Engine files
#     are WRITE-IF-ABSENT: a repo already carrying a locally-adapted engine
#     (the lane's field origin) keeps its version; the skill file installs
#     with backup-on-diff so lane doctrine still refreshes.
#   - Refresh (backup-on-diff → <file>.pre-v0.19.bak): espalier/pipeline.md,
#     the espalier-map SKILL.md (handoff now names the batch executor).
#   - Instruction files: one grep-guarded `/espalier-maprun` line appended inside
#     the existing `## Espalier` section of CLAUDE.md / AGENTS.md /
#     .github/copilot-instructions.md where that section exists.
#   - No config keys, no hook wiring changes (the run lane is invoked, never
#     event-driven).
#
# Usage:
#   bash migrate-v0.18.0-to-v0.19.0.sh [--dry-run] [--yes] [--plugin-dir=<path>]

set -u

DRY_RUN=no
SKIP_PROMPT=no
PLUGIN_DIR="${ESPALIER_PLUGIN_DIR:-}"

for arg in "$@"; do
  case "$arg" in
    --dry-run)       DRY_RUN=yes ;;
    --yes)           SKIP_PROMPT=yes ;;
    --plugin-dir=*)  PLUGIN_DIR="${arg#--plugin-dir=}" ;;
    -h|--help)       sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown flag: $arg (use --help)" >&2; exit 2 ;;
  esac
done

log() { echo "[migrate v0.18.0→v0.19.0] $*"; }
die() { echo "[migrate v0.18.0→v0.19.0] ERROR: $*" >&2; exit 1; }

[ -d espalier ] || die "no espalier/ dir — run from the target project root."

# --- Locate plugin templates -------------------------------------------------
if [ -z "$PLUGIN_DIR" ]; then
  _self_root="$(cd "$(dirname "$0")/.." && pwd)"
  [ -d "$_self_root/skills/espalier-init/hook-templates" ] && PLUGIN_DIR="$_self_root"
fi
[ -n "$PLUGIN_DIR" ] || die "cannot locate the plugin. Pass --plugin-dir=<espalier-engineering root>."
TPL="$PLUGIN_DIR/skills/espalier-init"
[ -f "$TPL/templates/skills/espalier-maprun.md" ] \
  || die "plugin dir $PLUGIN_DIR is not v0.19.0 (no espalier-maprun template). Update the plugin first."
[ -f "$TPL/hook-templates/maprun.py" ] \
  || die "plugin dir $PLUGIN_DIR is not v0.19.0 (no maprun.py template). Update the plugin first."

PLATFORMS=$(head -1 espalier/.platforms 2>/dev/null | tr -d '[:space:]')
[ -n "$PLATFORMS" ] || PLATFORMS=claude
want_claude()  { case "$PLATFORMS" in *claude*)  return 0 ;; *) return 1 ;; esac; }
want_codex()   { case "$PLATFORMS" in *codex*)   return 0 ;; *) return 1 ;; esac; }
want_copilot() { case "$PLATFORMS" in *copilot*) return 0 ;; *) return 1 ;; esac; }

ENGINE_FILES="maprun.py maprun-dispatch.sh maprun-merge.sh maprun-integration.sh maprun-verify.sh"

COPY_PAIRS="espalier/pipeline.md|$TPL/templates/pipeline.md
espalier/skills/espalier-map/SKILL.md|$TPL/templates/skills/espalier-map.md"

# --- Idempotency: every v0.19 marker -----------------------------------------
missing=""
mark() { missing="$missing
  - $1"; }
[ -f espalier/skills/espalier-maprun/SKILL.md ] \
  || mark "espalier-maprun lane skill"
for mr in $ENGINE_FILES; do
  [ -f "espalier/hooks/$mr" ] || mark "run engine: $mr"
done
grep -qF '/espalier-maprun' espalier/pipeline.md 2>/dev/null \
  || mark "pipeline.md run-lane note"
grep -qF 'espalier-maprun' espalier/skills/espalier-map/SKILL.md 2>/dev/null \
  || mark "espalier-map SKILL batch-handoff note"
if want_claude; then
  grep -qF 'espalier-maprun' CLAUDE.md 2>/dev/null \
    || mark "CLAUDE.md run-lane line"
fi
if want_codex; then
  grep -qF 'espalier-maprun' AGENTS.md 2>/dev/null \
    || mark "AGENTS.md run-lane line"
fi
if want_copilot; then
  grep -qF 'espalier-maprun' .github/copilot-instructions.md 2>/dev/null \
    || mark "copilot-instructions run-lane line"
fi

if [ -z "$missing" ]; then
  log "already at v0.19.0 (every marker present). Nothing to do."
  exit 0
fi

if [ "$DRY_RUN" = yes ]; then
  log "DRY RUN — missing markers:$missing"
  log "DRY RUN — would install espalier/skills/espalier-maprun/SKILL.md + symlinks ($PLATFORMS)"
  for mr in $ENGINE_FILES; do
    if [ -f "espalier/hooks/$mr" ]; then
      log "DRY RUN —   engine $mr exists — would preserve (write-if-absent)"
    else
      log "DRY RUN —   would install espalier/hooks/$mr"
    fi
  done
  log "DRY RUN — would refresh (backup-on-diff → <file>.pre-v0.19.bak):"
  echo "$COPY_PAIRS" | while IFS='|' read -r dst src; do
    [ -n "$dst" ] || continue
    if [ -f "$dst" ] && ! cmp -s "$dst" "$src"; then
      log "  $dst (differs — backup then copy)"
    elif [ ! -f "$dst" ]; then
      log "  $dst (missing — new copy, no backup)"
    else
      log "  $dst (already matches — no-op)"
    fi
  done
  log "DRY RUN — would add /espalier-maprun instruction lines per platform"
  exit 0
fi

if [ "$SKIP_PROMPT" != yes ]; then
  printf "Apply the v0.19.0 migration (run lane: /espalier-maprun master + maprun engine)? [y/N] "
  read -r reply
  case "$reply" in [yY]*) ;; *) echo "Aborted."; exit 0 ;; esac
fi

# --- New files ----------------------------------------------------------------
mkdir -p espalier/skills/espalier-maprun espalier/hooks
if [ -f espalier/skills/espalier-maprun/SKILL.md ] \
   && ! cmp -s espalier/skills/espalier-maprun/SKILL.md "$TPL/templates/skills/espalier-maprun.md"; then
  cp espalier/skills/espalier-maprun/SKILL.md espalier/skills/espalier-maprun/SKILL.md.pre-v0.19.bak
  log "backed up existing espalier-maprun SKILL → SKILL.md.pre-v0.19.bak"
fi
cp "$TPL/templates/skills/espalier-maprun.md" espalier/skills/espalier-maprun/SKILL.md
log "installed espalier/skills/espalier-maprun/SKILL.md"

for mr in $ENGINE_FILES; do
  if [ -f "espalier/hooks/$mr" ]; then
    log "engine: espalier/hooks/$mr exists — preserving (local adaptation wins)"
  else
    cp "$TPL/hook-templates/$mr" "espalier/hooks/$mr"
    log "installed espalier/hooks/$mr"
  fi
done
chmod +x espalier/hooks/maprun-*.sh 2>/dev/null || true

# --- Symlinks per platform (same relative-target convention as bootstrap) -----
_safe_ln() {
  local src="$1" dst="$2"
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    log "  WARN: $dst exists as a regular file — skipping symlink (move it aside, then re-run)"
    return 0
  fi
  ln -sfn "$src" "$dst"
}
if want_claude; then
  mkdir -p .claude/skills
  _safe_ln "../../espalier/skills/espalier-maprun" .claude/skills/espalier-maprun
  log "linked .claude/skills/espalier-maprun"
fi
if want_codex; then
  mkdir -p .agents/skills
  _safe_ln "../../espalier/skills/espalier-maprun" .agents/skills/espalier-maprun
  log "linked .agents/skills/espalier-maprun"
fi
if want_copilot; then
  mkdir -p .github/skills
  _safe_ln "../../espalier/skills/espalier-maprun" .github/skills/espalier-maprun
  log "linked .github/skills/espalier-maprun"
fi

# --- Pure-copy refresh (backup-on-diff) ---------------------------------------
log "refreshing pure-copy files (backup-on-diff → <file>.pre-v0.19.bak)"
echo "$COPY_PAIRS" | while IFS='|' read -r dst src; do
  [ -n "$dst" ] || continue
  [ -f "$src" ] || { echo "  WARN: plugin template missing: $src" >&2; continue; }
  if [ -f "$dst" ] && cmp -s "$dst" "$src"; then
    log "  unchanged: $dst"
    continue
  fi
  if [ -f "$dst" ]; then
    cp "$dst" "$dst.pre-v0.19.bak"
    log "  backed up: $dst → $dst.pre-v0.19.bak"
  fi
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  log "  refreshed: $dst"
done

# --- Instruction-file lane lines (grep-guarded, only where section exists) ----
_add_lane_line() {   # FILE INVOKE_PREFIX
  local f="$1" p="$2"
  [ -f "$f" ] || return 0
  grep -q "## Espalier" "$f" 2>/dev/null || return 0
  grep -qF "espalier-maprun" "$f" 2>/dev/null && return 0
  printf '\n**To execute a whole cleared map** over hours/days, invoke `%sespalier-maprun <map-slug>` — one interactive master pass dispatches headless pipeline workers in isolated worktrees, merges what passes, and relays worker questions; run one pass per fresh session.\n' "$p" >> "$f"
  log "added /espalier-maprun line to $f"
}
want_claude  && _add_lane_line CLAUDE.md "/"
want_codex   && _add_lane_line AGENTS.md "\$"
want_copilot && _add_lane_line .github/copilot-instructions.md "/"

# --- Verification --------------------------------------------------------------
pass=0; fail=0
check() { if eval "$2" >/dev/null 2>&1; then pass=$((pass+1)); echo "  ✓ $1"; else fail=$((fail+1)); echo "  ✗ $1"; fi; }

log "verification"
check "espalier-maprun skill installed"   "grep -q '^name: espalier-maprun' espalier/skills/espalier-maprun/SKILL.md"
check "maprun engine present"          "test -f espalier/hooks/maprun.py && test -x espalier/hooks/maprun-dispatch.sh && test -x espalier/hooks/maprun-merge.sh && test -x espalier/hooks/maprun-integration.sh && test -x espalier/hooks/maprun-verify.sh"
check "pipeline run-lane note"         "grep -qF '/espalier-maprun' espalier/pipeline.md"
check "map SKILL batch handoff"        "grep -qF 'espalier-maprun' espalier/skills/espalier-map/SKILL.md"
if want_claude; then
  check "claude symlink"               "[ -L .claude/skills/espalier-maprun ] && [ -e .claude/skills/espalier-maprun ]"
  check "CLAUDE.md lane line"          "grep -qF 'espalier-maprun' CLAUDE.md"
fi
if want_codex; then
  check "codex symlink"                "[ -L .agents/skills/espalier-maprun ] && [ -e .agents/skills/espalier-maprun ]"
  check "AGENTS.md lane line"          "grep -qF 'espalier-maprun' AGENTS.md"
fi
if want_copilot; then
  check "copilot symlink"              "[ -L .github/skills/espalier-maprun ] && [ -e .github/skills/espalier-maprun ]"
  check "copilot-instructions line"    "grep -qF 'espalier-maprun' .github/copilot-instructions.md"
fi

echo
log "Verification: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || die "verification failed"
log "v0.19.0 migration complete. Plan a cleared map's run with /espalier-maprun <map-slug> plan, then advance it one pass at a time with /espalier-maprun <map-slug>."
