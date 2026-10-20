#!/bin/bash
# Migrate a v0.29.0 Espalier install to v0.30.0.
#
# v0.30.0 adds two opt-in lanes and changes nothing for a run that does not
# ask for them:
#
#   --simple on /espalier and /espalier-fix — the human-review lane: grill,
#   spec, ONE approval question, coder (never runs git), reviewer-only Stage 4,
#   exit gate, then a Final Gate in place of Stages 7–10. The code stays
#   UNCOMMITTED for a human to commit by hand; the run's records live in the
#   gitignored espalier/.simple/{slug}/ and Approve deletes them.
#
#   --outside on /espalier-init, and /espalier-repot — the espalier/ tree lives
#   in <parent>/espalier-main/<project>/ with its own local git repo, reached
#   through a locally excluded symlink; the project repo tracks nothing
#   espalier-related and espalier-pr.sh commits the records into that repo
#   instead of projecting an espalier PR.
#
# Contract-equal to v0.29.0 everywhere else: every gate, rubric, sentinel,
# round cap and escalation path is unchanged. NOTHING here sets a budget.
#
#   - Pure-copy refresh (backup-on-diff → <file>.pre-v0.30.bak) — these ship
#     verbatim, so a migrated install ends byte-identical to a fresh one:
#       espalier/skills/espalier/SKILL.md          the router (--simple, install discovery)
#       espalier/skills/espalier/stages/simple.md  the simple-mode procedure (new)
#       espalier/skills/espalier/stages/7-10-delivery.md  (outside-mode note)
#       espalier/skills/espalier-fix/SKILL.md      the fix lane (--simple, discovery)
#       espalier/skills/espalier-repot/SKILL.md    the repot lane (new; + its symlinks)
#       espalier/pipeline.md
#       espalier/hooks/drift-helpers.sh            simple_brief
#       espalier/hooks/espalier-pr.sh              outside mode
#       espalier/hooks/espalier-outside.sh         prepare / discover / commit / repot (new; executable)
#   - Anchored edits, text EXTRACTED from the plugin templates at run time
#     (these files carry init-time project substitutions and are never copied;
#     backup-on-change → <file>.pre-v0.30.bak):
#       espalier/agents/harness-coder.md   `## Simple Mode: Never Run Git` before `## Fix Rounds`
#       espalier/agent.md                  the Repot row after the Prune row of the lane table
#     A customised file missing its anchor is SKIPPED with a record in
#     espalier/.migrations-skipped, never mangled.
#   - .gitignore gains `espalier/.simple/` once (inside installs; an outside
#     install excludes the whole symlink and needs nothing).
#   - Symlinks: .claude/skills/espalier-repot (+ .agents/skills and
#     .github/skills per espalier/.platforms).
#   - In-flight changes are reported, never touched: nothing in this release
#     changes the procedure of a change already past Stage 1.
#   No config key, no hook registration, no validation-count change.
#
# Usage:
#   bash migrate-v0.29.0-to-v0.30.0.sh [--dry-run] [--yes] [--plugin-dir=<path>]

set -u

DRY_RUN=no
SKIP_PROMPT=no
PLUGIN_DIR="${ESPALIER_PLUGIN_DIR:-}"

for arg in "$@"; do
  case "$arg" in
    --dry-run)       DRY_RUN=yes ;;
    --yes)           SKIP_PROMPT=yes ;;
    --plugin-dir=*)  PLUGIN_DIR="${arg#--plugin-dir=}" ;;
    -h|--help)       sed -n '2,50p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown flag: $arg (use --help)" >&2; exit 2 ;;
  esac
done

log() { echo "[migrate v0.29.0→v0.30.0] $*"; }
die() { echo "[migrate v0.29.0→v0.30.0] ERROR: $*" >&2; exit 1; }

[ -d espalier ] || die "no espalier/ dir — run from the target project root."

# --- Locate plugin templates --------------------------------------------------
if [ -z "$PLUGIN_DIR" ]; then
  _self_root="$(cd "$(dirname "$0")/.." && pwd)"
  [ -d "$_self_root/skills/espalier-init/templates" ] && PLUGIN_DIR="$_self_root"
