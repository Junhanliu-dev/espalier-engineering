#!/bin/bash
# Migrate a v0.20.0 Espalier install to v0.21.0.
#
# v0.21.0 is the pipeline-speed release: the same gates, rounds, and review
# contract run with fewer redundant reads and fewer redundant human waits.
# No gate is weakened — every change is a read-scope or dispatch optimization:
#
#   - Context pack: the orchestrator assembles the touched layers / specs /
#     rules / reference files ONCE per change (context-pack.md) and every
#     Stage 3-6 spawn reuses it instead of re-deriving it. Paths and facts
#     only — agents still read the named files and trust current code.
#   - Delta-scoped re-review rounds: round n≥2 panel agents get required
#     reads (fix files + prior findings + direct dependents) as a floor, not
#     a ceiling; security runs delta mode when its own prior round was clean.
#     Both agents still return fresh per-round sentinels and own the
#     whole-change verdict.
#   - Parallel disjoint sub-tasks: Stage 3 sub-tasks with pairwise-disjoint
#     file sets may dispatch concurrently; the panel always reviews the
#     combined diff.
#   - Push-target pre-authorization: the requirements approval gate also
#     collects the Stage 7 push target, so a green run doesn't stall on a
#     redundant confirm. All programmatic push gates unchanged.
#   - Grill: `light`-tier questions that are pairwise independent may be
#     batched into one AskUserQuestion; `full` tier and decision mode stay
#     strictly sequential.
#
# Mechanics:
#   - Refresh 4 pure-copy files from templates (backup-on-diff →
#     <file>.pre-v0.21.bak): espalier/pipeline.md and the espalier /
#     espalier-fix / espalier-grill SKILL files.
#   - Anchored inserts into the 3 per-project agent files (they are
#     substituted at init, never overwritten): coder gains the context-pack
#     step 0; reviewer gains step 0 + the delta read-scope paragraph;
#     security gains step 0 + the delta-mode paragraph. A customised file
#     missing its anchor is warned about + recorded in
#     espalier/.migrations-skipped, never mangled.
#   - No config keys, no hook wiring, no new symlinks.
#
# Usage:
#   bash migrate-v0.20.0-to-v0.21.0.sh [--dry-run] [--yes] [--plugin-dir=<path>]

set -u

DRY_RUN=no
SKIP_PROMPT=no
PLUGIN_DIR="${ESPALIER_PLUGIN_DIR:-}"

for arg in "$@"; do
  case "$arg" in
    --dry-run)       DRY_RUN=yes ;;
    --yes)           SKIP_PROMPT=yes ;;
    --plugin-dir=*)  PLUGIN_DIR="${arg#--plugin-dir=}" ;;
    -h|--help)       sed -n '2,41p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown flag: $arg (use --help)" >&2; exit 2 ;;
  esac
done

log() { echo "[migrate v0.20.0→v0.21.0] $*"; }
die() { echo "[migrate v0.20.0→v0.21.0] ERROR: $*" >&2; exit 1; }

[ -d espalier ] || die "no espalier/ dir — run from the target project root."

# --- Locate plugin templates -------------------------------------------------
if [ -z "$PLUGIN_DIR" ]; then
  _self_root="$(cd "$(dirname "$0")/.." && pwd)"
  [ -d "$_self_root/skills/espalier-init/templates" ] && PLUGIN_DIR="$_self_root"
fi
[ -n "$PLUGIN_DIR" ] || die "cannot locate the plugin. Pass --plugin-dir=<espalier-engineering root>."
TPL="$PLUGIN_DIR/skills/espalier-init/templates"
grep -q 'Stage 3 Entry: Context Pack' "$TPL/skills/espalier.md" 2>/dev/null \
  || die "plugin dir $PLUGIN_DIR is not v0.21.0 (espalier template lacks the context pack). Update the plugin first."

