#!/bin/bash
# Migrate a v0.28.1 Espalier install to v0.29.0.
#
# v0.29.0 is the PR split. A pipeline run no longer ends in one branch: the
# code branch carries every path outside espalier/, a sibling branch carries
# all of espalier/**, and Stage 7 opens both pull requests. Between the two, a
# new doc sweep reads the change's own diff against espalier/wiki/ and
# espalier/rules/ and commits what the diff falsified onto the espalier PR.
#
# Contract-equal to v0.28.1 everywhere else: every gate, rubric, sentinel,
# round cap and escalation path is unchanged. NOTHING here sets a budget.
#
#   - New files (pure copy):
#       espalier/hooks/espalier-pr.sh        the forge surface (project/push/open/status)
#       espalier/agents/modes/wiki-sweep.md  the sweep procedure
#   - Pure-copy refresh (backup-on-diff → <file>.pre-v0.29.bak) — these ship
#     verbatim, so a migrated install ends byte-identical to a fresh one:
#       espalier/pipeline.md
#       espalier/skills/espalier/stages/7-10-delivery.md
#       espalier/skills/espalier-fix/SKILL.md
#       espalier/hooks/drift-helpers.sh      (delivery_brief gains the PR + sweep sections)
#   - Anchored edits, text EXTRACTED from the plugin templates at run time
#     (these files carry init-time project substitutions and are never copied):
#       espalier/agents/harness-coder.md     Commit Discipline — commits are code only
#       espalier/agents/harness-reviewer.md  the Doc Sweep pointer + its You-Must-NOT bullet
#       espalier/rules/development-process.md  MAINTENANCE COMMITS v1 → v2
#     A customised file missing its anchor is SKIPPED with a record in
#     espalier/.migrations-skipped, never mangled.
#   - In-flight changes are never retro-split: a change already at Stage >= 7
#     finishes on the old single-branch path and is reported, not touched.
#   No config key, no new instruction-file line, no hooks, no symlinks.
#
# Usage:
#   bash migrate-v0.28.1-to-v0.29.0.sh [--dry-run] [--yes] [--plugin-dir=<path>]

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

log() { echo "[migrate v0.28.1→v0.29.0] $*"; }
die() { echo "[migrate v0.28.1→v0.29.0] ERROR: $*" >&2; exit 1; }

[ -d espalier ] || die "no espalier/ dir — run from the target project root."

# --- Locate plugin templates (probe: this release's own new hook) ------------
if [ -z "$PLUGIN_DIR" ]; then
  _self_root="$(cd "$(dirname "$0")/.." && pwd)"
  [ -d "$_self_root/skills/espalier-init/templates" ] && PLUGIN_DIR="$_self_root"
fi
[ -n "$PLUGIN_DIR" ] || die "cannot locate the plugin. Pass --plugin-dir=<espalier-engineering root>."
TPL="$PLUGIN_DIR/skills/espalier-init/templates"
HTPL="$PLUGIN_DIR/skills/espalier-init/hook-templates"
SKIPFILE="espalier/.migrations-skipped"

# --- v0.29.0 markers (also the idempotency check) ---------------------------
PR_MARK='espalier-pr.sh — the code PR and its espalier sibling'
SWEEP_MARK='# Mode: wiki-sweep'
PIPE_MARK='**Pull requests:**'
STAGE_MARK='### Stage 7: The Split — Code Branch, Espalier Branch'
FIX_MARK='### 7.0 The split — code branch, espalier branch'
HELP_MARK='## Doc Refresh (Stage 7 sweep)'
CODER_MARK='Your commits are CODE ONLY: never stage a path under'
REV_MARK='## Doc Sweep (Stage 7 — your prompt says'
RULE_MARK='<!-- ESPALIER MAINTENANCE COMMITS v2'

[ -f "$HTPL/espalier-pr.sh" ] \
  && grep -qF -- "$SWEEP_MARK"  "$TPL/agents/modes/wiki-sweep.md" 2>/dev/null \
  && grep -qF -- "$PIPE_MARK"   "$TPL/pipeline.md" 2>/dev/null \
  && grep -qF -- "$STAGE_MARK"  "$TPL/skills/espalier-stages/7-10-delivery.md" 2>/dev/null \
  && grep -qF -- "$FIX_MARK"    "$TPL/skills/espalier-fix.md" 2>/dev/null \
  && grep -qF -- "$HELP_MARK"   "$HTPL/drift-helpers.sh" 2>/dev/null \
  && grep -qF -- "$CODER_MARK"  "$TPL/agents/harness-coder.md" 2>/dev/null \
  && grep -qF -- "$REV_MARK"    "$TPL/agents/harness-reviewer.md" 2>/dev/null \
  && grep -qF -- "$RULE_MARK"   "$TPL/rules/development-process.md" 2>/dev/null \
  || die "plugin dir $PLUGIN_DIR is not v0.29.0 (templates lack the PR split). Update the plugin first."

