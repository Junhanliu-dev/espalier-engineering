#!/bin/bash
# Migrate a v0.27.0 Espalier install to v0.28.0.
#
# v0.28.0 is the ceiling-ledger release (second ponytail transplant — idea
# level, MIT; design in docs/ponytail-v4-transplant-plan.md). Contract-equal
# to v0.27.0: every gate, rubric, sentinel, round cap, and escalation path is
# unchanged; every new finding is advisory (P3); NOTHING here sets a budget.
#
#   - Pure-copy refresh (backup-on-diff → <file>.pre-v0.28.bak):
#     the espalier-grill and espalier-simplify SKILLs;
#     espalier/hooks/espalier-stats.sh; NEW
#     espalier/skills/espalier-coding/references/platform-native.md (the
#     ladder's rung-4 lookup — write-if-absent, refreshed on diff).
#   - Anchored edits, text EXTRACTED from the plugin templates at run time so
#     a migrated install is byte-identical to a fresh one in those sections:
#     harness-coder.md (rung 4 names the lookup; the "Mark a real corner"
#     block; the ladder floor's calibration clause; Change Impact step 1's
#     fix-placement clause); harness-reviewer.md (the `shrink:` tag; the
#     Ceiling-markers paragraph); rules/coding-standards.md (the marker as
#     the named comment case). A customised file missing its anchor is
#     skipped with a record in espalier/.migrations-skipped, never mangled.
#   No config key, no new instruction-file line, no hooks, no symlinks.
#
# Usage:
#   bash migrate-v0.27.0-to-v0.28.0.sh [--dry-run] [--yes] [--plugin-dir=<path>]

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

log() { echo "[migrate v0.27.0→v0.28.0] $*"; }
die() { echo "[migrate v0.27.0→v0.28.0] ERROR: $*" >&2; exit 1; }

[ -d espalier ] || die "no espalier/ dir — run from the target project root."

# --- Locate plugin templates (probe: this release's own lookup file) --------
if [ -z "$PLUGIN_DIR" ]; then
  _self_root="$(cd "$(dirname "$0")/.." && pwd)"
  [ -d "$_self_root/skills/espalier-init/templates" ] && PLUGIN_DIR="$_self_root"
fi
[ -n "$PLUGIN_DIR" ] || die "cannot locate the plugin. Pass --plugin-dir=<espalier-engineering root>."
TPL="$PLUGIN_DIR/skills/espalier-init/templates"
HTPL="$PLUGIN_DIR/skills/espalier-init/hook-templates"
SKIPFILE="espalier/.migrations-skipped"
REF_TPL="$TPL/skills/espalier-coding-references/platform-native.md"
REF="espalier/skills/espalier-coding/references/platform-native.md"

# --- v0.28.0 markers (also the idempotency check) ----------------------------
STATS_MARK='ceilings: markers='
GRILL_MARK='Over-specified mechanism'
SIMP_MARK='CEILING MARKERS'
# coder
CODER_RUNG4='not reading for every task.'                       # marker (last line of the rung-4 addition)
CODER_RUNG4_START='When this rung decides, open'
CODER_RUNG4_ANCHOR='requirements.md naming it.'                 # insert AFTER this line
CODER_FLOOR='never trimmed to the ideal value.'                 # marker (last line of the new floor paragraph)
CODER_FLOOR_START='The ladder is never a licence to trim a trust boundary'
CODER_FLOOR_OLD_END='Production-Aware sections below are the floor, not rungs.'
CODER_CORNER='**Mark a real corner.**'
CODER_CORNER_END='so the reviewer confirms it instead of hunting for it.'
CODER_IMPACT='The fix lands where every caller routes'
CODER_IMPACT_START='1. **Enumerate every surface that produces'
CODER_IMPACT_OLD_END='THIS project — let them, not assumption, define the list.'
CODER_IMPACT_END='caller broken and returns as a fix round.'
# reviewer
REV_SHRINK='- `shrink:` the same logic in fewer lines.'
REV_SHRINK_END='own tie-break.'
REV_SHRINK_ANCHOR='layer with one caller — unless a documented pattern mandates it.'   # insert AFTER
REV_CEIL='**Ceiling markers (P3).**'
REV_CEIL_END='trigger to revisit; Fix = the trigger.'
REV_CEIL_ANCHOR='**The one P1 — a NEW dependency:**'            # insert BEFORE (gap)
# coding-standards
STD_MARK='- A deliberate shortcut with a known ceiling carries the one allowed line,'
STD_END='per shortcut, greppable (`harness-coder.md` → Solution Selection Ladder).'
STD_ANCHOR='merely repeats what the line already says.'          # insert AFTER

