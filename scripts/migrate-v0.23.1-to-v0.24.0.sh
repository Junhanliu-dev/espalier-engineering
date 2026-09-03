#!/bin/bash
# Migrate a v0.23.1 Espalier install to v0.24.0.
#
# v0.24.0 is the simplify-lane release: /espalier-simplify — an evidence-first
# simplification survey of the EXISTING code (method adapted from
# tt-a1i/simplify-codebase, MIT). Read-only scouts hunt accidental complexity
# per discovered layer; every candidate carries a proof record (consumer map,
# cut boundary, consequence, decisive check, net effect); the ranked
# inventory lands in espalier/wiki/simplify-survey.md; proven cuts are filed
# as `Status: FILED` refactor/ skeletons that /espalier adopts and runs
# through its normal coder + two-agent panel; the docs that described the
# retired surface are flagged for /espalier-prune at Completion.
#
#   - New file: espalier/skills/espalier-simplify/SKILL.md (+ a symlink on
#     every platform in espalier/.platforms).
#   - Pure-copy refresh (backup-on-diff → <file>.pre-v0.24.bak):
#     espalier/pipeline.md (lanes note), the espalier SKILL (FILED-skeleton
#     scan covers refactor/; Completion flags docs naming retired surface),
#     the espalier-map SKILL (retirement maps carry simplify_from), the
#     espalier-ask SKILL (survey page as a `why` source), and
#     espalier/hooks/espalier-stats.sh (simplify-lane echo section).
#   - Anchored edits, text EXTRACTED from the plugin templates at run time so
#     a migrated install is byte-identical to a fresh one in those sections:
#     harness-coder.md gains "## Simplification Changes: Retire the Whole
#     Obligation" (before Editing Discipline); harness-reviewer.md gains
#     "## Simplification Review" (before Minimalism Review); espalier/agent.md
#     gains the Simplify config-index row (after the Audit row). A customised
#     file missing its anchor is skipped with a record in
#     espalier/.migrations-skipped, never mangled. Backups at
#     <file>.pre-v0.24.bak (once per file).
#   - Instruction files: one grep-guarded /espalier-simplify line inside the
#     existing `## Espalier` section of CLAUDE.md / AGENTS.md /
#     .github/copilot-instructions.md — after the audit line, or appended to
#     the file when that line was customised away.
#   No config keys, no hooks, no .gitignore entries.
#
# Usage:
#   bash migrate-v0.23.1-to-v0.24.0.sh [--dry-run] [--yes] [--plugin-dir=<path>]

set -u

DRY_RUN=no
SKIP_PROMPT=no
PLUGIN_DIR="${ESPALIER_PLUGIN_DIR:-}"

for arg in "$@"; do
  case "$arg" in
    --dry-run)       DRY_RUN=yes ;;
    --yes)           SKIP_PROMPT=yes ;;
    --plugin-dir=*)  PLUGIN_DIR="${arg#--plugin-dir=}" ;;
    -h|--help)       sed -n '2,35p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown flag: $arg (use --help)" >&2; exit 2 ;;
  esac
done

log() { echo "[migrate v0.23.1→v0.24.0] $*"; }
die() { echo "[migrate v0.23.1→v0.24.0] ERROR: $*" >&2; exit 1; }

[ -d espalier ] || die "no espalier/ dir — run from the target project root."

# --- Locate plugin templates (probe: this release's own skill template) ------
if [ -z "$PLUGIN_DIR" ]; then
  _self_root="$(cd "$(dirname "$0")/.." && pwd)"
  [ -d "$_self_root/skills/espalier-init/templates" ] && PLUGIN_DIR="$_self_root"
fi
[ -n "$PLUGIN_DIR" ] || die "cannot locate the plugin. Pass --plugin-dir=<espalier-engineering root>."
TPL="$PLUGIN_DIR/skills/espalier-init/templates"

