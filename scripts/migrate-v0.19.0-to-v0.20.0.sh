#!/bin/bash
# Migrate a v0.19.0 Espalier install to v0.20.0.
#
# v0.20.0 is the slice-PR release: the run lane keeps its v0.19 topology
# (integration branch, local union merges, MERGED-gated dispatch) and gains an
# OPT-IN forge surface — one reviewable slice PR per ticket, opened before the
# local merge and auto-closed as merged when the integration branch is pushed,
# plus a final assembly PR. Without a `pr` key in plan.json nothing changes.
#
#   - New file: espalier/hooks/maprun-pr.sh (write-if-absent, like the rest of
#     the engine).
#   - Refresh (backup-on-diff → SKILL.md.pre-v0.20.bak): the espalier-maprun
#     lane skill (PR opt-in in the plan step, open→merge→sync order, final
#     assembly PR, restated safety rails).
#   - Bug fix in espalier/hooks/maprun-integration.sh: its push block wrote the
#     SHARED .git/config (not worktree-scoped), blocking pushes from the
#     operator's own checkout. Patched in place when the stock lines are found
#     (backup → .pre-v0.20.bak); a locally-adapted file gets a loud warning
#     with the manual fix instead.
#   - Runtime heal of the target repo: a poisoned shared
#     `remote.origin.pushurl = blocked://maprun-forbids-push` is unset, and any
#     existing `_integration` worktree gets the block re-applied
#     worktree-scoped.
#   - No config keys, no hook wiring changes, no new symlinks.
#
# Usage:
#   bash migrate-v0.19.0-to-v0.20.0.sh [--dry-run] [--yes] [--plugin-dir=<path>]

set -u

DRY_RUN=no
SKIP_PROMPT=no
PLUGIN_DIR="${ESPALIER_PLUGIN_DIR:-}"

for arg in "$@"; do
  case "$arg" in
    --dry-run)       DRY_RUN=yes ;;
    --yes)           SKIP_PROMPT=yes ;;
    --plugin-dir=*)  PLUGIN_DIR="${arg#--plugin-dir=}" ;;
    -h|--help)       sed -n '2,28p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown flag: $arg (use --help)" >&2; exit 2 ;;
  esac
done

log() { echo "[migrate v0.19.0→v0.20.0] $*"; }
die() { echo "[migrate v0.19.0→v0.20.0] ERROR: $*" >&2; exit 1; }

[ -d espalier ] || die "no espalier/ dir — run from the target project root."

# --- Locate plugin templates -------------------------------------------------
if [ -z "$PLUGIN_DIR" ]; then
  _self_root="$(cd "$(dirname "$0")/.." && pwd)"
  [ -d "$_self_root/skills/espalier-init/hook-templates" ] && PLUGIN_DIR="$_self_root"
fi
[ -n "$PLUGIN_DIR" ] || die "cannot locate the plugin. Pass --plugin-dir=<espalier-engineering root>."
TPL="$PLUGIN_DIR/skills/espalier-init"
[ -f "$TPL/hook-templates/maprun-pr.sh" ] \
  || die "plugin dir $PLUGIN_DIR is not v0.20.0 (no maprun-pr.sh template). Update the plugin first."

# --- Idempotency: every v0.20 marker -----------------------------------------
missing=""
mark() { missing="$missing
  - $1"; }
[ -f espalier/hooks/maprun-pr.sh ] || mark "run engine: maprun-pr.sh"
grep -qF 'maprun-pr.sh' espalier/skills/espalier-maprun/SKILL.md 2>/dev/null \
  || mark "espalier-maprun SKILL slice-PR doctrine"

if [ -z "$missing" ]; then
  log "already at v0.20.0 (every marker present). Nothing to do."
  exit 0
fi

if [ "$DRY_RUN" = yes ]; then
  log "DRY RUN — missing markers:$missing"
  if [ -f espalier/hooks/maprun-pr.sh ]; then
    log "DRY RUN —   engine maprun-pr.sh exists — would preserve (write-if-absent)"
  else
    log "DRY RUN —   would install espalier/hooks/maprun-pr.sh"
  fi
  log "DRY RUN — would refresh espalier-maprun SKILL (backup-on-diff → SKILL.md.pre-v0.20.bak)"
  if [ -f espalier/hooks/maprun-integration.sh ] \
     && ! grep -q -- '--worktree' espalier/hooks/maprun-integration.sh; then
    log "DRY RUN — would patch maprun-integration.sh push block to worktree scope"
  fi
  log "DRY RUN — would heal a poisoned shared remote.origin.pushurl and re-block _integration worktrees"
  exit 0
fi

if [ "$SKIP_PROMPT" != yes ]; then
  printf "Apply the v0.20.0 migration (slice PRs: maprun-pr.sh + worktree-scoped push block)? [y/N] "
  read -r reply
  case "$reply" in [yY]*) ;; *) echo "Aborted."; exit 0 ;; esac