[ -f "$REF_TPL" ] \
  && grep -qF -- "$CODER_CORNER" "$TPL/agents/harness-coder.md" 2>/dev/null \
  && grep -qF -- "$REV_CEIL" "$TPL/agents/harness-reviewer.md" 2>/dev/null \
  && grep -qF -- "$STD_MARK" "$TPL/rules/coding-standards.md" 2>/dev/null \
  && grep -qF -- "$GRILL_MARK" "$TPL/skills/espalier-grill.md" 2>/dev/null \
  && grep -qF -- "$SIMP_MARK" "$TPL/skills/espalier-simplify.md" 2>/dev/null \
  && grep -qF -- "$STATS_MARK" "$HTPL/espalier-stats.sh" 2>/dev/null \
  || die "plugin dir $PLUGIN_DIR is not v0.28.0 (templates lack the ceiling ledger). Update the plugin first."

handled() {  # $1 = marker, $2 = file, $3 = skip label
  grep -qF -- "$1" "$2" 2>/dev/null || grep -qF "v0.28.0-$3" "$SKIPFILE" 2>/dev/null
}

missing=""
mark() { missing="$missing
  - $1"; }
cmp -s "$REF_TPL" "$REF" 2>/dev/null                                || mark "espalier-coding references/platform-native.md (rung-4 lookup)"
grep -qF -- "$STATS_MARK" espalier/hooks/espalier-stats.sh 2>/dev/null || mark "espalier-stats.sh ceiling-marker ledger"
grep -qF -- "$GRILL_MARK" espalier/skills/espalier-grill/SKILL.md 2>/dev/null   || mark "espalier-grill SKILL (over-specified-mechanism signal)"
grep -qF -- "$SIMP_MARK"  espalier/skills/espalier-simplify/SKILL.md 2>/dev/null || mark "espalier-simplify SKILL (ceiling markers as leads)"
CODER=espalier/agents/harness-coder.md
REV=espalier/agents/harness-reviewer.md
STD=espalier/rules/coding-standards.md
handled "$CODER_RUNG4"  "$CODER" coder-rung4-lookup    || mark "coder ladder rung 4 — names the platform-native lookup"
handled "$CODER_FLOOR"  "$CODER" coder-floor-calibration || mark "coder ladder floor — calibration clause"
handled "$CODER_CORNER" "$CODER" coder-ceiling-marker  || mark "coder 'Mark a real corner' — the ceiling: marker rule"
handled "$CODER_IMPACT" "$CODER" coder-fix-placement   || mark "coder Change Impact step 1 — fix-placement clause"
handled "$REV_SHRINK"   "$REV" reviewer-shrink-tag     || mark "reviewer Minimalism Review — shrink: tag"
handled "$REV_CEIL"     "$REV" reviewer-ceiling-rows   || mark "reviewer Minimalism Review — [ceiling] / [no-trigger] rows"
handled "$STD_MARK"     "$STD" standards-ceiling-comment || mark "coding-standards Comments — the ceiling: line as the named case"

if [ -z "$missing" ]; then
  log "already at v0.28.0 (every marker present). Nothing to do."
  exit 0
fi

if [ "$DRY_RUN" = yes ]; then
  log "DRY RUN — missing markers:$missing"
  log "DRY RUN — would refresh up to 4 pure-copy files (the espalier-grill / espalier-simplify SKILLs, espalier-stats.sh, the new references/platform-native.md; backup-on-diff → .pre-v0.28.bak)"
  log "DRY RUN — would anchored-edit harness-coder.md, harness-reviewer.md and rules/coding-standards.md from the templates (skip-with-record if customised; no-op where the v0.28 text is already present)"
  exit 0
fi

if [ "$SKIP_PROMPT" != yes ]; then
  echo "This migration will:"
  echo "  - refresh the espalier-grill / espalier-simplify SKILLs and espalier-stats.sh from templates, add references/platform-native.md (backups: <file>.pre-v0.28.bak)"
  echo "  - insert the v0.28 text into harness-coder.md / harness-reviewer.md / rules/coding-standards.md (customised files skipped, never mangled)"
  printf "Proceed? [y/N] "
  read -r ans
  case "$ans" in y|Y|yes|YES) ;; *) log "aborted."; exit 0 ;; esac