fi
[ -n "$PLUGIN_DIR" ] || die "cannot locate the plugin. Pass --plugin-dir=<espalier-engineering root>."
TPL="$PLUGIN_DIR/skills/espalier-init/templates"
HTPL="$PLUGIN_DIR/skills/espalier-init/hook-templates"
SKIPFILE="espalier/.migrations-skipped"

# --- v0.30.0 markers (also the idempotency check) ---------------------------
# Each names text only the FINAL v0.30.0 shape of its file carries.
ROUTER_MARK='Set `SIMPLE_MODE=yes`'
FIX_MARK='--simple)        SIMPLE_MODE="yes"'
SIMPLE_MARK='### The Final Gate (replaces Stages 7–10, both lanes)'
STAGE7_MARK='**Outside mode (v0.30'
PIPE_MARK='a MODE of `/espalier` and `/espalier-fix`, not a lane'
HELP_MARK='simple_brief() {'
PR_MARK='outside_commit()'
OUT_MARK='repot-out)'
REPOT_MARK='name: espalier-repot'
CODER_MARK='## Simple Mode: Never Run Git'
AGENT_MARK='Via /espalier-repot'
IGNORE_ENTRY='espalier/.simple/'

grep -qF -- "$ROUTER_MARK" "$TPL/skills/espalier.md" 2>/dev/null \
  && grep -qF -- "$FIX_MARK"    "$TPL/skills/espalier-fix.md" 2>/dev/null \
  && grep -qF -- "$SIMPLE_MARK" "$TPL/skills/espalier-stages/simple.md" 2>/dev/null \
  && grep -qF -- "$STAGE7_MARK" "$TPL/skills/espalier-stages/7-10-delivery.md" 2>/dev/null \
  && grep -qF -- "$PIPE_MARK"   "$TPL/pipeline.md" 2>/dev/null \
  && grep -qF -- "$HELP_MARK"   "$HTPL/drift-helpers.sh" 2>/dev/null \
  && grep -qF -- "$PR_MARK"     "$HTPL/espalier-pr.sh" 2>/dev/null \
  && grep -qF -- "$OUT_MARK"    "$HTPL/espalier-outside.sh" 2>/dev/null \
  && grep -qF -- "$REPOT_MARK"  "$TPL/skills/espalier-repot.md" 2>/dev/null \
  && grep -qF -- "$CODER_MARK"  "$TPL/agents/harness-coder.md" 2>/dev/null \
  && grep -qF -- "$AGENT_MARK"  "$TPL/agent.md" 2>/dev/null \
  || die "plugin dir $PLUGIN_DIR is not v0.30.0 (templates lack the simple lane / outside mode). Update the plugin first."

handled() {  # $1 = marker, $2 = installed file, $3 = skip label
  grep -qF -- "$1" "$2" 2>/dev/null || grep -qF "v0.30.0-$3" "$SKIPFILE" 2>/dev/null
}

