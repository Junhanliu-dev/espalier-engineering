#!/bin/bash
# Migrate a v0.22.0 Espalier install to v0.22.1.
#
# v0.22.1 is the comment-diet polish patch (field feedback: agents still
# write too MANY comment lines, not just long ones). Three per-project files
# strengthen the brevity default to default-zero — a comment exists only for
# a constraint the code cannot show; a documented project convention that
# mandates fuller docs still outranks the default:
#
#   - harness-coder.md: the "Comments:" constraint becomes default-NO-comment
#     with a delete-before-reporting re-scan (no banners, no signature
#     doc-blocks, no narration).
#   - coding-standards.md: a "Default to NO comment" bullet under
#     ## Comments & Docstrings.
#   - harness-reviewer.md: the Readability `comments:` tag now also flags
#     EXCESS comments (banners / signature doc-blocks / obvious notes),
#     naming the exact lines to delete.
#
# All three are per-project files a plugin update cannot reach. Anchored
# edits only; a customised file missing its anchor is skipped with a record
# in espalier/.migrations-skipped, never mangled. Backups at
# <file>.pre-v0.22.1.bak (once per file). No pure-copy refresh, no config
# keys, no hook wiring.
#
# Usage:
#   bash migrate-v0.22.0-to-v0.22.1.sh [--dry-run] [--yes] [--plugin-dir=<path>]

set -u

DRY_RUN=no
SKIP_PROMPT=no
PLUGIN_DIR="${ESPALIER_PLUGIN_DIR:-}"

for arg in "$@"; do
  case "$arg" in
    --dry-run)       DRY_RUN=yes ;;
    --yes)           SKIP_PROMPT=yes ;;
    --plugin-dir=*)  PLUGIN_DIR="${arg#--plugin-dir=}" ;;
    -h|--help)       sed -n '2,26p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown flag: $arg (use --help)" >&2; exit 2 ;;
  esac
done

log() { echo "[migrate v0.22.0→v0.22.1] $*"; }
die() { echo "[migrate v0.22.0→v0.22.1] ERROR: $*" >&2; exit 1; }

[ -d espalier ] || die "no espalier/ dir — run from the target project root."

# --- Locate plugin templates (probe: this patch's own marker) ----------------
if [ -z "$PLUGIN_DIR" ]; then
  _self_root="$(cd "$(dirname "$0")/.." && pwd)"
  [ -d "$_self_root/skills/espalier-init/templates" ] && PLUGIN_DIR="$_self_root"
fi
[ -n "$PLUGIN_DIR" ] || die "cannot locate the plugin. Pass --plugin-dir=<espalier-engineering root>."
grep -q 'the default is NO comment' "$PLUGIN_DIR/skills/espalier-init/templates/agents/harness-coder.md" 2>/dev/null \
  || die "plugin dir $PLUGIN_DIR is not v0.22.1 (coder template lacks the comment-diet default). Update the plugin first."

# --- v0.22.1 markers (also the idempotency check) ----------------------------
CODER_MARK='the default is NO comment'
STD_MARK='Default to NO comment'
REV_MARK='EXCESS comments'
SKIPFILE="espalier/.migrations-skipped"

handled() {  # $1 = marker, $2 = file, $3 = skip label
  grep -qF "$1" "$2" 2>/dev/null || grep -qF "v0.22.1-$3" "$SKIPFILE" 2>/dev/null
}

missing=""
mark() { missing="$missing
  - $1"; }
handled "$CODER_MARK" espalier/agents/harness-coder.md      coder-comment-diet     || mark "coder default-zero comments"
handled "$STD_MARK"   espalier/rules/coding-standards.md    standards-comment-diet || mark "coding-standards default-zero bullet"
handled "$REV_MARK"   espalier/agents/harness-reviewer.md   reviewer-excess-tag    || mark "reviewer excess-comments tag"

if [ -z "$missing" ]; then
  log "already at v0.22.1 (every marker present). Nothing to do."
  exit 0
fi

if [ "$DRY_RUN" = yes ]; then
  log "DRY RUN — missing markers:$missing"
  log "DRY RUN — would anchored-edit the 3 per-project files (skip-with-record if customised; backups .pre-v0.22.1.bak)"
  exit 0
fi

if [ "$SKIP_PROMPT" != yes ]; then
  echo "This migration strengthens the comment-brevity default to default-zero in 3"
  echo "per-project files (backups: <file>.pre-v0.22.1.bak; customised files skipped)."
  printf "Proceed? [y/N] "
  read -r ans
  case "$ans" in y|Y|yes|YES) ;; *) log "aborted."; exit 0 ;; esac
fi

BLK=$(mktemp -t v0221blk.XXXX)
trap 'rm -f "$BLK"' EXIT

record_skip() {  # $1 = label, $2 = file, $3 = anchor description
  log "WARN: $2 is customised past the stock shape ($3 not found) — skipped."
  log "      Manual step: port the v0.22.1 comment-diet text from the template yourself."
  grep -qF "v0.22.1-$1" "$SKIPFILE" 2>/dev/null \
    || echo "v0.22.1-$1: customised, manual port needed ($2)" >> "$SKIPFILE"
}

backup_once() { [ -f "$1.pre-v0.22.1.bak" ] || cp "$1" "$1.pre-v0.22.1.bak"; }