fi

backup_once() { [ -f "$1.pre-v0.28.bak" ] || cp "$1" "$1.pre-v0.28.bak"; }

# --- 1. Pure-copy refresh (backup-on-diff) -----------------------------------
refresh() {  # $1 = template path, $2 = installed path
  [ -f "$1" ] || die "template missing: $1"
  if [ -f "$2" ] && ! cmp -s "$1" "$2"; then
    cp "$2" "$2.pre-v0.28.bak"
  fi
  cp "$1" "$2"
  log "refreshed $2"
}
mkdir -p "$(dirname "$REF")"
cmp -s "$REF_TPL" "$REF" 2>/dev/null || refresh "$REF_TPL" "$REF"
grep -qF -- "$GRILL_MARK" espalier/skills/espalier-grill/SKILL.md 2>/dev/null    || refresh "$TPL/skills/espalier-grill.md"    espalier/skills/espalier-grill/SKILL.md
grep -qF -- "$SIMP_MARK"  espalier/skills/espalier-simplify/SKILL.md 2>/dev/null || refresh "$TPL/skills/espalier-simplify.md" espalier/skills/espalier-simplify/SKILL.md
if ! grep -qF -- "$STATS_MARK" espalier/hooks/espalier-stats.sh 2>/dev/null; then
  refresh "$HTPL/espalier-stats.sh" espalier/hooks/espalier-stats.sh
  chmod +x espalier/hooks/espalier-stats.sh 2>/dev/null || true
fi

# --- 2. Anchored edits (text extracted from the templates) -------------------
BLK=$(mktemp -t v0280blk.XXXX)
trap 'rm -f "$BLK"' EXIT

record_skip() {  # $1 = label, $2 = file, $3 = anchor description
  log "WARN: $2 is customised past the stock shape ($3 not found) — skipped."
  log "      Manual step: port the v0.28.0 '$1' text from the template yourself."
  grep -qF "v0.28.0-$1" "$SKIPFILE" 2>/dev/null \
    || echo "v0.28.0-$1: customised, manual port needed ($2)" >> "$SKIPFILE"
}

# extract_block TEMPLATE START END — lines from the first one containing START
# through the first later one containing END, inclusive, into $BLK. Dies on an
# empty result OR when END never matched.
extract_block() {
  awk -v start="$2" -v end="$3" '
    !insp && index($0, start) { insp=1 }
    insp { print }
    insp && index($0, end) { exit }
  ' "$1" > "$BLK"
  [ -s "$BLK" ] || die "template block '$2' … '$3' not found in $1 — plugin templates drifted; refusing to write an empty block."
  tail -1 "$BLK" | grep -qF -- "$3" \
    || die "template block '$2' has no END line '$3' in $1 — plugin templates drifted; refusing to write an unbounded block."
}

span_present() {  # FILE START END
  awk -v start="$2" -v end="$3" '
    !insp && index($0, start) { insp=1 }
    insp && index($0, end) { found=1; exit }
    END { exit !found }
  ' "$1" 2>/dev/null
}