# Outside mode: the symlink is excluded whole; .gitignore is a tracked file
# this install must not touch.
OUTSIDE=no
if [ -L espalier ]; then
  _lt="$(readlink espalier)"; case "$_lt" in /*) ;; *) _lt="$PWD/$_lt" ;; esac
  [ -f "$(dirname "$_lt")/.espalier-origin" ] && OUTSIDE=yes
fi
grep -q '^outside-root:' espalier/.espalier-config 2>/dev/null && OUTSIDE=yes

PLATFORMS=$(head -1 espalier/.platforms 2>/dev/null | tr -d '[:space:]')
[ -n "$PLATFORMS" ] || PLATFORMS=claude
want_claude()  { case ",$PLATFORMS," in *,claude,*)  return 0 ;; esac; [ -d .claude/skills ]; }
want_codex()   { case ",$PLATFORMS," in *,codex,*)   return 0 ;; esac; return 1; }
want_copilot() { case ",$PLATFORMS," in *,copilot,*) return 0 ;; esac; return 1; }

CODER=espalier/agents/harness-coder.md
AGENT=espalier/agent.md

missing=""
mark() { missing="$missing
  - $1"; }
grep -qF -- "$ROUTER_MARK" espalier/skills/espalier/SKILL.md 2>/dev/null          || mark "espalier SKILL (--simple flag, install discovery)"
grep -qF -- "$FIX_MARK"    espalier/skills/espalier-fix/SKILL.md 2>/dev/null      || mark "espalier-fix SKILL (--simple flag, install discovery)"
grep -qF -- "$SIMPLE_MARK" espalier/skills/espalier/stages/simple.md 2>/dev/null  || mark "stages/simple.md (the simple-mode procedure)"
grep -qF -- "$STAGE7_MARK" espalier/skills/espalier/stages/7-10-delivery.md 2>/dev/null || mark "stages/7-10-delivery.md (outside-mode note)"
grep -qF -- "$PIPE_MARK"   espalier/pipeline.md 2>/dev/null                       || mark "pipeline.md (the --simple mode + repot lane notes)"
grep -qF -- "$HELP_MARK"   espalier/hooks/drift-helpers.sh 2>/dev/null            || mark "drift-helpers.sh simple_brief"
grep -qF -- "$PR_MARK"     espalier/hooks/espalier-pr.sh 2>/dev/null              || mark "espalier-pr.sh (outside mode)"
grep -qF -- "$OUT_MARK"    espalier/hooks/espalier-outside.sh 2>/dev/null         || mark "espalier/hooks/espalier-outside.sh (outside mode: prepare / discover / commit / repot)"
grep -qF -- "$REPOT_MARK"  espalier/skills/espalier-repot/SKILL.md 2>/dev/null    || mark "espalier-repot SKILL (the repot lane)"
handled "$CODER_MARK" "$CODER" coder-simple-mode  || mark "harness-coder.md — Simple Mode section"
handled "$AGENT_MARK" "$AGENT" agent-repot-row    || mark "agent.md — the Repot lane row"
if want_claude;  then [ -L .claude/skills/espalier-repot ] || mark ".claude/skills/espalier-repot link"; fi
if want_codex;   then [ -L .agents/skills/espalier-repot ] || mark ".agents/skills/espalier-repot link"; fi
if want_copilot; then [ -L .github/skills/espalier-repot ] || mark ".github/skills/espalier-repot link"; fi
if [ "$OUTSIDE" != yes ]; then
  grep -qxF -- "$IGNORE_ENTRY" .gitignore 2>/dev/null || mark ".gitignore entry espalier/.simple/"
fi

if [ -z "$missing" ]; then
  log "already at v0.30.0 (every marker present). Nothing to do."
  exit 0
fi

# --- In-flight changes: reported, never touched ------------------------------
inflight=""
while IFS= read -r st; do
  [ -f "$st" ] || continue
  grep -qE '^- Status:[[:space:]]*(COMPLETE|ABORTED|ABORTED_LATE|ESCALATED|ESCALATED_LATE|FILED|PARTIAL_FIX)\b' "$st" && continue
  stage=$(grep -E '^(- )?Current Stage:' "$st" 2>/dev/null | head -1 | grep -oE '[0-9]+' | head -1)
  inflight="$inflight
  - ${st#espalier/changes/} (Stage ${stage:-?})"
done << EOF_ST
$(find espalier/changes -mindepth 3 -maxdepth 3 -name pipeline-state.md -not -path "*/_template/*" 2>/dev/null)
EOF_ST
INFLIGHT_NOTE="resume as before — nothing in v0.30.0 changes the procedure of a change already past Stage 1:"

if [ "$DRY_RUN" = yes ]; then
  log "DRY RUN — missing:$missing"
  log "DRY RUN — would refresh 9 pure-copy files (stages/simple.md, espalier-outside.sh and the espalier-repot SKILL among them; backups: .pre-v0.30.bak), link the repot skill for platforms: $PLATFORMS, anchored-edit harness-coder.md / agent.md (backups: .pre-v0.30.bak)$([ "$OUTSIDE" = yes ] || printf ', and add %s to .gitignore' "$IGNORE_ENTRY")"
  [ -n "$inflight" ] && log "DRY RUN — in flight, $INFLIGHT_NOTE$inflight"
  exit 0
fi

if [ "$SKIP_PROMPT" != yes ]; then
  echo "This migration will:"
  echo "  - add espalier/hooks/espalier-outside.sh, espalier/skills/espalier/stages/simple.md and espalier/skills/espalier-repot/SKILL.md (+ its symlinks for: $PLATFORMS)"
  echo "  - refresh the espalier and espalier-fix SKILLs, stages/7-10-delivery.md, pipeline.md, drift-helpers.sh and espalier-pr.sh (backups: <file>.pre-v0.30.bak)"
  echo "  - insert the v0.30 text into harness-coder.md and agent.md (customised files skipped, never mangled; backups: <file>.pre-v0.30.bak)"
  [ "$OUTSIDE" = yes ] || echo "  - add '$IGNORE_ENTRY' to .gitignore"
  [ -n "$inflight" ] && echo "  - NOTE: these in-flight changes $INFLIGHT_NOTE$inflight"
  printf "Proceed? [y/N] "
  read -r ans
  case "$ans" in y|Y|yes|YES) ;; *) log "aborted."; exit 0 ;; esac
fi

skip() {  # skip <label> <reason>
  printf '%s\t%s\n' "v0.30.0-$1" "$2" >> "$SKIPFILE"
  log "SKIPPED $1 — $2 (recorded in $SKIPFILE)"
}

BACKUPS=""
refresh() {  # refresh <template> <installed>
  [ -f "$1" ] || die "template missing: $1"
  if [ -f "$2" ] && cmp -s "$1" "$2"; then
    log "$2 already current"; return 0
  fi
  if [ -f "$2" ]; then
    cp "$2" "$2.pre-v0.30.bak" || die "could not back up $2"
    BACKUPS="$BACKUPS
  - $2.pre-v0.30.bak"
  fi
  mkdir -p "$(dirname "$2")" || die "could not create $(dirname "$2")"
  cp "$1" "$2" || die "could not write $2"
  log "refreshed $2"
}

# --- 1. Anchored edits FIRST (text extracted from the templates at run time) -
# Every extraction happens before any file is written, so a plugin whose
# templates lack an anchor dies here with the install untouched.
EDIT_RESULTS=$(TPL="$TPL" CODER="$CODER" AGENT="$AGENT" python3 - << 'PYEDIT'
import os, pathlib, shutil, sys

TPL = pathlib.Path(os.environ["TPL"])
results = []

def block(path, start, end):
    text = pathlib.Path(path).read_text()
    i = text.index(start)
    j = text.index(end, i)
    return text[i:j]

try:
    # harness-coder: the whole Simple Mode section, up to (not including) Fix Rounds
    CODER_SECTION = block(TPL / "agents/harness-coder.md",
                          "## Simple Mode: Never Run Git",
                          "## Fix Rounds: Fix the Class, Not the Instance")
    # agent.md: the Repot row of the lane table (one line)
    agent_tpl = (TPL / "agent.md").read_text()
    AGENT_ROW = next(l for l in agent_tpl.splitlines() if "Via /espalier-repot" in l) + "\n"
except (OSError, ValueError, StopIteration) as e:
    print(f"TEMPLATE\t{e}")
    sys.exit(3)

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
    shutil.copyfile(p, str(p) + ".pre-v0.30.bak")
    p.write_text(out)
    results.append((label, "done", str(p) + ".pre-v0.30.bak"))

def coder(s):
    if "## Simple Mode: Never Run Git" in s:
        return None
    anchor = "## Fix Rounds: Fix the Class, Not the Instance"
    if anchor not in s:
        raise ValueError("Fix Rounds heading")
    return s.replace(anchor, CODER_SECTION + anchor, 1)

def agent(s):
    if "Via /espalier-repot" in s:
        return None
    lines = s.splitlines(keepends=True)
    idx = next((i for i, l in enumerate(lines) if l.startswith("| Prune ")), None)
    if idx is None:
        raise ValueError("Prune row of the lane table")
    lines.insert(idx + 1, AGENT_ROW)
    return "".join(lines)

edit(os.environ["CODER"], "coder-simple-mode", coder)
edit(os.environ["AGENT"], "agent-repot-row",   agent)

for label, status, why in results:
    print(f"{label}\t{status}\t{why}")
PYEDIT
)
rc=$?
case "$rc" in
  0) ;;
  3) die "plugin templates lack an anchor this migration extracts (${EDIT_RESULTS#*	}) — nothing was changed. Update the plugin." ;;
  *) die "anchored-edit pass failed (python3 exit $rc) — check that python3 is installed" ;;
esac

while IFS=$'\t' read -r label status why; do
  [ -n "$label" ] || continue
  case "$status" in
    done) log "edited $label"; BACKUPS="$BACKUPS
  - $why" ;;
    noop) log "$label already present — left alone" ;;
    skip) skip "$label" "$why" ;;
  esac
done << EOF_ED
$EDIT_RESULTS
EOF_ED

# --- 2. Pure-copy refresh ----------------------------------------------------
refresh "$TPL/skills/espalier.md"                        espalier/skills/espalier/SKILL.md
refresh "$TPL/skills/espalier-stages/simple.md"          espalier/skills/espalier/stages/simple.md
refresh "$TPL/skills/espalier-stages/7-10-delivery.md"   espalier/skills/espalier/stages/7-10-delivery.md
refresh "$TPL/skills/espalier-fix.md"                    espalier/skills/espalier-fix/SKILL.md
refresh "$TPL/skills/espalier-repot.md"                  espalier/skills/espalier-repot/SKILL.md
refresh "$TPL/pipeline.md"                               espalier/pipeline.md
refresh "$HTPL/drift-helpers.sh"                         espalier/hooks/drift-helpers.sh
refresh "$HTPL/espalier-pr.sh"                           espalier/hooks/espalier-pr.sh
chmod +x espalier/hooks/espalier-pr.sh || die "could not chmod espalier/hooks/espalier-pr.sh"
refresh "$HTPL/espalier-outside.sh"                      espalier/hooks/espalier-outside.sh
chmod +x espalier/hooks/espalier-outside.sh || die "could not chmod espalier/hooks/espalier-outside.sh"

# --- 3. Symlinks for the repot skill ------------------------------------------
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
  _safe_ln ../../espalier/skills/espalier-repot .claude/skills/espalier-repot
  log "linked .claude/skills/espalier-repot"
fi
if want_codex; then
  mkdir -p .agents/skills
  _safe_ln ../../espalier/skills/espalier-repot .agents/skills/espalier-repot
  log "linked .agents/skills/espalier-repot"
fi
if want_copilot; then
  mkdir -p .github/skills
  _safe_ln ../../espalier/skills/espalier-repot .github/skills/espalier-repot
  log "linked .github/skills/espalier-repot"
fi

# --- 4. .gitignore: the --simple scratch dir (inside installs only) ----------
if [ "$OUTSIDE" != yes ] && ! grep -qxF -- "$IGNORE_ENTRY" .gitignore 2>/dev/null; then
  if [ -s .gitignore ] && [ -n "$(tail -c1 .gitignore)" ]; then printf '\n' >> .gitignore; fi
  printf '%s\n' "$IGNORE_ENTRY" >> .gitignore
  log "added '$IGNORE_ENTRY' to .gitignore (the --simple lane's scratch dir)"
fi

log "done. v0.30.0: --simple on /espalier and /espalier-fix (human-review lane, code left uncommitted),"
log "--outside on /espalier-init and /espalier-repot (the espalier/ tree outside the repo, local git)."
[ -n "$BACKUPS" ] && log "backups of every file this run replaced or edited (customisations to port by hand live here):$BACKUPS"
[ -n "$inflight" ] && log "in flight — these $INFLIGHT_NOTE$inflight"
[ "$OUTSIDE" = yes ] && log "outside install: commit this migration into the outside repo — bash espalier/hooks/espalier-outside.sh commit \"\$(git rev-parse --show-toplevel)\" 'chore(espalier): migrate to v0.30.0'"
exit 0