# --- v0.24.0 markers (also the idempotency check) ----------------------------
CODER_MARK='## Simplification Changes: Retire the Whole Obligation'
CODER_END='and the cut returns to the survey page.'
REV_MARK='## Simplification Review'
REV_END='rules or specs is ever residue.'
ROW_MARK='Via /espalier-simplify |'
LANE_MARK='/espalier-simplify'
ADOPT_MARK='simplify_from'
MAP_MARK='simplify_from'
ASK_MARK='simplify-survey'
STATS_MARK='simplify-lane echo'
HTPL="$PLUGIN_DIR/skills/espalier-init/hook-templates"
SKIPFILE="espalier/.migrations-skipped"

[ -f "$TPL/skills/espalier-simplify.md" ] \
  && grep -qF "$CODER_MARK" "$TPL/agents/harness-coder.md" 2>/dev/null \
  && grep -qF "$REV_MARK" "$TPL/agents/harness-reviewer.md" 2>/dev/null \
  && grep -qF "$ROW_MARK" "$TPL/agent.md" 2>/dev/null \
  && grep -qF "$ADOPT_MARK" "$TPL/skills/espalier.md" 2>/dev/null \
  && grep -qF "$MAP_MARK" "$TPL/skills/espalier-map.md" 2>/dev/null \
  && grep -qF "$ASK_MARK" "$TPL/skills/espalier-ask.md" 2>/dev/null \
  && grep -qF "$STATS_MARK" "$HTPL/espalier-stats.sh" 2>/dev/null \
  || die "plugin dir $PLUGIN_DIR is not v0.24.0 (templates lack the simplify lane). Update the plugin first."

PLATFORMS=$(head -1 espalier/.platforms 2>/dev/null | tr -d '[:space:]')
[ -n "$PLATFORMS" ] || PLATFORMS=claude
want_claude()  { case "$PLATFORMS" in *claude*)  return 0 ;; *) return 1 ;; esac; }
want_codex()   { case "$PLATFORMS" in *codex*)   return 0 ;; *) return 1 ;; esac; }
want_copilot() { case "$PLATFORMS" in *copilot*) return 0 ;; *) return 1 ;; esac; }

handled() {  # $1 = marker, $2 = file, $3 = skip label
  grep -qF "$1" "$2" 2>/dev/null || grep -qF "v0.24.0-$3" "$SKIPFILE" 2>/dev/null
}
# lane_line_present FILE — true when the file has no Espalier section (not
# applicable here) or already carries the lane line.
lane_line_present() {
  [ -f "$1" ] || return 0
  grep -q "## Espalier" "$1" 2>/dev/null || return 0
  grep -qF "espalier-simplify" "$1" 2>/dev/null
}

