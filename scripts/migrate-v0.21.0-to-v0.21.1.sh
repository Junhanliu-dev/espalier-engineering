#!/bin/bash
# Migrate a v0.21.0 Espalier install to v0.21.1.
#
# v0.21.1 is the comment-brevity polish patch (field feedback: generated
# comments run too long). Three per-project files gain a short-comments
# default — SHORT, clear, one plain line for the non-obvious constraint;
# a documented project convention requiring fuller docs still outranks it:
#
#   - harness-coder.md: a "Comments:" bullet in ## Your Constraints.
#   - coding-standards.md: a "Keep comments SHORT" bullet under
#     ## Comments & Docstrings.
#   - harness-reviewer.md: the Readability Review `comments:` tag now also
#     flags an OVERLONG comment (paragraph where one line carries it).
#
# All three are per-project files a plugin update cannot reach. Anchored
# edits only; a customised file missing its anchor is skipped with a
# record in espalier/.migrations-skipped, never mangled. Backups at
# <file>.pre-v0.21.1.bak (once per file). No pure-copy refresh, no config
# keys, no hook wiring, no new symlinks.
#
# Usage:
#   bash migrate-v0.21.0-to-v0.21.1.sh [--dry-run] [--yes] [--plugin-dir=<path>]

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

log() { echo "[migrate v0.21.0→v0.21.1] $*"; }
die() { echo "[migrate v0.21.0→v0.21.1] ERROR: $*" >&2; exit 1; }

[ -d espalier ] || die "no espalier/ dir — run from the target project root."

# --- Locate plugin templates (probe: this patch's own marker) ----------------
if [ -z "$PLUGIN_DIR" ]; then
  _self_root="$(cd "$(dirname "$0")/.." && pwd)"
  [ -d "$_self_root/skills/espalier-init/templates" ] && PLUGIN_DIR="$_self_root"
fi
[ -n "$PLUGIN_DIR" ] || die "cannot locate the plugin. Pass --plugin-dir=<espalier-engineering root>."
grep -q 'Comments: SHORT' "$PLUGIN_DIR/skills/espalier-init/templates/agents/harness-coder.md" 2>/dev/null \
  || die "plugin dir $PLUGIN_DIR is not v0.21.1 (coder template lacks the comment-brevity bullet). Update the plugin first."

# --- v0.21.1 markers (also the idempotency check) ----------------------------
CODER_MARK='Comments: SHORT'
REV_MARK='OVERLONG comment'
STD_MARK='Keep comments SHORT'
SKIPFILE="espalier/.migrations-skipped"

handled() {  # $1 = marker, $2 = file, $3 = skip label
  grep -qF "$1" "$2" 2>/dev/null || grep -qF "v0.21.1-$3" "$SKIPFILE" 2>/dev/null
}

missing=""
mark() { missing="$missing
  - $1"; }
handled "$CODER_MARK" espalier/agents/harness-coder.md      coder-comment-brevity     || mark "coder comment-brevity bullet"
handled "$REV_MARK"   espalier/agents/harness-reviewer.md   reviewer-comment-brevity  || mark "reviewer overlong-comment tag"
handled "$STD_MARK"   espalier/rules/coding-standards.md    standards-comment-brevity || mark "coding-standards brevity bullet"

if [ -z "$missing" ]; then
  log "already at v0.21.1 (every marker present). Nothing to do."
  exit 0
fi

if [ "$DRY_RUN" = yes ]; then
  log "DRY RUN — missing markers:$missing"
  log "DRY RUN — would anchored-edit the 3 per-project files (skip-with-record if customised; backups .pre-v0.21.1.bak)"
  exit 0
fi

if [ "$SKIP_PROMPT" != yes ]; then
  echo "This migration adds the short-comments default to 3 per-project files"
  echo "(backups: <file>.pre-v0.21.1.bak; customised files are skipped, never mangled)."
  printf "Proceed? [y/N] "
  read -r ans
  case "$ans" in y|Y|yes|YES) ;; *) log "aborted."; exit 0 ;; esac
fi

BLK=$(mktemp -t v0211blk.XXXX)
trap 'rm -f "$BLK"' EXIT

record_skip() {  # $1 = label, $2 = file, $3 = anchor description
  log "WARN: $2 is customised past the stock shape ($3 not found) — skipped."
  log "      Manual step: add the v0.21.1 comment-brevity text from the template yourself."
  grep -qF "v0.21.1-$1" "$SKIPFILE" 2>/dev/null \
    || echo "v0.21.1-$1: customised, manual port needed ($2)" >> "$SKIPFILE"
}

