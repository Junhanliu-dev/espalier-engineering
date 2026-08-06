#!/bin/bash
# Migrate a v0.15.0 Espalier install to v0.16.0.
#
# v0.16.0 is the multi-dev maintenance compatibility floor (Release A):
#
#   1. Pure-copy refresh (backup-on-diff → <file>.pre-v0.16.bak):
#        espalier/pipeline.md, the espalier / espalier-fix / espalier-prune /
#        espalier-doctor SKILL.md files, and espalier/hooks/drift-helpers.sh
#        (which gains the conv_fold/conv_observations conventions reader).
#   2. Surgical append: the `## Maintenance Commits` section (marker
#        `ESPALIER MAINTENANCE COMMITS v1`) onto the per-project
#        espalier/rules/development-process.md — end-of-file append, skipped
#        when the marker is present, abort-with-notice when the file is
#        missing. Backup <file>.pre-v0.16.bak.
#   3. Re-wire via `bootstrap --wire-only` (merge decision read back from
#        espalier/.merge-hook-decision): appends the .gitattributes union
#        entry (espalier/.ask-gaps.tsv merge=union), the canonical-remote /
#        canonical-branch config keys, the optional CODEOWNERS block, and
#        runs the 48/53/58-check validation.
#        SIDE-EFFECT: bootstrap Stage 8 backs up .claude/settings.json to
#        .claude/settings.json.espalier-backup-<epoch> before its merge.
#
#   CODEOWNERS: the /espalier-migrate skill collects the two handles
#   interactively and passes --codeowners-rules/--codeowners-wiki; this
#   script NEVER prompts for them (unattended runs skip the block).
#
# Detection requires EVERY mandatory marker, not a proxy subset: earlier
# chain steps run the current bootstrap with --force, which after a plugin
# upgrade can pre-install the config/attribute artifacts — a two-marker
# detector would then skip the still-missing surgical rule edit.
#
# Usage:
#   bash migrate-v0.15.0-to-v0.16.0.sh [--dry-run] [--yes]
#        [--codeowners-rules=<@handle>] [--codeowners-wiki=<@handle>]
#        [--plugin-dir=<path>]

set -u

DRY_RUN=no
SKIP_PROMPT=no
PLUGIN_DIR="${ESPALIER_PLUGIN_DIR:-}"
CODEOWNERS_RULES=""
CODEOWNERS_WIKI=""

for arg in "$@"; do
  case "$arg" in
    --dry-run)              DRY_RUN=yes ;;
    --yes)                  SKIP_PROMPT=yes ;;
    --plugin-dir=*)         PLUGIN_DIR="${arg#--plugin-dir=}" ;;
    --codeowners-rules=*)   CODEOWNERS_RULES="${arg#--codeowners-rules=}" ;;
    --codeowners-wiki=*)    CODEOWNERS_WIKI="${arg#--codeowners-wiki=}" ;;
    -h|--help)              sed -n '2,41p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown flag: $arg (use --help)" >&2; exit 2 ;;
  esac
done

log() { echo "[migrate v0.15.0→v0.16.0] $*"; }
die() { echo "[migrate v0.15.0→v0.16.0] ERROR: $*" >&2; exit 1; }

[ -d espalier ] || die "no espalier/ dir — run from the target project root."
[ -f espalier/.merge-hook-decision ] \
  || die "espalier/.merge-hook-decision missing — not a complete install (finish /espalier-init first)."
DECISION=$(head -1 espalier/.merge-hook-decision | tr -d '[:space:]')

# --- Locate plugin templates -------------------------------------------------
if [ -z "$PLUGIN_DIR" ]; then
  _self_root="$(cd "$(dirname "$0")/.." && pwd)"
  [ -d "$_self_root/skills/espalier-init/hook-templates" ] && PLUGIN_DIR="$_self_root"
fi
[ -n "$PLUGIN_DIR" ] || die "cannot locate the plugin. Pass --plugin-dir=<espalier-engineering root>."
TPL="$PLUGIN_DIR/skills/espalier-init"
grep -qF 'conv_fold' "$TPL/hook-templates/drift-helpers.sh" 2>/dev/null \
  || die "plugin dir $PLUGIN_DIR is not v0.16.0 (drift-helpers template lacks conv_fold). Update the plugin first."
DEVPROC_TPL="$TPL/templates/rules/development-process.md"
grep -qF 'ESPALIER MAINTENANCE COMMITS v1' "$DEVPROC_TPL" 2>/dev/null \
  || die "plugin template missing the Maintenance Commits section — update the plugin."

DEVPROC="espalier/rules/development-process.md"