# --- v0.21 markers (also the idempotency check) ------------------------------
# file : marker (fixed string)
PIPE_MARK='DELTA SCOPE'
ESP_MARK='Stage 3 Entry: Context Pack'
FIX_MARK='context-pack.md'
GRILL_MARK='pairwise INDEPENDENT'
CODER_MARK='CONTEXT PACK'
STEP0_MARK='names a CONTEXT PACK'
REV_MARK='Delta read scope'
SEC_MARK='Delta mode (when YOUR prior round was clean)'
SKIPFILE="espalier/.migrations-skipped"

# An agent marker counts as handled when present OR when a prior run recorded
# a customised skip for it — a declined customised file is handled-manual and
# must never keep the migration from reaching "nothing to do" (the v0.10/v0.11
# precedent).
agent_ok() {  # $1 = marker, $2 = file, $3 = skip label
  grep -qF "$1" "$2" 2>/dev/null || grep -qF "v0.21.0-$3" "$SKIPFILE" 2>/dev/null
}

missing=""
mark() { missing="$missing
  - $1"; }
grep -qF "$PIPE_MARK"  espalier/pipeline.md                        2>/dev/null || mark "pipeline.md delta-scope doctrine"
grep -qF "$ESP_MARK"   espalier/skills/espalier/SKILL.md           2>/dev/null || mark "espalier SKILL context pack"
grep -qF "$FIX_MARK"   espalier/skills/espalier-fix/SKILL.md       2>/dev/null || mark "espalier-fix SKILL context pack"
grep -qF "$GRILL_MARK" espalier/skills/espalier-grill/SKILL.md     2>/dev/null || mark "grill light-tier batching rule"
agent_ok "$CODER_MARK" espalier/agents/harness-coder.md    coder-context-pack    || mark "coder context-pack step"
agent_ok "$STEP0_MARK" espalier/agents/harness-reviewer.md reviewer-context-pack || mark "reviewer context-pack step"
agent_ok "$REV_MARK"   espalier/agents/harness-reviewer.md reviewer-delta-scope  || mark "reviewer delta read scope"
agent_ok "$STEP0_MARK" espalier/agents/harness-security.md security-context-pack || mark "security context-pack step"
agent_ok "$SEC_MARK"   espalier/agents/harness-security.md security-delta-mode   || mark "security delta mode"

if [ -z "$missing" ]; then
  log "already at v0.21.0 (every marker present). Nothing to do."
  exit 0
fi

if [ "$DRY_RUN" = yes ]; then
  log "DRY RUN — missing markers:$missing"
  log "DRY RUN — would refresh pipeline.md + espalier/espalier-fix/espalier-grill SKILLs (backup-on-diff → .pre-v0.21.bak)"
  log "DRY RUN — would anchored-insert context-pack/delta sections into the 3 agent files (skip-with-record if customised)"
  exit 0
fi

if [ "$SKIP_PROMPT" != yes ]; then
  echo "This migration will:"
  echo "  - refresh espalier/pipeline.md and 3 pipeline SKILL files from templates (backups: <file>.pre-v0.21.bak)"
  echo "  - insert the context-pack + delta-review sections into the 3 per-project agent files"
  printf "Proceed? [y/N] "
  read -r ans
  case "$ans" in y|Y|yes|YES) ;; *) log "aborted."; exit 0 ;; esac
fi

# --- 1. Pure-copy refresh (backup-on-diff) -----------------------------------
refresh() {  # $1 = template path, $2 = installed path
  [ -f "$1" ] || die "template missing: $1"
  if [ -f "$2" ] && ! cmp -s "$1" "$2"; then
    cp "$2" "$2.pre-v0.21.bak"
  fi
  cp "$1" "$2"
  log "refreshed $2"
}
refresh "$TPL/pipeline.md"              espalier/pipeline.md
refresh "$TPL/skills/espalier.md"       espalier/skills/espalier/SKILL.md
refresh "$TPL/skills/espalier-fix.md"   espalier/skills/espalier-fix/SKILL.md
refresh "$TPL/skills/espalier-grill.md" espalier/skills/espalier-grill/SKILL.md