backup_once() { [ -f "$1.pre-v0.21.1.bak" ] || cp "$1" "$1.pre-v0.21.1.bak"; }

awk_edit() {  # $1 = file, runs awk program $2 with blk file bound; writes in place via tmp
  f="$1"; prog="$2"
  tmp="$f.v0211tmp"
  cp "$f" "$tmp"
  awk -v blk="$BLK" "$prog" "$tmp" > "$f"
  rm -f "$tmp"
}

# 1. coder — insert the Comments bullet BEFORE the "Report what you did" bullet
if ! grep -qF "$CODER_MARK" espalier/agents/harness-coder.md; then
  ANCHOR='- Report what you did in structured format when done'
  if grep -qF -- "$ANCHOR" espalier/agents/harness-coder.md; then
    cat > "$BLK" << 'EOF'
- Comments: SHORT, clear, and few. One plain line stating the non-obvious
  constraint or the why — never a paragraph, never narration of what the next
  line does, never commentary addressed to the reviewer ("fixed per review").
  If a comment needs several sentences, the explanation belongs in the
  change's docs (requirements.md / coding-report.md), not the code. Density
  and docstring shape follow `coding-standards.md` → Comments & Docstrings —
  a project convention that mandates fuller docs (e.g. JSDoc on exports)
  outranks this brevity default.
EOF
    backup_once espalier/agents/harness-coder.md
    awk_edit espalier/agents/harness-coder.md '
      !done && index($0, "- Report what you did in structured format when done") {
        while ((getline line < blk) > 0) print line
        close(blk); done=1
      }
      { print }'
    log "inserted coder comment-brevity bullet"
  else
    record_skip coder-comment-brevity espalier/agents/harness-coder.md "the Your Constraints report bullet"
  fi
fi

# 2. coding-standards — insert the brevity bullet AFTER the density bullet's
#    closing line ("show; never narrate what the next line does.")
if ! grep -qF "$STD_MARK" espalier/rules/coding-standards.md; then
  if grep -qF 'show; never narrate what the next line does.' espalier/rules/coding-standards.md; then
    cat > "$BLK" << 'EOF'
- Keep comments SHORT: one plain, easy-to-read line beats a paragraph. A
  comment that needs several sentences is explanation that belongs in the
  change's docs, not the code. (A documented project convention requiring
  fuller docstrings outranks this default.)
EOF
    backup_once espalier/rules/coding-standards.md
    awk_edit espalier/rules/coding-standards.md '
      { print }
      !done && index($0, "show; never narrate what the next line does.") {
        while ((getline line < blk) > 0) print line
        close(blk); done=1
      }'
    log "inserted coding-standards brevity bullet"
  else
    record_skip standards-comment-brevity espalier/rules/coding-standards.md "the Comments & Docstrings density line"
  fi
fi

# 3. reviewer — extend the `comments:` tag to flag overlong comments (replace
#    the stock one-line span; wrapping differs from the template, markers match)
if ! grep -qF "$REV_MARK" espalier/agents/harness-reviewer.md; then
  if grep -qF 'narrating noise where the project comments sparsely, or a missing' espalier/agents/harness-reviewer.md; then
    cat > "$BLK" << 'EOF'
  narrating noise where the project comments sparsely, an OVERLONG comment
  (a paragraph where one plain line would carry the constraint — name the
  one-line replacement), or a missing
EOF
    backup_once espalier/agents/harness-reviewer.md
    awk_edit espalier/agents/harness-reviewer.md '
      !done && index($0, "narrating noise where the project comments sparsely, or a missing") {
        while ((getline line < blk) > 0) print line
        close(blk); done=1; next
      }
      { print }'
    log "extended reviewer comments: tag with the overlong-comment case"
  else
    record_skip reviewer-comment-brevity espalier/agents/harness-reviewer.md "the stock comments: tag line"
  fi
fi

# --- Verify ------------------------------------------------------------------
handled "$CODER_MARK" espalier/agents/harness-coder.md    coder-comment-brevity     || die "post-migration verification failed: coder lacks '$CODER_MARK'"
handled "$REV_MARK"   espalier/agents/harness-reviewer.md reviewer-comment-brevity  || die "post-migration verification failed: reviewer lacks '$REV_MARK'"
handled "$STD_MARK"   espalier/rules/coding-standards.md  standards-comment-brevity || die "post-migration verification failed: coding-standards lacks '$STD_MARK'"

log "done. v0.21.1 applied — backups at <file>.pre-v0.21.1.bak."
log "Generated comments now default to short + clear; discovered project"
log "conventions (fuller docstrings etc.) still outrank the default."
exit 0
