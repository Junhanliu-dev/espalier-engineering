#!/bin/bash
# Migrate a v0.16.0 Espalier install to v0.17.0.
#
# v0.17.0 is multi-dev maintenance Release B-team: the weekly gardener rota,
# the tracked single-line `espalier/.doctor-stamp` (clean/dirty semantics),
# and conventions file-per-key under `espalier/conventions/`. Everything
# rides pure-copy files:
#
#   - Refresh (backup-on-diff → <file>.pre-v0.17.bak): espalier/pipeline.md,
#     the espalier / espalier-fix / espalier-prune / espalier-doctor SKILL.md
#     files, and espalier/hooks/drift-helpers.sh (doctor_due v2 + shared
#     stamp writer + conv_slug + per-key append_convention).
#   - NO config change, NO .gitattributes change, NO data migration: the
#     per-key dir and the stamp file appear on first write; the legacy
#     .conventions.tsv is read forever and written never.
#   - Run-time safety assert: the tracked espalier/.doctor-stamp must NOT be
#     gitignored (target repos can carry hand-added ignore lines the
#     template never wrote) — `git check-ignore` must fail.
#
# Usage:
#   bash migrate-v0.16.0-to-v0.17.0.sh [--dry-run] [--yes] [--plugin-dir=<path>]

set -u

DRY_RUN=no
SKIP_PROMPT=no
PLUGIN_DIR="${ESPALIER_PLUGIN_DIR:-}"

for arg in "$@"; do
  case "$arg" in
    --dry-run)       DRY_RUN=yes ;;
    --yes)           SKIP_PROMPT=yes ;;
    --plugin-dir=*)  PLUGIN_DIR="${arg#--plugin-dir=}" ;;
    -h|--help)       sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown flag: $arg (use --help)" >&2; exit 2 ;;
  esac
done

log() { echo "[migrate v0.16.0→v0.17.0] $*"; }
die() { echo "[migrate v0.16.0→v0.17.0] ERROR: $*" >&2; exit 1; }

[ -d espalier ] || die "no espalier/ dir — run from the target project root."

# --- Locate plugin templates -------------------------------------------------
if [ -z "$PLUGIN_DIR" ]; then
  _self_root="$(cd "$(dirname "$0")/.." && pwd)"
  [ -d "$_self_root/skills/espalier-init/hook-templates" ] && PLUGIN_DIR="$_self_root"
fi
[ -n "$PLUGIN_DIR" ] || die "cannot locate the plugin. Pass --plugin-dir=<espalier-engineering root>."
TPL="$PLUGIN_DIR/skills/espalier-init"
grep -qF 'doctor_stamp_shared' "$TPL/hook-templates/drift-helpers.sh" 2>/dev/null \
  || die "plugin dir $PLUGIN_DIR is not v0.17.0 (drift-helpers template lacks doctor_stamp_shared). Update the plugin first."

# The tracked stamp must not be ignored — verified at RUN TIME because target
# repos can carry hand-added ignore lines the template never wrote.
if git check-ignore -q espalier/.doctor-stamp 2>/dev/null; then
  die "espalier/.doctor-stamp is matched by a .gitignore rule — the shared doctor stamp MUST be tracked. Remove that ignore line, then re-run."
fi

COPY_PAIRS="espalier/pipeline.md|$TPL/templates/pipeline.md
espalier/skills/espalier/SKILL.md|$TPL/templates/skills/espalier.md
espalier/skills/espalier-fix/SKILL.md|$TPL/templates/skills/espalier-fix.md
espalier/skills/espalier-prune/SKILL.md|$TPL/templates/skills/espalier-prune.md
espalier/skills/espalier-doctor/SKILL.md|$TPL/templates/skills/espalier-doctor.md
espalier/hooks/drift-helpers.sh|$TPL/hook-templates/drift-helpers.sh"

