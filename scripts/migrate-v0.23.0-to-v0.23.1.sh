#!/bin/bash
# Migrate a v0.23.0 Espalier install to v0.23.1.
#
# v0.23.1 is the class-sweep patch. Field data (48 changes on a real v0.23.0
# install): most second and third Stage 4 panel rounds re-find the SAME
# defect one hop from the line just fixed — the panel named one instance,
# the coder fixed that instance, the sibling survived, and every hop cost a
# full 2-agent round. This patch makes a fix round close the defect CLASS:
#
#   - harness-coder.md: new "## Fix Rounds: Fix the Class, Not the Instance"
#     section — on a `FIX ROUND {n}:` prompt the coder names the violated
#     property, enumerates every sibling inside the change's scope (touched
#     layers + the generated surfaces they feed), fixes each on its own
#     read, and reports one `### Class Sweep` block per P0/P1. Out-of-scope
#     siblings are listed, never chased into a repo-wide refactor.
#   - harness-reviewer.md: Re-review Rounds step 4 — states the class in its
#     own words, searches independently, re-runs the coder's search, checks
#     every "not affected" claim and every fixed sibling; a gap is a P1
#     `[class-sweep]`.
#   - harness-security.md: Re-review Rounds step 4 — the same check for its
#     own findings (a fix bypass or an unlisted sibling door is a P1).
#   - pipeline.md, espalier SKILL, espalier-fix SKILL (pure copies): the
#     Stage 4 re-spawn prompt opens with the `FIX ROUND {n}:` header.
#
# The three agent files are per-project and anchored-edited; the inserted
# text is EXTRACTED FROM THE PLUGIN'S TEMPLATES at run time, so a migrated
# install is byte-identical to a fresh one in those sections. A customised
# file missing its anchor is skipped with a record in
# espalier/.migrations-skipped, never mangled. Backups at
# <file>.pre-v0.23.1.bak (once per file). No config keys, no hook wiring.
#
# Usage:
#   bash migrate-v0.23.0-to-v0.23.1.sh [--dry-run] [--yes] [--plugin-dir=<path>]

set -u

DRY_RUN=no
SKIP_PROMPT=no
PLUGIN_DIR="${ESPALIER_PLUGIN_DIR:-}"

for arg in "$@"; do
  case "$arg" in
    --dry-run)       DRY_RUN=yes ;;
    --yes)           SKIP_PROMPT=yes ;;
    --plugin-dir=*)  PLUGIN_DIR="${arg#--plugin-dir=}" ;;
    -h|--help)       sed -n '2,34p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown flag: $arg (use --help)" >&2; exit 2 ;;
  esac
done

log() { echo "[migrate v0.23.0→v0.23.1] $*"; }
die() { echo "[migrate v0.23.0→v0.23.1] ERROR: $*" >&2; exit 1; }

[ -d espalier ] || die "no espalier/ dir — run from the target project root."

# --- Locate plugin templates (probe: this patch's own marker) ----------------
if [ -z "$PLUGIN_DIR" ]; then
  _self_root="$(cd "$(dirname "$0")/.." && pwd)"
  [ -d "$_self_root/skills/espalier-init/templates" ] && PLUGIN_DIR="$_self_root"
fi
[ -n "$PLUGIN_DIR" ] || die "cannot locate the plugin. Pass --plugin-dir=<espalier-engineering root>."
TPL="$PLUGIN_DIR/skills/espalier-init/templates"

# --- v0.23.1 markers (also the idempotency check) ----------------------------
CODER_MARK='## Fix Rounds: Fix the Class, Not the Instance'
REV_MARK='**Class-sweep verification.**'
SEC_MARK='**Class-sweep verification (your own findings).**'
LANE_MARK='FIX ROUND {n}:'
SKIPFILE="espalier/.migrations-skipped"

grep -qF "$CODER_MARK" "$TPL/agents/harness-coder.md" 2>/dev/null \
  && grep -qF "$LANE_MARK" "$TPL/skills/espalier.md" 2>/dev/null \
  || die "plugin dir $PLUGIN_DIR is not v0.23.1 (templates lack the class-sweep text). Update the plugin first."

handled() {  # $1 = marker, $2 = file, $3 = skip label
  grep -qF "$1" "$2" 2>/dev/null || grep -qF "v0.23.1-$3" "$SKIPFILE" 2>/dev/null
}