missing=""
mark() { missing="$missing
  - $1"; }
grep -q '^name: espalier-simplify' espalier/skills/espalier-simplify/SKILL.md 2>/dev/null \
  || mark "espalier-simplify lane skill"
if want_claude;  then [ -L .claude/skills/espalier-simplify ] || mark ".claude/skills/espalier-simplify link"; fi
if want_codex;   then [ -L .agents/skills/espalier-simplify ] || mark ".agents/skills/espalier-simplify link"; fi
if want_copilot; then [ -L .github/skills/espalier-simplify ] || mark ".github/skills/espalier-simplify link"; fi
grep -qF "$LANE_MARK"  espalier/pipeline.md              2>/dev/null || mark "pipeline.md lanes note"
grep -qF "$ADOPT_MARK" espalier/skills/espalier/SKILL.md 2>/dev/null || mark "espalier SKILL refactor/ adoption + Completion doc flags"
grep -qF "$MAP_MARK"   espalier/skills/espalier-map/SKILL.md 2>/dev/null || mark "espalier-map SKILL retirement maps"
grep -qF "$ASK_MARK"   espalier/skills/espalier-ask/SKILL.md 2>/dev/null || mark "espalier-ask SKILL survey why-source"
grep -qF "$STATS_MARK" espalier/hooks/espalier-stats.sh      2>/dev/null || mark "espalier-stats simplify-lane echo"
handled "$CODER_MARK" espalier/agents/harness-coder.md    coder-simplify    || mark "coder Simplification Changes section"
handled "$REV_MARK"   espalier/agents/harness-reviewer.md reviewer-simplify || mark "reviewer Simplification Review section"
if [ -f espalier/agent.md ]; then
  handled "$ROW_MARK" espalier/agent.md agent-index-row || mark "agent.md Simplify config-index row"
fi
if want_claude;  then lane_line_present CLAUDE.md                       || mark "CLAUDE.md lane line"; fi
if want_codex;   then lane_line_present AGENTS.md                       || mark "AGENTS.md lane line"; fi
if want_copilot; then lane_line_present .github/copilot-instructions.md || mark "copilot-instructions.md lane line"; fi

if [ -z "$missing" ]; then
  log "already at v0.24.0 (every marker present). Nothing to do."
  exit 0
fi

if [ "$DRY_RUN" = yes ]; then
  log "DRY RUN — missing markers:$missing"
  log "DRY RUN — would install espalier/skills/espalier-simplify/SKILL.md + symlinks for platforms: $PLATFORMS"
  log "DRY RUN — would refresh 5 pure-copy files (pipeline.md, espalier / espalier-map / espalier-ask SKILLs, espalier-stats.sh; backup-on-diff → .pre-v0.24.bak)"
  log "DRY RUN — would anchored-edit harness-coder.md, harness-reviewer.md, agent.md from the templates (skip-with-record if customised)"
  log "DRY RUN — would add the /espalier-simplify line to each wired instruction file"
  exit 0
fi

if [ "$SKIP_PROMPT" != yes ]; then
  echo "This migration will:"
  echo "  - install the espalier-simplify skill and link it for: $PLATFORMS"
  echo "  - refresh pipeline.md, the espalier / espalier-map / espalier-ask SKILLs, and espalier-stats.sh from templates (backups: <file>.pre-v0.24.bak)"
  echo "  - insert the simplification sections into harness-coder.md / harness-reviewer.md and the agent.md row (customised files skipped, never mangled)"
  echo "  - add one /espalier-simplify line to CLAUDE.md / AGENTS.md / copilot-instructions.md where wired"
  printf "Proceed? [y/N] "
  read -r ans
  case "$ans" in y|Y|yes|YES) ;; *) log "aborted."; exit 0 ;; esac
fi

backup_once() { [ -f "$1.pre-v0.24.bak" ] || cp "$1" "$1.pre-v0.24.bak"; }

# --- 1. Skill + symlinks -----------------------------------------------------
mkdir -p espalier/skills/espalier-simplify
if [ -f espalier/skills/espalier-simplify/SKILL.md ] \
   && ! cmp -s "$TPL/skills/espalier-simplify.md" espalier/skills/espalier-simplify/SKILL.md; then
  backup_once espalier/skills/espalier-simplify/SKILL.md
fi
cp "$TPL/skills/espalier-simplify.md" espalier/skills/espalier-simplify/SKILL.md
log "installed espalier/skills/espalier-simplify/SKILL.md"

_safe_ln() {  # same relative-target convention as bootstrap
  local src="$1" dst="$2"
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    log "  WARN: $dst exists as a regular file — skipping symlink (move it aside, then re-run)"
    return 0
  fi
  ln -sfn "$src" "$dst"
}
if want_claude; then
  mkdir -p .claude/skills
  _safe_ln ../../espalier/skills/espalier-simplify .claude/skills/espalier-simplify
  log "linked .claude/skills/espalier-simplify"
fi
if want_codex; then
  mkdir -p .agents/skills
  _safe_ln ../../espalier/skills/espalier-simplify .agents/skills/espalier-simplify
  log "linked .agents/skills/espalier-simplify"
fi
if want_copilot; then
  mkdir -p .github/skills
  _safe_ln ../../espalier/skills/espalier-simplify .github/skills/espalier-simplify
  log "linked .github/skills/espalier-simplify"
fi

# --- 2. Pure-copy refresh (backup-on-diff) -----------------------------------
refresh() {  # $1 = template path, $2 = installed path
  [ -f "$1" ] || die "template missing: $1"
  if [ -f "$2" ] && ! cmp -s "$1" "$2"; then
    cp "$2" "$2.pre-v0.24.bak"
  fi
  cp "$1" "$2"
  log "refreshed $2"
}
grep -qF "$LANE_MARK" espalier/pipeline.md 2>/dev/null \
  || refresh "$TPL/pipeline.md"        espalier/pipeline.md
