#!/bin/bash
# Migrate a v0.17.0 Espalier install to v0.18.0.
#
# v0.18.0 is the map-lane release: the /espalier-map multi-session planning
# lane (decision maps under espalier/maps/), the map-guard plan-don't-do
# PreToolUse hook, grill mode=decision, and the greenfield decide-then-bind
# init path (the last is plugin-side only — nothing to migrate here).
#
#   - New files: espalier/skills/espalier-map/SKILL.md (+ symlinks on every
#     platform in espalier/.platforms), espalier/hooks/map-guard.sh,
#     espalier/maps/ dir.
#   - Refresh (backup-on-diff → <file>.pre-v0.18.bak): espalier/pipeline.md,
#     the espalier + espalier-grill SKILL.md files.
#   - Wiring: .claude/settings.json gains the map-guard PreToolUse entry
#     (additive merge — user hooks untouched); .codex/config.toml gains the
#     marker-guarded ESPALIER MAP GUARD v1 block; .github/hooks/
#     espalier-gates.json gains the map-guard preToolUse entry via a targeted
#     json insert (file preserved otherwise; unparseable → warn, never clobber).
#   - Config: append `max-open-tickets: 9` to espalier/.espalier-config
#     (append-if-missing; user file otherwise preserved).
#   - Instruction files: one grep-guarded `/espalier-map` line appended inside
#     the existing `## Espalier` section of CLAUDE.md / AGENTS.md /
#     .github/copilot-instructions.md where that section exists.
#
# Usage:
#   bash migrate-v0.17.0-to-v0.18.0.sh [--dry-run] [--yes] [--plugin-dir=<path>]

set -u

DRY_RUN=no
SKIP_PROMPT=no
PLUGIN_DIR="${ESPALIER_PLUGIN_DIR:-}"

for arg in "$@"; do
  case "$arg" in
    --dry-run)       DRY_RUN=yes ;;
    --yes)           SKIP_PROMPT=yes ;;
    --plugin-dir=*)  PLUGIN_DIR="${arg#--plugin-dir=}" ;;
    -h|--help)       sed -n '2,27p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown flag: $arg (use --help)" >&2; exit 2 ;;
  esac
done

log() { echo "[migrate v0.17.0→v0.18.0] $*"; }
die() { echo "[migrate v0.17.0→v0.18.0] ERROR: $*" >&2; exit 1; }

[ -d espalier ] || die "no espalier/ dir — run from the target project root."

# --- Locate plugin templates -------------------------------------------------
if [ -z "$PLUGIN_DIR" ]; then
  _self_root="$(cd "$(dirname "$0")/.." && pwd)"
  [ -d "$_self_root/skills/espalier-init/hook-templates" ] && PLUGIN_DIR="$_self_root"
fi
[ -n "$PLUGIN_DIR" ] || die "cannot locate the plugin. Pass --plugin-dir=<espalier-engineering root>."
TPL="$PLUGIN_DIR/skills/espalier-init"
[ -f "$TPL/templates/skills/espalier-map.md" ] \
  || die "plugin dir $PLUGIN_DIR is not v0.18.0 (no espalier-map template). Update the plugin first."
[ -f "$TPL/hook-templates/map-guard.sh" ] \
  || die "plugin dir $PLUGIN_DIR is not v0.18.0 (no map-guard.sh template). Update the plugin first."

PLATFORMS=$(head -1 espalier/.platforms 2>/dev/null | tr -d '[:space:]')
[ -n "$PLATFORMS" ] || PLATFORMS=claude
want_claude()  { case "$PLATFORMS" in *claude*)  return 0 ;; *) return 1 ;; esac; }
want_codex()   { case "$PLATFORMS" in *codex*)   return 0 ;; *) return 1 ;; esac; }
want_copilot() { case "$PLATFORMS" in *copilot*) return 0 ;; *) return 1 ;; esac; }

COPY_PAIRS="espalier/pipeline.md|$TPL/templates/pipeline.md
espalier/skills/espalier/SKILL.md|$TPL/templates/skills/espalier.md
espalier/skills/espalier-grill/SKILL.md|$TPL/templates/skills/espalier-grill.md"