missing=""
mark() { missing="$missing
  - $1"; }
grep -qF "$LANE_MARK" espalier/pipeline.md                  2>/dev/null || mark "pipeline.md FIX ROUND header"
grep -qF "$LANE_MARK" espalier/skills/espalier/SKILL.md     2>/dev/null || mark "espalier SKILL FIX ROUND re-spawn line"
grep -qF "$LANE_MARK" espalier/skills/espalier-fix/SKILL.md 2>/dev/null || mark "espalier-fix SKILL FIX ROUND re-spawn line"
handled "$CODER_MARK" espalier/agents/harness-coder.md    coder-class-sweep    || mark "coder Fix Rounds section"
handled "$REV_MARK"   espalier/agents/harness-reviewer.md reviewer-class-sweep || mark "reviewer class-sweep verification"
handled "$SEC_MARK"   espalier/agents/harness-security.md security-class-sweep || mark "security class-sweep verification"

if [ -z "$missing" ]; then
  log "already at v0.23.1 (every marker present). Nothing to do."
  exit 0
fi

if [ "$DRY_RUN" = yes ]; then
  log "DRY RUN — missing markers:$missing"
  log "DRY RUN — would refresh 3 pure-copy files (pipeline.md + 2 lane SKILLs; backup-on-diff → .pre-v0.23.1.bak)"
  log "DRY RUN — would anchored-edit the 3 agent files from the templates (skip-with-record if customised)"
  exit 0
fi

if [ "$SKIP_PROMPT" != yes ]; then
  echo "This migration will:"
  echo "  - refresh pipeline.md and the espalier / espalier-fix SKILLs from templates (backups: <file>.pre-v0.23.1.bak)"
  echo "  - insert the class-sweep text into the 3 agent files (customised files skipped, never mangled)"
  printf "Proceed? [y/N] "
  read -r ans
  case "$ans" in y|Y|yes|YES) ;; *) log "aborted."; exit 0 ;; esac
fi

# --- 1. Pure-copy refresh (backup-on-diff) -----------------------------------
refresh() {  # $1 = template path, $2 = installed path
  [ -f "$1" ] || die "template missing: $1"
  if [ -f "$2" ] && ! cmp -s "$1" "$2"; then
    cp "$2" "$2.pre-v0.23.1.bak"
  fi
  cp "$1" "$2"
  log "refreshed $2"
}
grep -qF "$LANE_MARK" espalier/pipeline.md 2>/dev/null \
  || refresh "$TPL/pipeline.md"            espalier/pipeline.md
grep -qF "$LANE_MARK" espalier/skills/espalier/SKILL.md 2>/dev/null \
  || refresh "$TPL/skills/espalier.md"     espalier/skills/espalier/SKILL.md
grep -qF "$LANE_MARK" espalier/skills/espalier-fix/SKILL.md 2>/dev/null \
  || refresh "$TPL/skills/espalier-fix.md" espalier/skills/espalier-fix/SKILL.md

# --- 2. Anchored edits (text extracted from the templates) -------------------
BLK=$(mktemp -t v0231blk.XXXX)
trap 'rm -f "$BLK"' EXIT

record_skip() {  # $1 = label, $2 = file, $3 = anchor description
  log "WARN: $2 is customised past the stock shape ($3 not found) — skipped."
  log "      Manual step: port the v0.23.1 '$1' text from the template yourself."
  grep -qF "v0.23.1-$1" "$SKIPFILE" 2>/dev/null \
    || echo "v0.23.1-$1: customised, manual port needed ($2)" >> "$SKIPFILE"
}

backup_once() { [ -f "$1.pre-v0.23.1.bak" ] || cp "$1" "$1.pre-v0.23.1.bak"; }

# extract_block TEMPLATE START END — lines from the first one containing START
# through the first later one containing END, inclusive, into $BLK. Dies on an
# empty result: that means the template drifted from this script's anchors.
extract_block() {
  awk -v start="$2" -v end="$3" '
    !insp && index($0, start) { insp=1 }
    insp { print }
    insp && index($0, end) { exit }
  ' "$1" > "$BLK"
  [ -s "$BLK" ] || die "template block '$2' … '$3' not found in $1 — plugin templates drifted; refusing to write an empty block."
}