handled() {  # $1 = marker, $2 = installed file, $3 = skip label
  grep -qF -- "$1" "$2" 2>/dev/null || grep -qF "v0.29.0-$3" "$SKIPFILE" 2>/dev/null
}

CODER=espalier/agents/harness-coder.md
REV=espalier/agents/harness-reviewer.md
DEV=espalier/rules/development-process.md

missing=""
mark() { missing="$missing
  - $1"; }
[ -f espalier/hooks/espalier-pr.sh ]                                   || mark "espalier/hooks/espalier-pr.sh (the forge surface)"
[ -f espalier/agents/modes/wiki-sweep.md ]                             || mark "espalier/agents/modes/wiki-sweep.md (the sweep procedure)"
grep -qF -- "$PIPE_MARK"  espalier/pipeline.md 2>/dev/null              || mark "pipeline.md Stage 7 (split + sweep + pull requests)"
grep -qF -- "$STAGE_MARK" espalier/skills/espalier/stages/7-10-delivery.md 2>/dev/null || mark "stages/7-10-delivery.md (Stage 7 procedure)"
grep -qF -- "$FIX_MARK"   espalier/skills/espalier-fix/SKILL.md 2>/dev/null || mark "espalier-fix SKILL Stage 7.0 (the split)"
grep -qF -- "$HELP_MARK"  espalier/hooks/drift-helpers.sh 2>/dev/null  || mark "drift-helpers.sh delivery_brief (PR + doc-refresh sections)"
handled "$CODER_MARK" "$CODER" coder-code-only     || mark "harness-coder Commit Discipline — commits are code only"
handled "$REV_MARK"   "$REV"   reviewer-doc-sweep  || mark "harness-reviewer — the Doc Sweep pointer"
handled "$RULE_MARK"  "$DEV"   rules-maintenance-v2 || mark "development-process MAINTENANCE COMMITS v1 → v2"

if [ -z "$missing" ]; then
  log "already at v0.29.0 (every marker present). Nothing to do."
  exit 0
fi

# --- In-flight changes: reported, never retro-split --------------------------
inflight=""
while IFS= read -r st; do
  [ -f "$st" ] || continue
  grep -qE '^- Status:[[:space:]]*(COMPLETE|ABORTED|ABORTED_LATE|ESCALATED|ESCALATED_LATE|FILED)\b' "$st" && continue
  stage=$(grep -E '^(- )?Current Stage:' "$st" 2>/dev/null | head -1 | grep -oE '[0-9]+' | head -1)
  [ -n "$stage" ] && [ "$stage" -ge 7 ] 2>/dev/null && inflight="$inflight
  - ${st#espalier/changes/} (Stage $stage)"
done << EOF_ST
$(find espalier/changes -mindepth 3 -maxdepth 3 -name pipeline-state.md -not -path "*/_template/*" 2>/dev/null)
EOF_ST

if [ "$DRY_RUN" = yes ]; then
  log "DRY RUN — missing:$missing"
  log "DRY RUN — would add espalier-pr.sh + modes/wiki-sweep.md, refresh 4 pure-copy files (backups: .pre-v0.29.bak), and anchored-edit harness-coder.md / harness-reviewer.md / rules/development-process.md"
  [ -n "$inflight" ] && log "DRY RUN — in-flight past Stage 7, would be left on the old single-branch path:$inflight"
  exit 0
fi

if [ "$SKIP_PROMPT" != yes ]; then
  echo "This migration will:"
  echo "  - add espalier/hooks/espalier-pr.sh and espalier/agents/modes/wiki-sweep.md"
  echo "  - refresh pipeline.md, stages/7-10-delivery.md, espalier-fix SKILL and drift-helpers.sh (backups: <file>.pre-v0.29.bak)"
  echo "  - insert the v0.29 text into harness-coder.md, harness-reviewer.md and rules/development-process.md (customised files skipped, never mangled)"
  [ -n "$inflight" ] && echo "  - leave these in-flight changes on the old single-branch path:$inflight"
  printf "Proceed? [y/N] "
  read -r ans
  case "$ans" in y|Y|yes|YES) ;; *) log "aborted."; exit 0 ;; esac
fi

skip() {  # skip <label> <reason>
  printf '%s\t%s\n' "v0.29.0-$1" "$2" >> "$SKIPFILE"
  log "SKIPPED $1 — $2 (recorded in $SKIPFILE)"
}

refresh() {  # refresh <template> <installed>
  [ -f "$1" ] || die "template missing: $1"
  if [ -f "$2" ] && ! cmp -s "$1" "$2"; then cp "$2" "$2.pre-v0.29.bak"; fi
  cp "$1" "$2"
  log "refreshed $2"
}

# --- 1. New files ------------------------------------------------------------
mkdir -p espalier/agents/modes
if [ ! -f espalier/hooks/espalier-pr.sh ]; then
  cp "$HTPL/espalier-pr.sh" espalier/hooks/espalier-pr.sh
  chmod +x espalier/hooks/espalier-pr.sh
  log "added espalier/hooks/espalier-pr.sh"