# --- Idempotency: every v0.18 marker -----------------------------------------
missing=""
mark() { missing="$missing
  - $1"; }
[ -f espalier/skills/espalier-map/SKILL.md ] \
  || mark "espalier-map lane skill"
[ -x espalier/hooks/map-guard.sh ] \
  || mark "map-guard hook (executable)"
[ -x espalier/hooks/espalier-stats.sh ] \
  || mark "espalier-stats report hook"
grep -qF 'mode=decision' espalier/skills/espalier-grill/SKILL.md 2>/dev/null \
  || mark "grill decision mode"
grep -qF 'charted_from' espalier/skills/espalier/SKILL.md 2>/dev/null \
  || mark "espalier SKILL map-slice adoption"
grep -qF '/espalier-map' espalier/pipeline.md 2>/dev/null \
  || mark "pipeline.md lanes note"
grep -q '^max-open-tickets:' espalier/.espalier-config 2>/dev/null \
  || mark "max-open-tickets config key"
if want_claude; then
  grep -qF 'map-guard' .claude/settings.json 2>/dev/null \
    || mark "settings.json map-guard entry"
fi
if want_codex; then
  grep -qF 'ESPALIER MAP GUARD' .codex/config.toml 2>/dev/null \
    || mark ".codex/config.toml map-guard block"
fi
if want_copilot; then
  grep -qF 'map-guard' .github/hooks/espalier-gates.json 2>/dev/null \
    || mark "copilot gates map-guard entry"
fi

if [ -z "$missing" ]; then
  log "already at v0.18.0 (every marker present). Nothing to do."
  exit 0
fi

if [ "$DRY_RUN" = yes ]; then
  log "DRY RUN — missing markers:$missing"
  log "DRY RUN — would create espalier/skills/espalier-map/SKILL.md, espalier/hooks/map-guard.sh, espalier/maps/"
  log "DRY RUN — would symlink espalier-map for platforms: $PLATFORMS"
  log "DRY RUN — would refresh (backup-on-diff → <file>.pre-v0.18.bak):"
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
  log "DRY RUN — would append max-open-tickets: 9 (if missing), wire hooks per platform, add /espalier-map instruction lines"
  exit 0
fi

if [ "$SKIP_PROMPT" != yes ]; then
  printf "Apply the v0.18.0 migration (map lane + map-guard + grill decision mode)? [y/N] "
  read -r reply
  case "$reply" in [yY]*) ;; *) echo "Aborted."; exit 0 ;; esac
fi

# --- New files ----------------------------------------------------------------
mkdir -p espalier/skills/espalier-map espalier/maps
cp "$TPL/templates/skills/espalier-map.md" espalier/skills/espalier-map/SKILL.md
log "installed espalier/skills/espalier-map/SKILL.md"
cp "$TPL/hook-templates/map-guard.sh" espalier/hooks/map-guard.sh
chmod +x espalier/hooks/map-guard.sh
log "installed espalier/hooks/map-guard.sh"
cp "$TPL/hook-templates/espalier-stats.sh" espalier/hooks/espalier-stats.sh
chmod +x espalier/hooks/espalier-stats.sh
log "installed espalier/hooks/espalier-stats.sh"

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
  _safe_ln "../../espalier/skills/espalier-map" .claude/skills/espalier-map
  log "linked .claude/skills/espalier-map"
fi
if want_codex; then
  mkdir -p .agents/skills
  _safe_ln "../../espalier/skills/espalier-map" .agents/skills/espalier-map
  log "linked .agents/skills/espalier-map"
fi
if want_copilot; then
  mkdir -p .github/skills
  _safe_ln "../../espalier/skills/espalier-map" .github/skills/espalier-map
  log "linked .github/skills/espalier-map"
fi

# --- Pure-copy refresh (backup-on-diff) ---------------------------------------
log "refreshing pure-copy files (backup-on-diff → <file>.pre-v0.18.bak)"
echo "$COPY_PAIRS" | while IFS='|' read -r dst src; do
  [ -n "$dst" ] || continue
  [ -f "$src" ] || { echo "  WARN: plugin template missing: $src" >&2; continue; }
  if [ -f "$dst" ] && cmp -s "$dst" "$src"; then
    log "  unchanged: $dst"
    continue
  fi
  if [ -f "$dst" ]; then
    cp "$dst" "$dst.pre-v0.18.bak"
    log "  backed up: $dst → $dst.pre-v0.18.bak"
  fi
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  log "  refreshed: $dst"
done