# Pure-copy refresh set: "<installed>|<template>"
COPY_PAIRS="espalier/pipeline.md|$TPL/templates/pipeline.md
espalier/skills/espalier/SKILL.md|$TPL/templates/skills/espalier.md
espalier/skills/espalier-fix/SKILL.md|$TPL/templates/skills/espalier-fix.md
espalier/skills/espalier-prune/SKILL.md|$TPL/templates/skills/espalier-prune.md
espalier/skills/espalier-doctor/SKILL.md|$TPL/templates/skills/espalier-doctor.md
espalier/hooks/drift-helpers.sh|$TPL/hook-templates/drift-helpers.sh"

# --- Detection: EVERY mandatory marker ---------------------------------------
missing=""
mark() { missing="$missing
  - $1"; }

grep -qxF 'espalier/.ask-gaps.tsv merge=union' .gitattributes 2>/dev/null \
  || mark ".gitattributes union entry (espalier/.ask-gaps.tsv merge=union)"
grep -qE '^canonical-remote: .+' espalier/.espalier-config 2>/dev/null \
  || mark "canonical-remote key in espalier/.espalier-config"
grep -qE '^canonical-branch: .+' espalier/.espalier-config 2>/dev/null \
  || mark "canonical-branch key in espalier/.espalier-config"
grep -qF 'ESPALIER MAINTENANCE COMMITS v1' "$DEVPROC" 2>/dev/null \
  || mark "## Maintenance Commits section in $DEVPROC"
grep -qF 'Multi-Developer Maintenance' espalier/pipeline.md 2>/dev/null \
  || mark "pipeline.md multi-dev maintenance section"
grep -qF 'Multi-Developer Discipline' espalier/skills/espalier-prune/SKILL.md 2>/dev/null \
  || mark "espalier-prune maintenance-lane section"
grep -qF 'Multi-Developer Discipline' espalier/skills/espalier-doctor/SKILL.md 2>/dev/null \
  || mark "espalier-doctor maintenance-lane section"
grep -qF 'conv_fold' espalier/skills/espalier/SKILL.md 2>/dev/null \
  || mark "espalier SKILL conv_fold call sites"
grep -qF 'conv_fold' espalier/skills/espalier-fix/SKILL.md 2>/dev/null \
  || mark "espalier-fix SKILL conv_fold call sites"
grep -qF 'conv_fold' espalier/hooks/drift-helpers.sh 2>/dev/null \
  || mark "drift-helpers.sh conv_fold reader"

if [ -z "$missing" ]; then
  log "already at v0.16.0 (every marker present). Nothing to do."
  exit 0
fi

if [ "$DRY_RUN" = yes ]; then
  log "DRY RUN — missing markers:$missing"
  log "DRY RUN — would:"
  echo "$COPY_PAIRS" | while IFS='|' read -r dst src; do
    [ -n "$dst" ] || continue
    if [ -f "$dst" ] && ! cmp -s "$dst" "$src"; then
      log "  refresh $dst (backup → $dst.pre-v0.16.bak)"
    elif [ ! -f "$dst" ]; then
      log "  install $dst (missing — new copy, no backup)"
    else
      log "  $dst already matches the template (no copy, no backup)"
    fi
  done
  if ! grep -qF 'ESPALIER MAINTENANCE COMMITS v1' "$DEVPROC" 2>/dev/null; then
    log "  append '## Maintenance Commits' to $DEVPROC (backup → $DEVPROC.pre-v0.16.bak)"
  fi
  log "  re-wire: bootstrap --wire-only --merge-decision=$DECISION (appends the"
  log "    .gitattributes entry + canonical config keys, runs 48/53/58 validation;"
  log "    side-effect: .claude/settings.json backed up before its hook merge)"
  [ -n "$CODEOWNERS_RULES$CODEOWNERS_WIKI" ] \
    && log "  CODEOWNERS block (rules=$CODEOWNERS_RULES wiki=$CODEOWNERS_WIKI)" \
    || log "  CODEOWNERS: no handles passed — skipped"
  exit 0
fi

if [ "$SKIP_PROMPT" != yes ]; then
  printf "Apply the v0.16.0 migration (multi-dev maintenance floor)? [y/N] "
  read -r reply
  case "$reply" in [yY]*) ;; *) echo "Aborted."; exit 0 ;; esac
fi