fi

# --- New engine file (write-if-absent) ---------------------------------------
mkdir -p espalier/hooks
if [ -f espalier/hooks/maprun-pr.sh ]; then
  log "engine: espalier/hooks/maprun-pr.sh exists — preserving (local adaptation wins)"
else
  cp "$TPL/hook-templates/maprun-pr.sh" espalier/hooks/maprun-pr.sh
  log "installed espalier/hooks/maprun-pr.sh"
fi
chmod +x espalier/hooks/maprun-pr.sh 2>/dev/null || true

# --- Lane skill refresh (backup-on-diff) -------------------------------------
mkdir -p espalier/skills/espalier-maprun
if [ -f espalier/skills/espalier-maprun/SKILL.md ] \
   && ! cmp -s espalier/skills/espalier-maprun/SKILL.md "$TPL/templates/skills/espalier-maprun.md"; then
  cp espalier/skills/espalier-maprun/SKILL.md espalier/skills/espalier-maprun/SKILL.md.pre-v0.20.bak
  log "backed up existing espalier-maprun SKILL → SKILL.md.pre-v0.20.bak"
fi
cp "$TPL/templates/skills/espalier-maprun.md" espalier/skills/espalier-maprun/SKILL.md
log "refreshed espalier/skills/espalier-maprun/SKILL.md"

# --- maprun-integration.sh: worktree-scope the push block --------------------
# The stock v0.19 lines wrote the SHARED .git/config. Patch them in place when
# found verbatim; anything else (already patched, locally adapted) is left
# alone — with a loud warning if the unscoped pattern is still detectable.
MI=espalier/hooks/maprun-integration.sh
if [ -f "$MI" ]; then
  if grep -q -- '--worktree' "$MI"; then
    log "maprun-integration.sh already worktree-scoped — no patch needed"
  else
    PATCHED=$(MI="$MI" python3 - << 'PYPATCH'
import os
path = os.environ["MI"]
src = open(path).read()
old = ('  git -C "$IWT" config remote.origin.pushurl "blocked://maprun-forbids-push" || true\n'
       '  git -C "$IWT" config push.default nothing || true\n')
new = ('  git -C "$REPO" config extensions.worktreeConfig true\n'
       '  git -C "$IWT" config --worktree remote.origin.pushurl "blocked://maprun-forbids-push" || true\n'
       '  git -C "$IWT" config --worktree push.default nothing || true\n')
if old not in src:
    print("miss")
    raise SystemExit(0)
open(path + ".pre-v0.20.bak", "w").write(src)
open(path, "w").write(src.replace(old, new, 1))
print("ok")
PYPATCH
)
    if [ "$PATCHED" = "ok" ]; then
      log "patched maprun-integration.sh push block to worktree scope (backup → $MI.pre-v0.20.bak)"
    else
      log "WARN: maprun-integration.sh is locally adapted and still uses an"
      log "WARN: unscoped push block. Fix it by hand: the two 'git -C \"\$IWT\" config'"
      log "WARN: lines need --worktree (plus 'git -C \"\$REPO\" config extensions.worktreeConfig true')."
    fi
  fi
fi

# --- Runtime heal: shared config + existing _integration worktrees -----------
if git rev-parse --show-toplevel >/dev/null 2>&1; then
  if [ "$(git config remote.origin.pushurl 2>/dev/null)" = "blocked://maprun-forbids-push" ]; then
    git config --unset remote.origin.pushurl || true
    log "healed: removed maprun push block from the SHARED git config"
  fi
  git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | while IFS= read -r wt; do
    case "$wt" in
      */_integration)
        git config extensions.worktreeConfig true
        git -C "$wt" config --worktree remote.origin.pushurl "blocked://maprun-forbids-push" 2>/dev/null || true
        git -C "$wt" config --worktree push.default nothing 2>/dev/null || true
        log "re-blocked (worktree-scoped): $wt"
        ;;
    esac
  done
fi

log "done. The PR flow is OPT-IN: add a \"pr\" key to a map's plan.json (see the"
log "lane skill's plan.json reference) and run 'maprun-pr.sh <map-dir> setup'."