# 1. coder — REPLACE the v0.21.1 bullet span (identical text in fresh-template
#    and #29-migrated installs) with the default-zero version.
if ! handled "$CODER_MARK" espalier/agents/harness-coder.md coder-comment-diet; then
  SPAN_START='- Comments: SHORT, clear, and few.'
  SPAN_END='outranks this brevity default.'
  if grep -qF -- "$SPAN_START" espalier/agents/harness-coder.md \
     && grep -qF -- "$SPAN_END" espalier/agents/harness-coder.md; then
    cat > "$BLK" << 'EOF'
- Comments: the default is NO comment — working code needs none. Add one
  ONLY for a constraint the code cannot show (a why, an invariant, a
  non-obvious edge), and then ONE plain line. Never a paragraph, never
  narration of what the next line does, never commentary addressed to the
  reviewer ("fixed per review"), never a section banner ("// helpers"),
  never a doc-block that restates a signature. Before writing your
  coding-report, RE-SCAN the diff and DELETE every comment that fails
  that test — a diff whose comment lines rival its code lines is
  over-commented. Multi-sentence explanations belong in the change's docs
  (requirements.md / coding-report.md), not the code. Density and
  docstring shape follow `coding-standards.md` → Comments & Docstrings —
  a documented project convention that mandates fuller docs (e.g. JSDoc
  on exports) outranks this default; match the project, don't fight it.
EOF
    backup_once espalier/agents/harness-coder.md
    tmp="espalier/agents/harness-coder.md.v0221tmp"
    cp espalier/agents/harness-coder.md "$tmp"
    awk -v blk="$BLK" -v start="$SPAN_START" -v end="$SPAN_END" '
      !insp && index($0, start) {
        while ((getline line < blk) > 0) print line
        close(blk); insp=1; skipping=1; next
      }
      skipping && index($0, end) { skipping=0; next }
      skipping { next }
      { print }
    ' "$tmp" > espalier/agents/harness-coder.md
    rm -f "$tmp"
    log "replaced coder comments constraint with the default-zero version"
  else
    record_skip coder-comment-diet espalier/agents/harness-coder.md "the v0.21.1 Comments bullet span"
  fi
fi

# 2. coding-standards — insert the default-zero bullet AFTER the v0.21.1
#    brevity bullet's closing line (identical in both install shapes).
if ! handled "$STD_MARK" espalier/rules/coding-standards.md standards-comment-diet; then
  ANCHOR='fuller docstrings outranks this default.)'
  if grep -qF -- "$ANCHOR" espalier/rules/coding-standards.md; then
    cat > "$BLK" << 'EOF'
- Default to NO comment: add one only for a constraint the code cannot
  show. No section banners, no doc-blocks restating a signature, no
  narration, no restating the code in prose — delete any comment that
  merely repeats what the line already says.
EOF
    backup_once espalier/rules/coding-standards.md
    tmp="espalier/rules/coding-standards.md.v0221tmp"
    cp espalier/rules/coding-standards.md "$tmp"
    awk -v blk="$BLK" -v anchor="$ANCHOR" '
      { print }
      !done && index($0, anchor) {
        while ((getline line < blk) > 0) print line
        close(blk); done=1
      }
    ' "$tmp" > espalier/rules/coding-standards.md
    rm -f "$tmp"
    log "inserted coding-standards default-zero bullet"
  else
    record_skip standards-comment-diet espalier/rules/coding-standards.md "the v0.21.1 brevity bullet"
  fi
fi

# 3. reviewer — splice the EXCESS case into the `comments:` tag. The target
#    line WRAPS DIFFERENTLY in fresh-template vs #29-migrated installs, so
#    this is a SUBSTRING splice (index+substr, no regex), preserving any tail.
if ! handled "$REV_MARK" espalier/agents/harness-reviewer.md reviewer-excess-tag; then
  ANCH='one-line replacement), or a missing'
  if grep -qF -- "$ANCH" espalier/agents/harness-reviewer.md; then
    backup_once espalier/agents/harness-reviewer.md
    tmp="espalier/agents/harness-reviewer.md.v0221tmp"
    cp espalier/agents/harness-reviewer.md "$tmp"
    awk -v anch="$ANCH" '
      !done {
        i = index($0, anch)
        if (i) {
          pre = substr($0, 1, i - 1)
          tail = substr($0, i + length(anch))
          print pre "one-line replacement), EXCESS comments (more comment than the code"
          print "  warrants — section banners, doc-blocks restating a signature,"
          print "  obvious-statement notes; name the exact lines to delete), or a missing" tail
          done = 1; next
        }
      }
      { print }
    ' "$tmp" > espalier/agents/harness-reviewer.md
    rm -f "$tmp"
    log "spliced reviewer EXCESS-comments case into the comments: tag"
  else
    record_skip reviewer-excess-tag espalier/agents/harness-reviewer.md "the stock comments: tag line"
  fi
fi

# --- Verify ------------------------------------------------------------------
handled "$CODER_MARK" espalier/agents/harness-coder.md    coder-comment-diet     || die "post-migration verification failed: coder lacks '$CODER_MARK'"
handled "$STD_MARK"   espalier/rules/coding-standards.md  standards-comment-diet || die "post-migration verification failed: coding-standards lacks '$STD_MARK'"
handled "$REV_MARK"   espalier/agents/harness-reviewer.md reviewer-excess-tag    || die "post-migration verification failed: reviewer lacks '$REV_MARK'"

log "done. v0.22.1 applied — backups at <file>.pre-v0.22.1.bak."
log "Comments now default to zero — one plain line only for what the code"
log "cannot show; discovered project conventions still outrank the default."
exit 0