# --- Step 1: pure-copy refresh with backup-on-diff ----------------------------
log "Step 1: pure-copy refresh (backup-on-diff → <file>.pre-v0.16.bak)"
echo "$COPY_PAIRS" | while IFS='|' read -r dst src; do
  [ -n "$dst" ] || continue
  [ -f "$src" ] || { echo "  WARN: plugin template missing: $src" >&2; continue; }
  if [ -f "$dst" ] && cmp -s "$dst" "$src"; then
    log "  unchanged: $dst"
    continue
  fi
  if [ -f "$dst" ]; then
    cp "$dst" "$dst.pre-v0.16.bak"
    log "  backed up: $dst → $dst.pre-v0.16.bak"
  fi
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  log "  refreshed: $dst"
done
chmod +x espalier/hooks/drift-helpers.sh 2>/dev/null || true

# --- Step 2: surgical append of the Maintenance Commits section ---------------
log "Step 2: Maintenance Commits section in $DEVPROC"
if [ ! -f "$DEVPROC" ]; then
  die "$DEVPROC is missing — restore it (re-run espalier-init Phase 2) and re-run this migration."
fi
if grep -qF 'ESPALIER MAINTENANCE COMMITS v1' "$DEVPROC"; then
  log "  marker already present — skipping the append"
else
  cp "$DEVPROC" "$DEVPROC.pre-v0.16.bak"
  log "  backed up: $DEVPROC → $DEVPROC.pre-v0.16.bak"
  # End-of-file append, section text extracted from the template (single
  # source of truth — the section is fixed policy text, last in the template).
  [ -n "$(tail -c1 "$DEVPROC")" ] && printf '\n' >> "$DEVPROC"
  printf '\n' >> "$DEVPROC"
  sed -n '/^## Maintenance Commits$/,$p' "$DEVPROC_TPL" >> "$DEVPROC"
  log "  appended '## Maintenance Commits' (ESPALIER MAINTENANCE COMMITS v1)"
fi

# --- Step 3: re-wire (gitattributes + config keys + CODEOWNERS + validation) --
log "Step 3: bootstrap --wire-only (merge-decision=$DECISION)"
log "  side-effect: .claude/settings.json is backed up to .claude/settings.json.espalier-backup-<epoch> before its hook merge"
CO_FLAGS=""
[ -n "$CODEOWNERS_RULES" ] && CO_FLAGS="--codeowners-rules=$CODEOWNERS_RULES"
[ -n "$CODEOWNERS_WIKI" ]  && CO_FLAGS="$CO_FLAGS --codeowners-wiki=$CODEOWNERS_WIKI"
# shellcheck disable=SC2086
bash "$PLUGIN_DIR/scripts/bootstrap-espalier.sh" \
  --project-dir=. \
  --plugin-dir="$TPL" \
  --wire-only \
  --merge-decision="$DECISION" \
  --yes \
  $CO_FLAGS \
  || die "wire-only bootstrap failed — see output above"

# --- Verification --------------------------------------------------------------
pass=0; fail=0
check() { if eval "$2" >/dev/null 2>&1; then pass=$((pass+1)); echo "  ✓ $1"; else fail=$((fail+1)); echo "  ✗ $1"; fi; }

log "verification"
check "gitattributes union entry"         "grep -qxF 'espalier/.ask-gaps.tsv merge=union' .gitattributes"
check "canonical-remote key"              "grep -qE '^canonical-remote: .+' espalier/.espalier-config"
check "canonical-branch key"              "grep -qE '^canonical-branch: .+' espalier/.espalier-config"
check "Maintenance Commits marker"        "grep -qF 'ESPALIER MAINTENANCE COMMITS v1' '$DEVPROC'"
check "pipeline multi-dev section"        "grep -qF 'Multi-Developer Maintenance' espalier/pipeline.md"
check "prune lane section"                "grep -qF 'Multi-Developer Discipline' espalier/skills/espalier-prune/SKILL.md"
check "doctor lane section"               "grep -qF 'Multi-Developer Discipline' espalier/skills/espalier-doctor/SKILL.md"
check "espalier SKILL conv_fold"          "grep -qF 'conv_fold' espalier/skills/espalier/SKILL.md"
check "espalier-fix SKILL conv_fold"      "grep -qF 'conv_fold' espalier/skills/espalier-fix/SKILL.md"
check "drift-helpers conv_fold reader"    "grep -qF 'conv_fold' espalier/hooks/drift-helpers.sh && test -x espalier/hooks/drift-helpers.sh"
if [ -n "$CODEOWNERS_RULES$CODEOWNERS_WIKI" ]; then
  check "CODEOWNERS marker block"         "grep -rqF '>>> ESPALIER OWNERS v1 >>>' .github/CODEOWNERS CODEOWNERS docs/CODEOWNERS 2>/dev/null"
fi

echo
log "Verification: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || die "verification failed"
log "v0.16.0 migration complete. Touched paths are listed above (incl. .pre-v0.16.bak backups and the settings.json backup)."