# --- 2. Anchored inserts into the per-project agent files --------------------
BLK=$(mktemp -t v021blk.XXXX)
trap 'rm -f "$BLK"' EXIT

insert_before() {  # $1 = file, $2 = anchor (fixed string), $3 = label
  local f="$1" anchor="$2" label="$3"
  if ! grep -qF "$anchor" "$f"; then
    log "WARN: $f is customised past the stock shape (anchor for '$label' not found) — skipped."
    log "      Manual step: add the '$label' section from the v0.21 template yourself."
    grep -qF "v0.21.0-$label" "$SKIPFILE" 2>/dev/null \
      || echo "v0.21.0-$label: customised, manual port needed ($f)" >> "$SKIPFILE"
    return 0
  fi
  # Backup ONCE per file: a second insert into the same file must not
  # overwrite the true pre-migration backup with half-migrated content.
  [ -f "$f.pre-v0.21.bak" ] || cp "$f" "$f.pre-v0.21.bak"
  tmp="$f.v21tmp"
  cp "$f" "$tmp"
  awk -v blk="$BLK" -v anchor="$anchor" '
    !done && index($0, anchor) {
      while ((getline line < blk) > 0) print line
      close(blk); done=1
    }
    { print }
  ' "$tmp" > "$f"
  rm -f "$tmp"
  log "inserted '$label' into $f"
}

# 2a. coder — context-pack step 0
if ! grep -qF "$CODER_MARK" espalier/agents/harness-coder.md; then
  cat > "$BLK" << 'EOF'
0. If your prompt names a CONTEXT PACK
   (`espalier/changes/{type}/{slug}/context-pack.md`), read it FIRST. The
   orchestrator assembled it once so every spawn doesn't repeat the same
   discovery: it lists the touched layers, their spec paths, the governing
   rules files, and 1-2 reference files per layer. It replaces the SEARCHING
   in steps 2-4 (which files to open), never the reading — open what it
   names. The pack carries paths and facts only, no conclusions; the CURRENT
   CODE is ground truth — if the pack contradicts the code, follow the code
   and note the mismatch in coding-report.md under "## Staleness
   Encountered". No pack named in your prompt — or the named file missing
   (a pre-v0.21 change resumed mid-flight) — → do steps 1-4 yourself.
EOF
  insert_before espalier/agents/harness-coder.md \
    '1. Read `espalier/skills/espalier-coding/SKILL.md` for the implementation checklist' \
    'coder-context-pack'
fi

# 2b. reviewer — context-pack step 0
if ! grep -qF 'names a CONTEXT PACK' espalier/agents/harness-reviewer.md; then
  cat > "$BLK" << 'EOF'
0. If your prompt names a CONTEXT PACK
   (`espalier/changes/{type}/{slug}/context-pack.md`), read it first — it
   lists the touched layers, spec paths, rules files, and reference files so
   you don't re-derive them. Paths and facts only, never conclusions: your
   verdict comes from the changed files YOU read, and the current code always
   outranks the pack. No pack named — or the file missing — → discover as below.
EOF
  insert_before espalier/agents/harness-reviewer.md \
    '1. Read `espalier/skills/espalier-review/SKILL.md` for the review checklist' \
    'reviewer-context-pack'
fi

# 2c. reviewer — delta read scope
if ! grep -qF "$REV_MARK" espalier/agents/harness-reviewer.md; then
  cat > "$BLK" << 'EOF'