# insert_before FILE ANCHOR — $BLK plus one blank line go right before the
# first line containing ANCHOR.
insert_before() {
  local f="$1" anchor="$2" tmp="$1.v0280tmp"
  backup_once "$f"
  cp "$f" "$tmp"
  awk -v blk="$BLK" -v anchor="$anchor" '
    !done && index($0, anchor) {
      while ((getline line < blk) > 0) print line
      close(blk); print ""; done=1
    }
    { print }
  ' "$tmp" > "$f"
  rm -f "$tmp"
}

# insert_after FILE ANCHOR — $BLK goes right after the first line containing
# ANCHOR, no blank line (a list continuation or a sibling bullet).
insert_after() {
  local f="$1" anchor="$2" tmp="$1.v0280tmp"
  backup_once "$f"
  cp "$f" "$tmp"
  awk -v blk="$BLK" -v anchor="$anchor" '
    { print }
    !done && index($0, anchor) {
      while ((getline line < blk) > 0) print line
      close(blk); done=1
    }
  ' "$tmp" > "$f"
  rm -f "$tmp"
}

# swap_block FILE START END — the span from the first line containing START
# through the first later line containing END (inclusive) becomes $BLK.
swap_block() {
  local f="$1" start="$2" end="$3" tmp="$1.v0280tmp"
  backup_once "$f"
  cp "$f" "$tmp"
  awk -v blk="$BLK" -v start="$start" -v end="$end" '
    !done && !insp && index($0, start) { insp=1 }
    insp {
      if (index($0, end)) {
        while ((getline line < blk) > 0) print line
        close(blk); insp=0; done=1
      }
      next
    }
    { print }
  ' "$tmp" > "$f"
  rm -f "$tmp"
}

_tpl_of() {  # installed path → template path (relative to $TPL)
  case "$1" in
    espalier/agents/harness-coder.md)    echo agents/harness-coder.md ;;
    espalier/agents/harness-reviewer.md) echo agents/harness-reviewer.md ;;
    espalier/rules/coding-standards.md)  echo rules/coding-standards.md ;;
    *) die "no template mapping for $1" ;;
  esac
}
# swap_step LABEL FILE MARKER TPL_START TPL_END OLD_START OLD_END
swap_step() {
  local label="$1" f="$2" marker="$3" ts="$4" te="$5" os="$6" oe="$7"
  handled "$marker" "$f" "$label" && return 0
  if span_present "$f" "$os" "$oe"; then
    extract_block "$TPL/$(_tpl_of "$f")" "$ts" "$te"
    swap_block "$f" "$os" "$oe"
    log "applied $label ($f)"
  else
    record_skip "$label" "$f" "the '$os' … '$oe' span"
  fi
}
# insert_step LABEL FILE MARKER TPL_START TPL_END ANCHOR [before|after]
insert_step() {
  local label="$1" f="$2" marker="$3" ts="$4" te="$5" anchor="$6" where="${7:-before}"
  handled "$marker" "$f" "$label" && return 0
  if grep -qF -- "$anchor" "$f" 2>/dev/null; then
    extract_block "$TPL/$(_tpl_of "$f")" "$ts" "$te"
    if [ "$where" = after ]; then insert_after "$f" "$anchor"; else insert_before "$f" "$anchor"; fi
    log "applied $label ($f)"
  else
    record_skip "$label" "$f" "the '$anchor' anchor"
  fi
}