# --- Config key (append-if-missing, newline-guarded) --------------------------
if ! grep -q '^max-open-tickets:' espalier/.espalier-config 2>/dev/null; then
  touch espalier/.espalier-config
  if [ -s espalier/.espalier-config ] && [ -n "$(tail -c1 espalier/.espalier-config)" ]; then
    printf '\n' >> espalier/.espalier-config
  fi
  printf '\n# /espalier-map anti-waterfall cap: max OPEN decision tickets per map.\nmax-open-tickets: 9\n' \
    >> espalier/.espalier-config
  log "appended max-open-tickets: 9 to espalier/.espalier-config"
fi

# --- Claude settings.json merge (additive, atomic — bootstrap's algorithm) ----
if want_claude; then
  mkdir -p .claude
  if [ -f .claude/settings.json ]; then
    cp .claude/settings.json ".claude/settings.json.espalier-backup-$(date +%s)"
    ls -t .claude/settings.json.espalier-backup-* 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null || true
  fi
  python3 - << 'PYMERGE' || die "settings.json merge failed"
import json, os, sys, tempfile

SETTINGS = ".claude/settings.json"
NEW_ENTRY = {
    "matcher": "Write|Edit",
    "hooks": [{
        "type": "command",
        "command": 'bash "$CLAUDE_PROJECT_DIR/espalier/hooks/map-guard.sh"',
        "timeout": 5
    }]
}

if os.path.exists(SETTINGS):
    try:
        with open(SETTINGS) as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        print(f"ERROR: .claude/settings.json is invalid JSON: {e}", file=sys.stderr)
        sys.exit(1)
else:
    data = {}

hooks = data.setdefault("hooks", {})
if not isinstance(hooks, dict):
    print("ERROR: .claude/settings.json 'hooks' is not an object", file=sys.stderr)
    sys.exit(1)
entries = hooks.setdefault("PreToolUse", [])
new_cmds = {h.get("command") for h in NEW_ENTRY["hooks"]}
present = any(
    e.get("matcher") == NEW_ENTRY["matcher"]
    and new_cmds & {h.get("command") for h in e.get("hooks", [])}
    for e in entries
)
if present:
    print("[migrate v0.17.0→v0.18.0]   settings.json: map-guard entry already present")
else:
    entries.append(NEW_ENTRY)
    dirname = os.path.dirname(SETTINGS) or "."
    fd, tmp = tempfile.mkstemp(dir=dirname, suffix=".tmp", prefix=".settings-")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
        with open(tmp) as f:
            json.load(f)
        os.replace(tmp, SETTINGS)
        print("[migrate v0.17.0→v0.18.0]   settings.json: map-guard entry added")
    except Exception as e:
        os.unlink(tmp)
        print(f"ERROR: failed to write settings.json: {e}", file=sys.stderr)
        sys.exit(1)
PYMERGE
fi

# --- Codex config block (own markers — additive) ------------------------------
if want_codex; then
  if grep -qF 'ESPALIER MAP GUARD' .codex/config.toml 2>/dev/null; then
    log ".codex/config.toml: map-guard block already present"
  else
    mkdir -p .codex
    [ -s .codex/config.toml ] && printf '\n' >> .codex/config.toml
    cat >> .codex/config.toml << 'CODEXMAPGUARD'
# >>> ESPALIER MAP GUARD v1 >>> (managed by espalier bootstrap — do not edit between markers)
# Blocks writes outside espalier/maps/ while a /espalier-map session marker is
# active (plan, don't do). Inert otherwise. Exit 2 + stderr blocks.
[[hooks.PreToolUse]]
matcher = "^(apply_patch|Edit|Write)$"

[[hooks.PreToolUse.hooks]]
type = "command"
command = "bash espalier/hooks/map-guard.sh"
statusMessage = "Espalier map-session write guard"
timeout = 5
# <<< ESPALIER MAP GUARD v1 <<<
CODEXMAPGUARD
    log ".codex/config.toml: map-guard block appended (re-run /hooks in Codex to trust it)"
  fi
fi