# insert_after FILE ANCHOR — $BLK goes right after the first line containing ANCHOR.
insert_after() {
  local f="$1" anchor="$2" tmp="$1.v0231tmp"
  backup_once "$f"; cp "$f" "$tmp"
  awk -v blk="$BLK" -v anchor="$anchor" '
    { print }
    !done && index($0, anchor) {
      while ((getline line < blk) > 0) print line
      close(blk); done=1
    }
  ' "$tmp" > "$f"
  rm -f "$tmp"
}

# insert_before FILE ANCHOR — $BLK plus one blank line go right before the
# first line containing ANCHOR.
insert_before() {
  local f="$1" anchor="$2" tmp="$1.v0231tmp"
  backup_once "$f"; cp "$f" "$tmp"
  awk -v blk="$BLK" -v anchor="$anchor" '
    !done && index($0, anchor) {
      while ((getline line < blk) > 0) print line
      close(blk); print ""; done=1
    }
    { print }
  ' "$tmp" > "$f"
  rm -f "$tmp"
}

# 2a. coder — the Fix Rounds section sits immediately before Editing Discipline.
CODER=espalier/agents/harness-coder.md
if ! handled "$CODER_MARK" "$CODER" coder-class-sweep; then
  ANCH='## Editing Discipline'
  if grep -qF -- "$ANCH" "$CODER"; then
    extract_block "$TPL/agents/harness-coder.md" "$CODER_MARK" 'the reviewer files it as a P1 and the round repeats.'
    insert_before "$CODER" "$ANCH"
    log "inserted coder Fix Rounds (class sweep) section"
  else
    record_skip coder-class-sweep "$CODER" "the '## Editing Discipline' heading"
  fi
fi

# 2b. reviewer — step 4 of Re-review Rounds, right after step 3's last line.
REV=espalier/agents/harness-reviewer.md
if ! handled "$REV_MARK" "$REV" reviewer-class-sweep; then
  ANCH='re-spawned again after the next fix.'
  if grep -qF -- "$ANCH" "$REV"; then
    extract_block "$TPL/agents/harness-reviewer.md" "$REV_MARK" 'finding, filed early.'
    insert_after "$REV" "$ANCH"
    log "inserted reviewer class-sweep verification step"
  else
    record_skip reviewer-class-sweep "$REV" "the Re-review Rounds step-3 closing line"
  fi
fi

# 2c. security — step 4 of Re-review Rounds, right after step 3's last line.
SEC=espalier/agents/harness-security.md
if ! handled "$SEC_MARK" "$SEC" security-class-sweep; then
  ANCH='trusts no sensitive client value.'
  if grep -qF -- "$ANCH" "$SEC"; then
    extract_block "$TPL/agents/harness-security.md" "$SEC_MARK" 'sibling doors open is still open.'
    insert_after "$SEC" "$ANCH"
    log "inserted security class-sweep verification step"
  else
    record_skip security-class-sweep "$SEC" "the Re-review Rounds step-3 closing line"
  fi
fi

# --- Verify ------------------------------------------------------------------
grep -qF "$LANE_MARK" espalier/pipeline.md                  || die "post-migration verification failed: pipeline.md lacks '$LANE_MARK'"
grep -qF "$LANE_MARK" espalier/skills/espalier/SKILL.md     || die "post-migration verification failed: espalier SKILL lacks '$LANE_MARK'"
grep -qF "$LANE_MARK" espalier/skills/espalier-fix/SKILL.md || die "post-migration verification failed: espalier-fix SKILL lacks '$LANE_MARK'"
handled "$CODER_MARK" "$CODER" coder-class-sweep    || die "post-migration verification failed: coder lacks '$CODER_MARK'"
handled "$REV_MARK"   "$REV"   reviewer-class-sweep || die "post-migration verification failed: reviewer lacks '$REV_MARK'"
handled "$SEC_MARK"   "$SEC"   security-class-sweep || die "post-migration verification failed: security lacks '$SEC_MARK'"

log "done. v0.23.1 applied — backups at <file>.pre-v0.23.1.bak."
log "Fix rounds now close the defect class: the coder sweeps in-scope siblings"
log "and reports a Class Sweep block; both panel agents re-verify it."
exit 0