# 2a. coder — order matters: the floor swap keeps its first line, which the
# corner block is then inserted before, so a fresh template and a migrated
# file read rung 5 → Mark a real corner → floor.
if [ -f "$CODER" ]; then
  insert_step coder-rung4-lookup "$CODER" "$CODER_RUNG4" "$CODER_RUNG4_START" "$CODER_RUNG4" "$CODER_RUNG4_ANCHOR" after
  swap_step   coder-floor-calibration "$CODER" "$CODER_FLOOR" \
    "$CODER_FLOOR_START" "$CODER_FLOOR" "$CODER_FLOOR_START" "$CODER_FLOOR_OLD_END"
  insert_step coder-ceiling-marker "$CODER" "$CODER_CORNER" "$CODER_CORNER" "$CODER_CORNER_END" "$CODER_FLOOR_START" before
  swap_step   coder-fix-placement "$CODER" "$CODER_IMPACT" \
    "$CODER_IMPACT_START" "$CODER_IMPACT_END" "$CODER_IMPACT_START" "$CODER_IMPACT_OLD_END"
fi

# 2b. reviewer
if [ -f "$REV" ]; then
  insert_step reviewer-shrink-tag   "$REV" "$REV_SHRINK" "$REV_SHRINK" "$REV_SHRINK_END" "$REV_SHRINK_ANCHOR" after
  insert_step reviewer-ceiling-rows "$REV" "$REV_CEIL"   "$REV_CEIL"   "$REV_CEIL_END"   "$REV_CEIL_ANCHOR" before
fi

# 2c. coding-standards (LLM-written at init; the Comments bullets are fixed text)
if [ -f "$STD" ]; then
  insert_step standards-ceiling-comment "$STD" "$STD_MARK" "$STD_MARK" "$STD_END" "$STD_ANCHOR" after
fi

# --- 3. .gitignore: migration backups (already there from #35 on most installs)
if ! grep -qxF '*.pre-v0.*.bak' .gitignore 2>/dev/null; then
  if [ -s .gitignore ] && [ -n "$(tail -c1 .gitignore)" ]; then printf '\n' >> .gitignore; fi
  printf '# espalier migration backups (one per file per migration)\n*.pre-v0.*.bak\n' >> .gitignore
  log "added '*.pre-v0.*.bak' to .gitignore"
fi

# --- Verify ------------------------------------------------------------------
cmp -s "$REF_TPL" "$REF"                                          || die "post-migration verification failed: $REF differs from the template"
grep -qF -- "$STATS_MARK" espalier/hooks/espalier-stats.sh           || die "post-migration verification failed: espalier-stats.sh lacks '$STATS_MARK'"
grep -qF -- "$GRILL_MARK" espalier/skills/espalier-grill/SKILL.md    || die "post-migration verification failed: espalier-grill SKILL lacks '$GRILL_MARK'"
grep -qF -- "$SIMP_MARK"  espalier/skills/espalier-simplify/SKILL.md || die "post-migration verification failed: espalier-simplify SKILL lacks '$SIMP_MARK'"
[ -f "$CODER" ] && { handled "$CODER_CORNER" "$CODER" coder-ceiling-marker || die "post-migration verification failed: coder lacks the ceiling: marker rule"; }
[ -f "$REV" ]   && { handled "$REV_CEIL" "$REV" reviewer-ceiling-rows || die "post-migration verification failed: reviewer lacks the Ceiling markers rows"; }
if grep -q 'v0.28.0-' "$SKIPFILE" 2>/dev/null; then
  log "done with skips — see $SKIPFILE (each is a manual port from the template; the file works as before until then)."
fi

log "done. v0.28.0 applied — backups at <file>.pre-v0.28.bak (gitignored)."
log "Every gate and cap is unchanged. New: a deliberate shortcut with a known ceiling carries"
log "one line at the site — 'ceiling: <limit>; <trigger>' (the coder's ladder, rung 5); the"
log "reviewer files [ceiling] / [no-trigger] at P3 and a shrink: row only where the shorter form"
log "reads as clearly; the ladder's rung 4 opens references/platform-native.md when conventions"
log "are silent; a fix lands where every caller routes through; the grill counts an over-specified"
log "mechanism as a signal; /espalier-simplify reads every marker as a lead. Run"
log "'bash espalier/hooks/espalier-stats.sh' for the ceilings ledger."
exit 0