**Delta read scope (a floor, not a ceiling).** On a re-review round your
REQUIRED reads are: (a) every file the fix changed, (b) every file named in
the prior round's findings — verify each is actually resolved, not just
claimed — and (c) the direct callers/dependents of anything the fix changed
(a fix that alters a helper's contract breaks callers it never touched).
Do NOT re-read the entire diff by default — the unchanged remainder was
reviewed fresh in the round it last changed, the orchestrator re-runs
build/lint on the whole tree before every round, and the Reviewed-Diff
fingerprint blocks any unreviewed edit at push. EXPAND beyond the required
scope the moment anything you read makes you suspect wider impact — suspicion
always outranks the scope. The whole-diff verdict rule above is unchanged.

EOF
  insert_before espalier/agents/harness-reviewer.md \
    'Never assume the fix is correct because it addresses your previous finding. Review' \
    'reviewer-delta-scope'
fi

# 2d. security — context-pack step 0
if ! grep -qF 'names a CONTEXT PACK' espalier/agents/harness-security.md; then
  cat > "$BLK" << 'EOF'
0. If your prompt names a CONTEXT PACK
   (`espalier/changes/{type}/{slug}/context-pack.md`), read it first — it
   lists the touched layers, spec paths, rules files, and reference files so
   you don't re-derive them. Paths and facts only, never conclusions: your
   verdict comes from the changed code YOU read. No pack named — or the file
   missing — → discover as below.
EOF
  insert_before espalier/agents/harness-security.md \
    '1. Read `espalier/rules/security-standards.md` — the trust boundary, the sensitive' \
    'security-context-pack'
fi

# 2e. security — delta mode
if ! grep -qF "$SEC_MARK" espalier/agents/harness-security.md; then
  cat > "$BLK" << 'EOF'
**Delta mode (when YOUR prior round was clean).** If your last sentinel on
this change was PASS/PASS_WITH_FIXES with p0=0 p1=0 — the round exists
because the CORRECTNESS reviewer failed, not you — audit the delta instead of
re-auditing everything: read the fix's changed files and answer two
questions. (1) Does the fix introduce any NEW client-supplied value,
endpoint, consumer, or trust-boundary read your prior audit did not cover?
(2) Does it alter the handling of any field already in your
`## Security-Sensitive Fields` contract? Both no → write this round's record
citing the prior audit's scope, carry the contract forward unchanged, and
end with a fresh `VERDICT:` sentinel for THIS round — you saw the current
code and this round's verdict is yours. Either yes — or your prior round had
findings — → full re-audit exactly as on round 1. Delta mode narrows what
you must read, never what you may read, and never your responsibility.

EOF
  insert_before espalier/agents/harness-security.md \
    'Never assume the fix is correct because it addresses your prior finding. Audit the' \
    'security-delta-mode'
fi

# --- 3. Verify ---------------------------------------------------------------
fail=""
grep -qF "$PIPE_MARK"  espalier/pipeline.md                    || fail="$fail pipeline.md"
grep -qF "$ESP_MARK"   espalier/skills/espalier/SKILL.md       || fail="$fail espalier-SKILL"
grep -qF "$FIX_MARK"   espalier/skills/espalier-fix/SKILL.md   || fail="$fail espalier-fix-SKILL"
grep -qF "$GRILL_MARK" espalier/skills/espalier-grill/SKILL.md || fail="$fail grill-SKILL"
[ -n "$fail" ] && die "post-migration verification failed for:$fail"

# Agent files verify only when not recorded as skipped (customised installs).
agent_ok "$CODER_MARK" espalier/agents/harness-coder.md    coder-context-pack    || die "post-migration verification failed: coder lacks '$CODER_MARK'"
agent_ok "$STEP0_MARK" espalier/agents/harness-reviewer.md reviewer-context-pack || die "post-migration verification failed: reviewer lacks step 0"
agent_ok "$REV_MARK"   espalier/agents/harness-reviewer.md reviewer-delta-scope  || die "post-migration verification failed: reviewer lacks '$REV_MARK'"
agent_ok "$STEP0_MARK" espalier/agents/harness-security.md security-context-pack || die "post-migration verification failed: security lacks step 0"
agent_ok "$SEC_MARK"   espalier/agents/harness-security.md security-delta-mode   || die "post-migration verification failed: security lacks '$SEC_MARK'"

log "done. v0.21.0 applied — backups at <file>.pre-v0.21.bak."
log "The pipeline's gates, round caps, and review contract are unchanged;"
log "re-review rounds and sub-agent spawns just read (and wait) less."
exit 0