# --- Copilot gates json insert (targeted; never clobber) ----------------------
if want_copilot; then
  GATES=.github/hooks/espalier-gates.json
  if [ ! -f "$GATES" ]; then
    log "WARN: $GATES missing — re-run bootstrap --wire-only --platforms=copilot to recreate it (it will include map-guard)"
  elif grep -qF 'map-guard' "$GATES" 2>/dev/null; then
    log "copilot gates: map-guard entry already present"
  else
    python3 - << 'PYGATES' || log "WARN: could not parse $GATES — add the map-guard preToolUse entry manually (see docs/migrating-v0.17-to-v0.18.md)"
import json, os, tempfile, sys

GATES = ".github/hooks/espalier-gates.json"
with open(GATES) as f:
    data = json.load(f)
entries = data.setdefault("hooks", {}).setdefault("preToolUse", [])
entries.append({
    "type": "command",
    "matcher": "edit|write|create|apply_patch|str_replace_editor",
    "bash": "bash espalier/hooks/copilot-hook-adapter.sh map-guard.sh",
    "timeoutSec": 5
})
dirname = os.path.dirname(GATES) or "."
fd, tmp = tempfile.mkstemp(dir=dirname, suffix=".tmp", prefix=".gates-")
try:
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    with open(tmp) as f:
        json.load(f)
    os.replace(tmp, GATES)
    print("[migrate v0.17.0→v0.18.0]   copilot gates: map-guard entry added")
except Exception as e:
    os.unlink(tmp)
    print(f"ERROR: failed to write {GATES}: {e}", file=sys.stderr)
    sys.exit(1)
PYGATES
  fi
fi

# --- Instruction-file lane lines (grep-guarded, only where section exists) ----
_add_lane_line() {   # FILE INVOKE_PREFIX
  local f="$1" p="$2"
  [ -f "$f" ] || return 0
  grep -q "## Espalier" "$f" 2>/dev/null || return 0
  grep -qF "espalier-map" "$f" 2>/dev/null && return 0
  printf '\n**For multi-session planning** (an epic, a greenfield build — anything too big for one session), invoke `%sespalier-map <idea>` — charts a decision map under `espalier/maps/`, one ticket per session; a cleared map hands back FILED slices for `%sespalier`. It plans only, never codes.\n' "$p" "$p" >> "$f"
  log "added /espalier-map line to $f"
}
want_claude  && _add_lane_line CLAUDE.md "/"
want_codex   && _add_lane_line AGENTS.md "\$"
want_copilot && _add_lane_line .github/copilot-instructions.md "/"

# --- Verification --------------------------------------------------------------
pass=0; fail=0
check() { if eval "$2" >/dev/null 2>&1; then pass=$((pass+1)); echo "  ✓ $1"; else fail=$((fail+1)); echo "  ✗ $1"; fi; }

log "verification"
check "espalier-map skill installed"   "grep -q '^name: espalier-map' espalier/skills/espalier-map/SKILL.md"
check "map-guard hook executable"      "test -x espalier/hooks/map-guard.sh"
check "stats hook executable"          "test -x espalier/hooks/espalier-stats.sh"
check "maps dir"                       "test -d espalier/maps"
check "grill decision mode"            "grep -qF 'mode=decision' espalier/skills/espalier-grill/SKILL.md"
check "espalier SKILL slice adoption"  "grep -qF 'charted_from' espalier/skills/espalier/SKILL.md"
check "pipeline lanes note"            "grep -qF '/espalier-map' espalier/pipeline.md"
check "max-open-tickets key"           "grep -q '^max-open-tickets:' espalier/.espalier-config"
if want_claude; then
  check "settings.json map-guard"      "grep -qF 'map-guard' .claude/settings.json"
  check "claude symlink"               "[ -L .claude/skills/espalier-map ] && [ -e .claude/skills/espalier-map ]"
fi
if want_codex; then
  check "codex map-guard block"        "grep -qF 'ESPALIER MAP GUARD' .codex/config.toml"
  check "codex symlink"                "[ -L .agents/skills/espalier-map ] && [ -e .agents/skills/espalier-map ]"
fi
if want_copilot; then
  check "copilot symlink"              "[ -L .github/skills/espalier-map ] && [ -e .github/skills/espalier-map ]"
fi

echo
log "Verification: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || die "verification failed"
log "v0.18.0 migration complete. Chart your first map with /espalier-map <idea>; espalier/maps/ appears in git on its first commit."