# --- Idempotency: every v0.17 marker -----------------------------------------
missing=""
mark() { missing="$missing
  - $1"; }
grep -qF 'doctor_stamp_shared' espalier/hooks/drift-helpers.sh 2>/dev/null \
  || mark "drift-helpers.sh shared-stamp writer + doctor_due v2"
grep -qF 'doctor_stamp_shared' espalier/skills/espalier-doctor/SKILL.md 2>/dev/null \
  || mark "espalier-doctor shared-stamp protocol"
grep -qiF 'gardener' espalier/skills/espalier-prune/SKILL.md 2>/dev/null \
  || mark "espalier-prune gardener rota"
grep -qiF 'gardener rota' espalier/skills/espalier/SKILL.md 2>/dev/null \
  || mark "espalier SKILL Stage 0 Proceed default"
grep -qiF 'gardener rota' espalier/skills/espalier-fix/SKILL.md 2>/dev/null \
  || mark "espalier-fix SKILL Stage 0 Proceed default"
grep -qiF 'keep both lines' espalier/pipeline.md 2>/dev/null \
  || mark "pipeline.md per-key conflict playbook"

if [ -z "$missing" ]; then
  log "already at v0.17.0 (every marker present). Nothing to do."
  exit 0
fi

if [ "$DRY_RUN" = yes ]; then
  log "DRY RUN — missing markers:$missing"
  log "DRY RUN — would refresh (backup-on-diff → <file>.pre-v0.17.bak):"
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
  log "DRY RUN — no config change, no attribute change, no data migration"
  exit 0
fi

if [ "$SKIP_PROMPT" != yes ]; then
  printf "Apply the v0.17.0 migration (gardener rota + shared stamp + file-per-key)? [y/N] "
  read -r reply
  case "$reply" in [yY]*) ;; *) echo "Aborted."; exit 0 ;; esac
fi

log "refreshing pure-copy files (backup-on-diff → <file>.pre-v0.17.bak)"
echo "$COPY_PAIRS" | while IFS='|' read -r dst src; do
  [ -n "$dst" ] || continue
  [ -f "$src" ] || { echo "  WARN: plugin template missing: $src" >&2; continue; }
  if [ -f "$dst" ] && cmp -s "$dst" "$src"; then
    log "  unchanged: $dst"
    continue
  fi
  if [ -f "$dst" ]; then
    cp "$dst" "$dst.pre-v0.17.bak"
    log "  backed up: $dst → $dst.pre-v0.17.bak"
  fi
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  log "  refreshed: $dst"
done
chmod +x espalier/hooks/drift-helpers.sh 2>/dev/null || true

# --- Verification --------------------------------------------------------------
pass=0; fail=0
check() { if eval "$2" >/dev/null 2>&1; then pass=$((pass+1)); echo "  ✓ $1"; else fail=$((fail+1)); echo "  ✗ $1"; fi; }

log "verification"
check "drift-helpers: doctor_due v2 + stamp writer" "grep -qF 'doctor_stamp_shared' espalier/hooks/drift-helpers.sh && grep -qF 'conv_slug' espalier/hooks/drift-helpers.sh"
check "doctor skill: shared-stamp protocol"         "grep -qF 'doctor_stamp_shared' espalier/skills/espalier-doctor/SKILL.md && grep -qiF 'keep the newer line' espalier/skills/espalier-doctor/SKILL.md"
check "prune skill: gardener rota"                  "grep -qiF 'gardener' espalier/skills/espalier-prune/SKILL.md"
check "Stage 0 Proceed defaults (both lanes)"       "grep -qiF 'gardener rota' espalier/skills/espalier/SKILL.md && grep -qiF 'gardener rota' espalier/skills/espalier-fix/SKILL.md"
check "pipeline: per-key conflict playbook"         "grep -qiF 'keep both lines' espalier/pipeline.md"
check ".doctor-stamp not gitignored"                "! git check-ignore -q espalier/.doctor-stamp"

echo
log "Verification: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || die "verification failed"
log "v0.17.0 migration complete. The per-key dir and the shared stamp appear on first write; the legacy .conventions.tsv stays read-only forever."