grep -qF "$ADOPT_MARK" espalier/skills/espalier/SKILL.md 2>/dev/null \
  || refresh "$TPL/skills/espalier.md" espalier/skills/espalier/SKILL.md
grep -qF "$MAP_MARK" espalier/skills/espalier-map/SKILL.md 2>/dev/null \
  || refresh "$TPL/skills/espalier-map.md" espalier/skills/espalier-map/SKILL.md
grep -qF "$ASK_MARK" espalier/skills/espalier-ask/SKILL.md 2>/dev/null \
  || refresh "$TPL/skills/espalier-ask.md" espalier/skills/espalier-ask/SKILL.md
if ! grep -qF "$STATS_MARK" espalier/hooks/espalier-stats.sh 2>/dev/null; then
  refresh "$HTPL/espalier-stats.sh" espalier/hooks/espalier-stats.sh
  chmod +x espalier/hooks/espalier-stats.sh 2>/dev/null || true
fi

# --- 3. Anchored edits (text extracted from the templates) -------------------
BLK=$(mktemp -t v0240blk.XXXX)
trap 'rm -f "$BLK"' EXIT
NOBAK=no

record_skip() {  # $1 = label, $2 = file, $3 = anchor description
  log "WARN: $2 is customised past the stock shape ($3 not found) — skipped."
  log "      Manual step: port the v0.24.0 '$1' text from the template yourself."
  grep -qF "v0.24.0-$1" "$SKIPFILE" 2>/dev/null \
    || echo "v0.24.0-$1: customised, manual port needed ($2)" >> "$SKIPFILE"
}

# extract_block TEMPLATE START END — lines from the first one containing START
# through the first later one containing END, inclusive, into $BLK. Dies on an
# empty result OR when END never matched (the block would otherwise run to
# EOF and swallow every later section — the v0.23.0 span-edit lesson): both
# mean the template drifted from this script's anchors.
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