fi
[ -f espalier/agents/modes/wiki-sweep.md ] \
  || { cp "$TPL/agents/modes/wiki-sweep.md" espalier/agents/modes/wiki-sweep.md; log "added espalier/agents/modes/wiki-sweep.md"; }

# --- 2. Pure-copy refresh ----------------------------------------------------
refresh "$TPL/pipeline.md"                              espalier/pipeline.md
refresh "$TPL/skills/espalier-stages/7-10-delivery.md"  espalier/skills/espalier/stages/7-10-delivery.md
refresh "$TPL/skills/espalier-fix.md"                   espalier/skills/espalier-fix/SKILL.md
refresh "$HTPL/drift-helpers.sh"                        espalier/hooks/drift-helpers.sh

# --- 3. Anchored edits (text extracted from the templates at run time) -------
EDIT_RESULTS=$(TPL="$TPL" CODER="$CODER" REV="$REV" DEV="$DEV" python3 - << 'PYEDIT'
import os, pathlib, re, sys

TPL = pathlib.Path(os.environ["TPL"])
results = []

def block(path, start, end, inclusive_end=True):
    """The template's text from the line containing `start` to the line containing `end`."""
    text = pathlib.Path(path).read_text()
    i = text.index(start)
    j = text.index(end, i)
    return text[i:j + (len(end) if inclusive_end else 0)]

def edit(installed, label, fn):
    p = pathlib.Path(installed)
    if not p.exists():
        results.append((label, "skip", "file not installed")); return
    s = p.read_text()
    try:
        out = fn(s)
    except (ValueError, AssertionError) as e:
        results.append((label, "skip", f"anchor not found ({e})")); return
    if out is None:
        results.append((label, "noop", "already present")); return
    p.write_text(out)
    results.append((label, "done", ""))

# harness-coder: the code-only paragraph, inserted after the Commit Discipline opener
CODER_PARA = block(TPL / "agents/harness-coder.md",
                   "Your commits are CODE ONLY",
                   "which is the thing the split exists to prevent.")
def coder(s):
    if "Your commits are CODE ONLY" in s:
        return None
    anchor = "passes where it exists, the tests you wrote for that unit pass."
    if anchor not in s:
        raise ValueError("Commit Discipline opener")
    return s.replace(anchor, anchor + "\n\n" + CODER_PARA, 1)

# harness-reviewer: the Doc Sweep section (before You Must NOT) + its bullet
REV_SECTION = block(TPL / "agents/harness-reviewer.md",
                    "## Doc Sweep (Stage 7 — your prompt says",
                    "## You Must NOT", inclusive_end=False)
REV_BULLET = block(TPL / "agents/harness-reviewer.md",
                   "- Write a doc patch on a WIKI SWEEP",
                   "change's diff, or delete any doc text there (propose the removal instead)")
def reviewer(s):
    if "## Doc Sweep (Stage 7" in s:
        return None
    if "## You Must NOT" not in s:
        raise ValueError("You Must NOT heading")
    s = s.replace("## You Must NOT", REV_SECTION + "## You Must NOT", 1)
    return s.rstrip("\n") + "\n" + REV_BULLET + "\n"

# development-process: the managed maintenance block, v1 -> v2
DEV_V2 = block(TPL / "rules/development-process.md",
               "<!-- ESPALIER MAINTENANCE COMMITS v2",
               "that invariant is now structural rather than a matter of discipline.")
def dev(s):
    if "ESPALIER MAINTENANCE COMMITS v2" in s:
        return None
    m = re.search(r"<!-- ESPALIER MAINTENANCE COMMITS v1.*?never folded into feature commits\.",
                  s, re.S)
    if not m:
        raise ValueError("MAINTENANCE COMMITS v1 managed block")
    return s[:m.start()] + DEV_V2 + s[m.end():]

edit(os.environ["CODER"], "coder-code-only",      coder)
edit(os.environ["REV"],   "reviewer-doc-sweep",   reviewer)
edit(os.environ["DEV"],   "rules-maintenance-v2", dev)

for label, status, why in results:
    print(f"{label}\t{status}\t{why}")
PYEDIT
) || die "anchored-edit pass failed"

while IFS=$'\t' read -r label status why; do
  [ -n "$label" ] || continue
  case "$status" in
    done) log "edited $label" ;;
    noop) log "$label already present — left alone" ;;
    skip) skip "$label" "$why" ;;
  esac
done << EOF_ED
$EDIT_RESULTS
EOF_ED

log "done. v0.29.0: Stage 7 splits the change into a code PR and an espalier PR,"
log "and sweeps espalier/wiki + espalier/rules against the change's own diff."
[ -n "$inflight" ] && log "in-flight past Stage 7, finishing on the old single-branch path:$inflight"
exit 0