# insert_before FILE ANCHOR — $BLK plus one blank line go right before the
# first line containing ANCHOR.
insert_before() {
  local f="$1" anchor="$2" tmp="$1.v0240tmp"
  [ "$NOBAK" = yes ] || backup_once "$f"
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

# insert_after FILE ANCHOR — $BLK goes right after the first line containing ANCHOR.
insert_after() {
  local f="$1" anchor="$2" tmp="$1.v0240tmp"
  [ "$NOBAK" = yes ] || backup_once "$f"
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

# 3a. coder — the section sits immediately before Editing Discipline.
CODER=espalier/agents/harness-coder.md
if ! handled "$CODER_MARK" "$CODER" coder-simplify; then
  ANCH='## Editing Discipline'
  if grep -qF -- "$ANCH" "$CODER" 2>/dev/null; then
    extract_block "$TPL/agents/harness-coder.md" "$CODER_MARK" "$CODER_END"
    insert_before "$CODER" "$ANCH"
    log "inserted coder Simplification Changes section"
  else
    record_skip coder-simplify "$CODER" "the '## Editing Discipline' heading"
  fi
fi

# 3b. reviewer — the section sits immediately before the Minimalism Review.
REV=espalier/agents/harness-reviewer.md
if ! handled "$REV_MARK" "$REV" reviewer-simplify; then
  ANCH='## Minimalism Review (advisory'
  if grep -qF -- "$ANCH" "$REV" 2>/dev/null; then
    extract_block "$TPL/agents/harness-reviewer.md" "$REV_MARK" "$REV_END"
    insert_before "$REV" "$ANCH"
    log "inserted reviewer Simplification Review section"
  else
    record_skip reviewer-simplify "$REV" "the '## Minimalism Review' heading"
  fi
fi

# 3c. agent.md — the Simplify row follows the Audit row of the Config Index.
AGENT=espalier/agent.md
if [ -f "$AGENT" ] && ! handled "$ROW_MARK" "$AGENT" agent-index-row; then
  ANCH='Via /espalier-audit |'
  if grep -qF -- "$ANCH" "$AGENT" 2>/dev/null; then
    grep -F "$ROW_MARK" "$TPL/agent.md" > "$BLK"
    [ -s "$BLK" ] || die "template row '$ROW_MARK' not found in $TPL/agent.md — plugin templates drifted."
    insert_after "$AGENT" "$ANCH"
    log "inserted agent.md Simplify config-index row"
  else
    record_skip agent-index-row "$AGENT" "the Audit row ('Via /espalier-audit |')"
  fi
fi

# --- 4. Instruction-file lane line (grep-guarded, only where the section exists)
add_lane_line() {  # FILE VERB PREFIX
  local f="$1" verb="$2" p="$3" line
  [ -f "$f" ] || return 0
  grep -q "## Espalier" "$f" 2>/dev/null || return 0
  grep -qF "espalier-simplify" "$f" 2>/dev/null && return 0
  line=$(printf '**For a simplification survey** of the existing code (dead surface, duplicate state, ownerless abstractions), %s `%sespalier-simplify [scope]` — read-only, evidence-ranked into `espalier/wiki/simplify-survey.md`; proven cuts are filed as refactor skeletons for `%sespalier`, never deleted in place.' "$verb" "$p" "$p")
  if grep -qF '**For a repo-wide security audit**' "$f"; then
    printf '\n%s\n' "$line" > "$BLK"
    NOBAK=yes; insert_after "$f" '**For a repo-wide security audit**'; NOBAK=no
    log "added /espalier-simplify line to $f (after the audit line)"
  else
    printf '\n%s\n' "$line" >> "$f"
    log "added /espalier-simplify line to $f (appended — audit line not found)"
  fi
}
if want_claude;  then add_lane_line CLAUDE.md                       use    "/";  fi
if want_codex;   then add_lane_line AGENTS.md                       invoke "\$"; fi
if want_copilot; then add_lane_line .github/copilot-instructions.md invoke "/";  fi

# --- Verify ------------------------------------------------------------------
grep -q '^name: espalier-simplify' espalier/skills/espalier-simplify/SKILL.md \
  || die "post-migration verification failed: espalier-simplify skill missing"
grep -qF "$LANE_MARK"  espalier/pipeline.md              || die "post-migration verification failed: pipeline.md lacks the lanes note"
grep -qF "$ADOPT_MARK" espalier/skills/espalier/SKILL.md || die "post-migration verification failed: espalier SKILL lacks '$ADOPT_MARK'"
grep -qF "$MAP_MARK"   espalier/skills/espalier-map/SKILL.md || die "post-migration verification failed: espalier-map SKILL lacks '$MAP_MARK'"
grep -qF "$ASK_MARK"   espalier/skills/espalier-ask/SKILL.md || die "post-migration verification failed: espalier-ask SKILL lacks '$ASK_MARK'"
grep -qF "$STATS_MARK" espalier/hooks/espalier-stats.sh      || die "post-migration verification failed: espalier-stats.sh lacks '$STATS_MARK'"
handled "$CODER_MARK" "$CODER" coder-simplify    || die "post-migration verification failed: coder lacks '$CODER_MARK'"
handled "$REV_MARK"   "$REV"   reviewer-simplify || die "post-migration verification failed: reviewer lacks '$REV_MARK'"
if want_claude; then
  [ -L .claude/skills/espalier-simplify ] && [ -e .claude/skills/espalier-simplify ] \
    || die "post-migration verification failed: .claude/skills/espalier-simplify link"
fi
if want_codex; then
  [ -L .agents/skills/espalier-simplify ] && [ -e .agents/skills/espalier-simplify ] \
    || die "post-migration verification failed: .agents/skills/espalier-simplify link"
fi
if want_copilot; then
  [ -L .github/skills/espalier-simplify ] && [ -e .github/skills/espalier-simplify ] \
    || die "post-migration verification failed: .github/skills/espalier-simplify link"
fi

log "done. v0.24.0 applied — backups at <file>.pre-v0.24.bak."
log "Survey the code with /espalier-simplify [scope]; proven cuts file as refactor"
log "skeletons for /espalier, and the docs they retire get flagged for /espalier-prune."
exit 0
