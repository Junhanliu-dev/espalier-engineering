#!/bin/bash
# Migrate a v0.24.0 Espalier install to v0.25.0.
#
# v0.25.0 is the quality-first context release: every agent works with its
# instructions at full strength on current inputs — smaller context is the
# by-product, never the goal, and NOTHING here sets a budget or refuses on
# size. Contract-equal to v0.24.0: every gate, rubric, sentinel, round cap,
# and escalation path is unchanged.
#
#   - Pure-copy refresh (backup-on-diff → <file>.pre-v0.25.bak):
#     espalier/pipeline.md (now the stage CONTRACT); the espalier SKILL (now a
#     ROUTER) plus its five NEW stage files under
#     espalier/skills/espalier/stages/; the five NEW agent mode files under
#     espalier/agents/modes/; the espalier-fix, espalier-requirements,
#     espalier-grill, espalier-map, espalier-audit, espalier-ask,
#     espalier-simplify, espalier-prune, espalier-doctor SKILLs;
#     espalier/.scout-prompts.md; espalier/hooks/{drift-helpers.sh,
#     maprun.py, espalier-stats.sh}. A whole-file refresh replaces a
#     customised copy (backed up, never merged) — the mechanism every
#     migration has used for these files.
#   - Anchored edits, text EXTRACTED from the plugin templates at run time so
#     a migrated install is byte-identical to a fresh one in those sections:
#     harness-coder.md (Handoff protocol, Docs clause, read-once / Grep-only /
#     Scoped-docs lines, report shape + hygiene, rules reword lines, contract
#     file reads); harness-reviewer.md (Before Reviewing lines, spec-citation
#     check, advisory row rules + `docs:` tag, contract file read);
#     harness-security.md (Before Auditing lines); the seven mode-only
#     sections (coder Fix Rounds + Simplification Changes; reviewer Re-review
#     Rounds + Simplification Review + Security Abuse-Test Coverage; security
#     Re-review Rounds + Repo-Audit Mode) become a heading + one-line pointer
#     at the mode file (the text is read when the prompt names the mode);
#     the espalier-testing SKILL (contract file read); espalier/agent.md
#     (Config + Pipeline rows); espalier/rules/engineering-structure.md
#     (`## Not Precedent` anchor).
#     A customised file missing its anchor is skipped with a record in
#     espalier/.migrations-skipped, never mangled. An install that already
#     carries a section's v0.25 text (the rules reword lines on some installs)
#     no-ops that step.
#   - Config: `grep-only-paths:` appended to espalier/.espalier-config
#     (grep-guarded, comment included). No budget keys; no gate-command keys
#     (exit_gate reads the installed pre-push gate's own run_* bodies).
#   - .gitignore gains `*.pre-v0.*.bak` once (existing tracked backups are
#     left alone).
#   - Report, do not act: req_shape_check on every IN_PROGRESS change and the
#     rules contract-drift totals — the migration never rewrites a rule or a
#     requirement; that is /espalier-prune's interactive, per-file gate.
#   No new instruction-file line, no hooks, no symlinks.
#
# Usage:
#   bash migrate-v0.24.0-to-v0.25.0.sh [--dry-run] [--yes] [--plugin-dir=<path>]

set -u

DRY_RUN=no
SKIP_PROMPT=no
PLUGIN_DIR="${ESPALIER_PLUGIN_DIR:-}"

for arg in "$@"; do
  case "$arg" in
    --dry-run)       DRY_RUN=yes ;;
    --yes)           SKIP_PROMPT=yes ;;
    --plugin-dir=*)  PLUGIN_DIR="${arg#--plugin-dir=}" ;;
    -h|--help)       sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown flag: $arg (use --help)" >&2; exit 2 ;;
  esac
done

log() { echo "[migrate v0.24.0→v0.25.0] $*"; }
die() { echo "[migrate v0.24.0→v0.25.0] ERROR: $*" >&2; exit 1; }

[ -d espalier ] || die "no espalier/ dir — run from the target project root."

# --- Locate plugin templates (probe: this release's own helper) --------------
if [ -z "$PLUGIN_DIR" ]; then
  _self_root="$(cd "$(dirname "$0")/.." && pwd)"
  [ -d "$_self_root/skills/espalier-init/templates" ] && PLUGIN_DIR="$_self_root"
fi
[ -n "$PLUGIN_DIR" ] || die "cannot locate the plugin. Pass --plugin-dir=<espalier-engineering root>."
TPL="$PLUGIN_DIR/skills/espalier-init/templates"
HTPL="$PLUGIN_DIR/skills/espalier-init/hook-templates"
SKIPFILE="espalier/.migrations-skipped"

# --- v0.25.0 markers (also the idempotency check) ----------------------------
HELPERS_MARK='scoped_docs()'
STATS_MARK='Spawn shape (per change)'
MAPRUN_MARK='STAGE_LABEL_FALLBACK'
PIPE_MARK='exit_gate'
LANE_MARK='HANDOFF: true'
ROUTER_MARK='stages/3-coding.md'
STAGE_FILES='1-2-requirements 3-coding 4-panel 5-6-contract 7-10-delivery'
MODE_FILES='fix-round simplification re-review repo-audit stage6-abuse-coverage'
REQ_MARK='Contract and notes'
GRILL_MARK='Resolved by grill'
MAP_MARK='unlimited code reads'
AUDIT_MARK='auto-loaded'
NOTES_MARK='requirements-notes.md'
PRUNE_MARK='Removed rules'
DOCTOR_MARK='contract drift'
SCOUT_MARK='Writing Contract'
CFG_KEY='grep-only-paths'
NP_TOKEN='ESPALIER NOT PRECEDENT v1'
# coder
CODER_HANDOFF='## Handoff: Finish Bounded, Hand Off Clean'
CODER_HANDOFF_END='task list.'
CODER_DOCS='**Docs.** When your change makes a claim'
CODER_DOCS_END="\`/espalier-prune\`'s, not yours."
CODER_READ='8. Read once.'
CODER_READ_END='the code before relying on it, as with the pack.'
CODER_REPORT='- Spec applied:'
CODER_PROSE='Write the report FRESH'
CODER_PROSE_END='(see Docs under Editing Discipline).'
CODER_SEC='`espalier/rules/security-standards.md` (auto-loaded'
CODER_PROD='Apply `espalier/rules/production-standards.md` (auto-loaded'
CODER_CONTRACT='security-contract.md` — the'
CODER_ENTRY='Read `security-contract.md`'
# reviewer
REV_BEFORE="6. Earlier spawns' reports are in \`coding-log/\`"
REV_SPEC='[spec-unread]'
REV_MIN='Each advisory finding is ONE row'
REV_MIN_END='There is no count either way.'
REV_DOCS='- `docs:` a doc diff'
REV_DOCS_END='round; no count.'
# security
SEC_BEFORE='7. Scoped docs named in the pack'
# mode pointers (the body keeps the heading + a one-line pointer)
CODER_FIXMODE='modes/fix-round.md'
CODER_SIMPMODE='modes/simplification.md'
REV_RRMODE='(its harness-reviewer'
REV_SIMPMODE='the independent re-search of every retired name'
REV_ABUSEMODE='modes/stage6-abuse-coverage.md'
SEC_RRMODE='(its harness-security section)'
SEC_AUDITMODE='modes/repo-audit.md'
# testing skill / agent.md
TEST_MARK='security-contract.md'
AGENT_MARK='grep-only-paths'
AGENT_PIPE_MARK='stages/'

grep -qF "$HELPERS_MARK" "$HTPL/drift-helpers.sh" 2>/dev/null \
  && grep -qF "$CODER_HANDOFF" "$TPL/agents/harness-coder.md" 2>/dev/null \
  && grep -qF "$REV_SPEC" "$TPL/agents/harness-reviewer.md" 2>/dev/null \
  && grep -qF "$SEC_BEFORE" "$TPL/agents/harness-security.md" 2>/dev/null \
  && grep -qF "$ROUTER_MARK" "$TPL/skills/espalier.md" 2>/dev/null \
  && [ -f "$TPL/skills/espalier-stages/3-coding.md" ] && grep -qF "$LANE_MARK" "$TPL/skills/espalier-stages/3-coding.md" 2>/dev/null \
  && [ -f "$TPL/agents/modes/fix-round.md" ] \
  && grep -qF "$LANE_MARK" "$TPL/skills/espalier-fix.md" 2>/dev/null \
  && grep -qF "$NP_TOKEN" "$TPL/rules/engineering-structure.md" 2>/dev/null \
  && grep -qF "$STATS_MARK" "$HTPL/espalier-stats.sh" 2>/dev/null \
  && grep -qF "$MAPRUN_MARK" "$HTPL/maprun.py" 2>/dev/null \
  || die "plugin dir $PLUGIN_DIR is not v0.25.0 (templates lack the context helpers / spawn protocols). Update the plugin first."

handled() {  # $1 = marker, $2 = file, $3 = skip label
  grep -qF -- "$1" "$2" 2>/dev/null || grep -qF "v0.25.0-$3" "$SKIPFILE" 2>/dev/null
}

missing=""
mark() { missing="$missing
  - $1"; }
grep -qF "$HELPERS_MARK" espalier/hooks/drift-helpers.sh  2>/dev/null || mark "drift-helpers.sh context helpers (report_archive / contract_extract / exit_gate / grep_only_files / scoped_docs / rule_bullets / contract_drift_lines)"
grep -qF "$STATS_MARK"   espalier/hooks/espalier-stats.sh 2>/dev/null || mark "espalier-stats.sh spawn-shape + workspace-docs sections"
grep -qF "$MAPRUN_MARK"  espalier/hooks/maprun.py         2>/dev/null || mark "maprun.py stage-name regex fix + fallback labels"
grep -qF "$PIPE_MARK"    espalier/pipeline.md             2>/dev/null || mark "pipeline.md (exit_gate + handoff contract)"
grep -qF "$ROUTER_MARK"  espalier/skills/espalier/SKILL.md     2>/dev/null || mark "espalier SKILL as the router (Stage Execution Protocol names the stage files)"
for _f in $STAGE_FILES; do cmp -s "$TPL/skills/espalier-stages/$_f.md" "espalier/skills/espalier/stages/$_f.md" 2>/dev/null || mark "espalier/skills/espalier/stages/$_f.md (stage procedure)"; done
for _f in $MODE_FILES;  do cmp -s "$TPL/agents/modes/$_f.md" "espalier/agents/modes/$_f.md" 2>/dev/null || mark "espalier/agents/modes/$_f.md (agent mode file)"; done
grep -qF "$LANE_MARK"    espalier/skills/espalier-fix/SKILL.md 2>/dev/null || mark "espalier-fix SKILL (handoff guard, resume offers, pack lines, gate helper)"
grep -qF "$REQ_MARK"     espalier/skills/espalier-requirements/SKILL.md 2>/dev/null || mark "espalier-requirements SKILL (sizing paragraph replaces the ≤ 5 files rule; contract + notes)"
grep -qF "$GRILL_MARK"   espalier/skills/espalier-grill/SKILL.md 2>/dev/null || mark "espalier-grill SKILL (unlimited code reads; notes file)"
grep -qF "$MAP_MARK"     espalier/skills/espalier-map/SKILL.md   2>/dev/null || mark "espalier-map SKILL (unlimited code reads)"
grep -qF "$AUDIT_MARK"   espalier/skills/espalier-audit/SKILL.md 2>/dev/null || mark "espalier-audit SKILL (spawn line reword)"
grep -qF "$NOTES_MARK"   espalier/skills/espalier-ask/SKILL.md   2>/dev/null || mark "espalier-ask SKILL (requirements-notes why-source)"
grep -qF "$NOTES_MARK"   espalier/skills/espalier-simplify/SKILL.md 2>/dev/null || mark "espalier-simplify SKILL (requirements-notes decision history)"
grep -qF "$PRUNE_MARK"   espalier/skills/espalier-prune/SKILL.md 2>/dev/null || mark "espalier-prune SKILL (Removed-rules ledger, Not Precedent refresh)"
grep -qF "$DOCTOR_MARK"  espalier/skills/espalier-doctor/SKILL.md 2>/dev/null || mark "espalier-doctor SKILL (contract drift line)"
grep -qF "$SCOUT_MARK"   espalier/.scout-prompts.md      2>/dev/null || mark ".scout-prompts.md (Writing Contract, not_precedent array)"
CODER=espalier/agents/harness-coder.md
REV=espalier/agents/harness-reviewer.md
SEC=espalier/agents/harness-security.md
TESTSK=espalier/skills/espalier-testing/SKILL.md
AGENT=espalier/agent.md
RULE=espalier/rules/engineering-structure.md
handled "$CODER_HANDOFF"  "$CODER" coder-handoff    || mark "coder Handoff section"
handled "$CODER_DOCS"     "$CODER" coder-docs       || mark "coder Docs clause"
handled "$CODER_READ"     "$CODER" coder-read-once  || mark "coder read-once / Grep-only / Scoped-docs lines"
handled "$CODER_REPORT"   "$CODER" coder-report     || mark "coder report shape (Prior reports / Spec applied / Docs lines)"
handled "$CODER_PROSE"    "$CODER" coder-report-prose || mark "coder report prose (overwrite semantics, spec line, hygiene)"
handled "$CODER_SEC"      "$CODER" coder-reword-security   || mark "coder security-standards reword line"
handled "$CODER_PROD"     "$CODER" coder-reword-production || mark "coder production-standards reword line"
handled "$CODER_CONTRACT" "$CODER" coder-contract-read   || mark "coder abuse-test contract file read"
handled "$CODER_ENTRY"    "$CODER" coder-contract-entry  || mark "coder CONTRACT PHASE entry point"
handled "$REV_BEFORE"     "$REV" reviewer-before    || mark "reviewer Before Reviewing lines (reword, read-once, Grep-only, Scoped-docs, coding-log)"
handled "$REV_SPEC"       "$REV" reviewer-spec      || mark "reviewer spec-citation check ([spec-unread])"
handled "$REV_MIN"        "$REV" reviewer-advisory-rows || mark "reviewer Minimalism advisory row rule"
handled "$REV_DOCS"       "$REV" reviewer-docs-tag  || mark "reviewer docs: tag + Readability row rule"
handled "$SEC_BEFORE"     "$SEC" security-before    || mark "security Before Auditing lines (reword, coding-log, Read-tool evidence, read-once, Grep-only, Scoped-docs)"
handled "$CODER_FIXMODE"  "$CODER" coder-mode-fix-round      || mark "coder Fix Rounds → modes/fix-round.md pointer"
handled "$CODER_SIMPMODE" "$CODER" coder-mode-simplification || mark "coder Simplification Changes → modes/simplification.md pointer"
handled "$REV_RRMODE"     "$REV" reviewer-mode-re-review     || mark "reviewer Re-review Rounds → modes/re-review.md pointer"
handled "$REV_SIMPMODE"   "$REV" reviewer-mode-simplification || mark "reviewer Simplification Review → modes/simplification.md pointer"
handled "$REV_ABUSEMODE"  "$REV" reviewer-mode-abuse-coverage || mark "reviewer Security Abuse-Test Coverage → modes/stage6-abuse-coverage.md pointer"
handled "$SEC_RRMODE"     "$SEC" security-mode-re-review     || mark "security Re-review Rounds → modes/re-review.md pointer"
handled "$SEC_AUDITMODE"  "$SEC" security-mode-repo-audit    || mark "security Repo-Audit Mode → modes/repo-audit.md pointer"
if [ -f "$TESTSK" ]; then handled "$TEST_MARK" "$TESTSK" testing-contract-read || mark "espalier-testing SKILL contract file read"; fi
if [ -f "$AGENT" ];  then handled "$AGENT_MARK" "$AGENT" agent-config-row || mark "agent.md Config row (grep-only-paths)"; handled "$AGENT_PIPE_MARK" "$AGENT" agent-pipeline-row || mark "agent.md Pipeline row (stages/)"; fi
if [ -f "$RULE" ];   then grep -qF "$NP_TOKEN" "$RULE" 2>/dev/null || mark "engineering-structure.md ## Not Precedent anchor"; fi
grep -q "^$CFG_KEY:" espalier/.espalier-config 2>/dev/null || mark ".espalier-config grep-only-paths key"
grep -qxF '*.pre-v0.*.bak' .gitignore 2>/dev/null || mark ".gitignore backup pattern"

if [ -z "$missing" ]; then
  log "already at v0.25.0 (every marker present). Nothing to do."
  exit 0
fi

if [ "$DRY_RUN" = yes ]; then
  log "DRY RUN — missing markers:$missing"
  log "DRY RUN — would refresh up to 25 pure-copy files (pipeline.md, the espalier router + 5 stage files, 5 agent mode files, 9 lane SKILLs, .scout-prompts.md, drift-helpers.sh, maprun.py, espalier-stats.sh; backup-on-diff → .pre-v0.25.bak)"
  log "DRY RUN — would anchored-edit harness-coder.md, harness-reviewer.md, harness-security.md (incl. the 7 mode-only sections → heading + pointer), the espalier-testing SKILL, agent.md, engineering-structure.md from the templates (skip-with-record if customised; no-op where the v0.25 text is already present)"
  log "DRY RUN — would append grep-only-paths to espalier/.espalier-config and '*.pre-v0.*.bak' to .gitignore (grep-guarded)"
  log "DRY RUN — would print the report-only lines (req_shape_check per IN_PROGRESS change; rules contract-drift totals) — never edits a rule or a requirement"
  exit 0
fi

if [ "$SKIP_PROMPT" != yes ]; then
  echo "This migration will:"
  echo "  - refresh pipeline.md, the espalier router + its stages/ files, the agents' modes/ files, the lane SKILLs, .scout-prompts.md, drift-helpers.sh, maprun.py, espalier-stats.sh from templates (backups: <file>.pre-v0.25.bak)"
  echo "  - insert the v0.25 sections into harness-coder.md / harness-reviewer.md / harness-security.md and replace their mode-only sections with pointers at modes/; the testing SKILL, agent.md, engineering-structure.md (customised files skipped, never mangled)"
  echo "  - append grep-only-paths to espalier/.espalier-config and the backup pattern to .gitignore"
  echo "  - print report-only lines (requirement shape, rules contract drift) — it edits no rule and no requirement"
  printf "Proceed? [y/N] "
  read -r ans
  case "$ans" in y|Y|yes|YES) ;; *) log "aborted."; exit 0 ;; esac
fi

backup_once() { [ -f "$1.pre-v0.25.bak" ] || cp "$1" "$1.pre-v0.25.bak"; }

# --- 1. Pure-copy refresh (backup-on-diff) -----------------------------------
refresh() {  # $1 = template path, $2 = installed path
  [ -f "$1" ] || die "template missing: $1"
  if [ -f "$2" ] && ! cmp -s "$1" "$2"; then
    cp "$2" "$2.pre-v0.25.bak"
  fi
  cp "$1" "$2"
  log "refreshed $2"
}
grep -qF "$PIPE_MARK"   espalier/pipeline.md 2>/dev/null                        || refresh "$TPL/pipeline.md"                    espalier/pipeline.md
grep -qF "$ROUTER_MARK" espalier/skills/espalier/SKILL.md 2>/dev/null           || refresh "$TPL/skills/espalier.md"             espalier/skills/espalier/SKILL.md
mkdir -p espalier/skills/espalier/stages espalier/agents/modes
for _f in $STAGE_FILES; do
  cmp -s "$TPL/skills/espalier-stages/$_f.md" "espalier/skills/espalier/stages/$_f.md" 2>/dev/null \
    || refresh "$TPL/skills/espalier-stages/$_f.md" "espalier/skills/espalier/stages/$_f.md"
done
for _f in $MODE_FILES; do
  cmp -s "$TPL/agents/modes/$_f.md" "espalier/agents/modes/$_f.md" 2>/dev/null \
    || refresh "$TPL/agents/modes/$_f.md" "espalier/agents/modes/$_f.md"
done
grep -qF "$LANE_MARK"   espalier/skills/espalier-fix/SKILL.md 2>/dev/null       || refresh "$TPL/skills/espalier-fix.md"         espalier/skills/espalier-fix/SKILL.md
grep -qF "$REQ_MARK"    espalier/skills/espalier-requirements/SKILL.md 2>/dev/null || refresh "$TPL/skills/espalier-requirements.md" espalier/skills/espalier-requirements/SKILL.md
grep -qF "$GRILL_MARK"  espalier/skills/espalier-grill/SKILL.md 2>/dev/null     || refresh "$TPL/skills/espalier-grill.md"       espalier/skills/espalier-grill/SKILL.md
grep -qF "$MAP_MARK"    espalier/skills/espalier-map/SKILL.md 2>/dev/null       || refresh "$TPL/skills/espalier-map.md"         espalier/skills/espalier-map/SKILL.md
grep -qF "$AUDIT_MARK"  espalier/skills/espalier-audit/SKILL.md 2>/dev/null     || refresh "$TPL/skills/espalier-audit.md"       espalier/skills/espalier-audit/SKILL.md
grep -qF "$NOTES_MARK"  espalier/skills/espalier-ask/SKILL.md 2>/dev/null       || refresh "$TPL/skills/espalier-ask.md"         espalier/skills/espalier-ask/SKILL.md
grep -qF "$NOTES_MARK"  espalier/skills/espalier-simplify/SKILL.md 2>/dev/null  || refresh "$TPL/skills/espalier-simplify.md"    espalier/skills/espalier-simplify/SKILL.md
grep -qF "$PRUNE_MARK"  espalier/skills/espalier-prune/SKILL.md 2>/dev/null     || refresh "$TPL/skills/espalier-prune.md"       espalier/skills/espalier-prune/SKILL.md
grep -qF "$DOCTOR_MARK" espalier/skills/espalier-doctor/SKILL.md 2>/dev/null    || refresh "$TPL/skills/espalier-doctor.md"      espalier/skills/espalier-doctor/SKILL.md
grep -qF "$SCOUT_MARK"  espalier/.scout-prompts.md 2>/dev/null                  || refresh "$TPL/scout-prompts.md"               espalier/.scout-prompts.md
grep -qF "$HELPERS_MARK" espalier/hooks/drift-helpers.sh 2>/dev/null            || refresh "$HTPL/drift-helpers.sh"              espalier/hooks/drift-helpers.sh
if ! grep -qF "$MAPRUN_MARK" espalier/hooks/maprun.py 2>/dev/null; then
  refresh "$HTPL/maprun.py" espalier/hooks/maprun.py
  chmod +x espalier/hooks/maprun.py 2>/dev/null || true
fi
if ! grep -qF "$STATS_MARK" espalier/hooks/espalier-stats.sh 2>/dev/null; then
  refresh "$HTPL/espalier-stats.sh" espalier/hooks/espalier-stats.sh
  chmod +x espalier/hooks/espalier-stats.sh 2>/dev/null || true
fi

# --- 2. Anchored edits (text extracted from the templates) -------------------
BLK=$(mktemp -t v0250blk.XXXX)
trap 'rm -f "$BLK"' EXIT
NOBAK=no

record_skip() {  # $1 = label, $2 = file, $3 = anchor description
  log "WARN: $2 is customised past the stock shape ($3 not found) — skipped."
  log "      Manual step: port the v0.25.0 '$1' text from the template yourself."
  grep -qF "v0.25.0-$1" "$SKIPFILE" 2>/dev/null \
    || echo "v0.25.0-$1: customised, manual port needed ($2)" >> "$SKIPFILE"
}

# extract_block TEMPLATE START END — lines from the first one containing START
# through the first later one containing END, inclusive, into $BLK. Dies on an
# empty result OR when END never matched (an unbounded block would swallow
# every later section).
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

# span_present FILE START END — true when the file has a line containing START
# and, on or after it, a line containing END.
span_present() {
  awk -v start="$2" -v end="$3" '
    !insp && index($0, start) { insp=1 }
    insp && index($0, end) { found=1; exit }
    END { exit !found }
  ' "$1" 2>/dev/null
}

# insert_before FILE ANCHOR — $BLK plus one blank line go right before the
# first line containing ANCHOR.
insert_before() {
  local f="$1" anchor="$2" tmp="$1.v0250tmp"
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
  local f="$1" anchor="$2" tmp="$1.v0250tmp"
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

# swap_block FILE START END — the span from the first line containing START
# through the first later line containing END (inclusive) becomes $BLK. The
# reword primitive: a v0.24 sentence is replaced by its v0.25 text.
swap_block() {
  local f="$1" start="$2" end="$3" tmp="$1.v0250tmp"
  [ "$NOBAK" = yes ] || backup_once "$f"
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

# swap_step LABEL FILE MARKER TPL_START TPL_END OLD_START OLD_END [OLD_START2 OLD_END2]
# — no-op when MARKER is present; otherwise swap the OLD span (stock v0.24
# anchors, then an alternate pair for installs that hand-applied part of the
# change) with the template block; skip-with-record when neither span exists.
swap_step() {
  local label="$1" f="$2" marker="$3" ts="$4" te="$5" os="$6" oe="$7" os2="${8:-}" oe2="${9:-}"
  handled "$marker" "$f" "$label" && return 0
  if span_present "$f" "$os" "$oe"; then
    extract_block "$TPL/$(_tpl_of "$f")" "$ts" "$te"
    swap_block "$f" "$os" "$oe"
    log "applied $label ($f)"
  elif [ -n "$os2" ] && span_present "$f" "$os2" "$oe2"; then
    extract_block "$TPL/$(_tpl_of "$f")" "$ts" "$te"
    swap_block "$f" "$os2" "$oe2"
    log "applied $label ($f, alternate anchor)"
  else
    record_skip "$label" "$f" "the '$os' … '$oe' span"
  fi
}
_tpl_of() {  # installed path → template path (relative to $TPL)
  case "$1" in
    espalier/agents/harness-coder.md)    echo agents/harness-coder.md ;;
    espalier/agents/harness-reviewer.md) echo agents/harness-reviewer.md ;;
    espalier/agents/harness-security.md) echo agents/harness-security.md ;;
    espalier/skills/espalier-testing/SKILL.md) echo skills/espalier-testing.md ;;
    espalier/agent.md)                   echo agent.md ;;
    *) die "no template mapping for $1" ;;
  esac
}
# insert_step LABEL FILE MARKER TPL_START TPL_END before|after ANCHOR
insert_step() {
  local label="$1" f="$2" marker="$3" ts="$4" te="$5" where="$6" anchor="$7"
  handled "$marker" "$f" "$label" && return 0
  if grep -qF -- "$anchor" "$f" 2>/dev/null; then
    extract_block "$TPL/$(_tpl_of "$f")" "$ts" "$te"
    if [ "$where" = before ]; then insert_before "$f" "$anchor"; else insert_after "$f" "$anchor"; fi
    log "applied $label ($f)"
  else
    record_skip "$label" "$f" "the '$anchor' anchor"
  fi
}

# 2a. coder
if [ -f "$CODER" ]; then
  insert_step coder-handoff "$CODER" "$CODER_HANDOFF" "$CODER_HANDOFF" "$CODER_HANDOFF_END" before '## Editing Discipline'
  insert_step coder-docs "$CODER" "$CODER_DOCS" "$CODER_DOCS" "$CODER_DOCS_END" before '## Change Impact Analysis (do this BEFORE writing code)'
  # the three reading-discipline lines follow step 7 of Before Writing ANY Code
  insert_step coder-read-once "$CODER" "$CODER_READ" "$CODER_READ" "$CODER_READ_END" after 'change — after you understand it, never instead of understanding it.'
  # report shape: the Coding Report block's field lines are re-rendered from the template
  swap_step coder-report "$CODER" "$CODER_REPORT" \
    '## Coding Report' '- Notes: {anything the reviewer should pay attention to}' \
    '## Coding Report' '- Notes: {anything the reviewer should pay attention to}'
  insert_step coder-report-prose "$CODER" "$CODER_PROSE" "$CODER_PROSE" "$CODER_PROSE_END" before '### Test Scope Signal (fix lane)'
  swap_step coder-reword-security "$CODER" "$CODER_SEC" \
    'The Stage 4 security audit is a backstop, not permission to trust the client. Apply' 'the backend is the trust boundary.**' \
    'The Stage 4 security audit is a backstop, not permission to trust the client. Read' 'the backend is the trust boundary.**'
  swap_step coder-reword-production "$CODER" "$CODER_PROD" \
    'Apply `espalier/rules/production-standards.md` (auto-loaded' 'write them in the first place:' \
    'Read `espalier/rules/production-standards.md` and apply its seeds' 'write them in the first place:'
  swap_step coder-contract-read "$CODER" "$CODER_CONTRACT" \
    'When you run in CONTRACT PHASE mode, read the contract in' 'For EACH field listed, write the negative test named in its' \
    'When you run in CONTRACT PHASE mode, read the `## Security-Sensitive Fields`' 'For EACH field listed, write the negative test named in its'
  swap_step coder-contract-entry "$CODER" "$CODER_ENTRY" \
    '- **`CONTRACT PHASE:`** — the panel has passed. Read `security-contract.md`' 'the earlier report is in coding-log/. (Under' \
    "- **\`CONTRACT PHASE:\`** — the panel has passed. Read security-record.md's" 'else. Append your test report to coding-report.md normally. (Under'
fi

# 2b. reviewer
if [ -f "$REV" ]; then
  swap_step reviewer-before "$REV" "$REV_BEFORE" \
    '1. Read `espalier/skills/espalier-review/SKILL.md` for the review checklist' 'current coding-report.md cites it or a finding needs the history.' \
    '1. Read `espalier/skills/espalier-review/SKILL.md` for the review checklist' 'tiers (the Production-Readiness Review below enforces them)' \
    '1. Read `espalier/skills/espalier-review/SKILL.md` for the review checklist' 'present (other platforms) — never re-read what is already loaded'
  swap_step reviewer-spec "$REV" "$REV_SPEC" \
    '   - The layer spec (`espalier/skills/espalier-coding/specs/{layer}.md`) —' 'itself, when there is one, is filed at its normal severity as today.' \
    '   - The layer spec (`espalier/skills/espalier-coding/specs/{layer}.md`)' '   - The layer spec (`espalier/skills/espalier-coding/specs/{layer}.md`)'
  insert_step reviewer-advisory-rows "$REV" "$REV_MIN" "$REV_MIN" "$REV_MIN_END" before '**The one P1 — a NEW dependency:**'
  # the docs: bullet continues the tag list (no blank line): it goes right
  # after the comments: bullet's last line, which is exactly "  convention."
  insert_step reviewer-docs-tag "$REV" "$REV_DOCS" "$REV_DOCS" "$REV_DOCS_END" after '  convention.'
fi

# 2c. security
if [ -f "$SEC" ]; then
  swap_step security-before "$SEC" "$SEC_BEFORE" \
    '1. `espalier/rules/security-standards.md` — the trust boundary, the sensitive' 'the code before it clears a finding, as with the pack.' \
    '1. Read `espalier/rules/security-standards.md` — the trust boundary, the sensitive' '   verdict for staleness.' \
    '1. `espalier/rules/security-standards.md` — the trust boundary, the sensitive' '   verdict for staleness.'
fi

# 2c'. the seven mode-only sections → heading + one-line pointer (the text
# now lives in espalier/agents/modes/, read when the prompt names the mode).
# A customised body missing a section's anchors keeps the section inline
# (double text, no functional loss) and is recorded.
if [ -f "$CODER" ]; then
  swap_step coder-mode-fix-round "$CODER" "$CODER_FIXMODE" \
    '## Fix Rounds: Fix the Class, Not the Instance' 'lives there in full and applies only on a fix round.' \
    '## Fix Rounds: Fix the Class, Not the Instance' 'an instance-only fix; the reviewer files it as a P1 and the round repeats.'
  swap_step coder-mode-simplification "$CODER" "$CODER_SIMPMODE" \
    '## Simplification Changes: Retire the Whole Obligation' 'there in full and apply only on a simplification change.' \
    '## Simplification Changes: Retire the Whole Obligation' 'it and the cut returns to the survey page.'
fi
if [ -f "$REV" ]; then
  swap_step reviewer-mode-re-review "$REV" "$REV_RRMODE" \
    '## Re-review Rounds (you may be re-spawned on a fix)' 'there in full and apply only from round 2 on.' \
    '## Re-review Rounds (you may be re-spawned on a fix)' 'the new code as fresh code.'
  swap_step reviewer-mode-simplification "$REV" "$REV_SIMPMODE" \
    '## Simplification Review (when the change retires surface)' 'Run it after step 5 and before the Minimalism Review.' \
    '## Simplification Review (when the change retires surface)' 'rules or specs is ever residue.'
  swap_step reviewer-mode-abuse-coverage "$REV" "$REV_ABUSEMODE" \
    '## Security Abuse-Test Coverage (contract delta review — serial: Stage 6)' 'there in full and apply only on that review.' \
    '## Security Abuse-Test Coverage (contract delta review — serial: Stage 6)' 'This is enforced coverage, not a suggestion.'
fi
if [ -f "$SEC" ]; then
  swap_step security-mode-re-review "$SEC" "$SEC_RRMODE" \
    '## Re-review Rounds (you may be re-spawned on a fix)' 'live there in full and apply only from round 2 on.' \
    '## Re-review Rounds (you may be re-spawned on a fix)' 'new code as fresh code.'
  swap_step security-mode-repo-audit "$SEC" "$SEC_AUDITMODE" \
    '## Repo-Audit Mode (spawned by /espalier-audit)' 'that mode.' \
    '## Repo-Audit Mode (spawned by /espalier-audit)' 'correct, complete answer for a well-controlled batch.'
fi

# 2d. testing SKILL (LLM-written at init; anchored, never pure-copied)
if [ -f "$TESTSK" ]; then
  swap_step testing-contract-read "$TESTSK" "$TEST_MARK" \
    'When the change has an `espalier/changes/{type}/{slug}/security-contract.md` —' 'write a negative test for EACH field.' \
    'When the change has an `espalier/changes/{type}/{slug}/security-record.md` with a' 'write a negative test for EACH field.'
fi

# 2e. agent.md — the Config row is re-rendered from the template (one line).
if [ -f "$AGENT" ] && ! handled "$AGENT_MARK" "$AGENT" agent-config-row; then
  ANCH='| Config | espalier/.espalier-config |'
  if grep -qF -- "$ANCH" "$AGENT" 2>/dev/null; then
    grep -F -- "$ANCH" "$TPL/agent.md" > "$BLK"
    [ -s "$BLK" ] || die "template row '$ANCH' not found in $TPL/agent.md — plugin templates drifted."
    swap_block "$AGENT" "$ANCH" "$ANCH"
    log "applied agent-config-row ($AGENT)"
  else
    record_skip agent-config-row "$AGENT" "the Config row ('| Config | espalier/.espalier-config |')"
  fi
fi

# 2e'. agent.md — the Pipeline row names the stage files.
if [ -f "$AGENT" ] && ! handled "$AGENT_PIPE_MARK" "$AGENT" agent-pipeline-row; then
  ANCH='| Pipeline | espalier/pipeline.md |'
  if grep -qF -- "$ANCH" "$AGENT" 2>/dev/null; then
    grep -F -- "$ANCH" "$TPL/agent.md" > "$BLK"
    [ -s "$BLK" ] || die "template row '$ANCH' not found in $TPL/agent.md — plugin templates drifted."
    swap_block "$AGENT" "$ANCH" "$ANCH"
    log "applied agent-pipeline-row ($AGENT)"
  else
    record_skip agent-pipeline-row "$AGENT" "the Pipeline row ('| Pipeline | espalier/pipeline.md |')"
  fi
fi

# 2f. engineering-structure.md — the Not Precedent anchor is appended (empty
# list); skipped when the token is already present.
if [ -f "$RULE" ] && ! grep -qF "$NP_TOKEN" "$RULE" 2>/dev/null; then
  extract_block "$TPL/rules/engineering-structure.md" '## Not Precedent' 'evidence file:line}'
  backup_once "$RULE"
  { printf '\n'; cat "$BLK"; } >> "$RULE"
  log "appended ## Not Precedent anchor to $RULE (empty list — /espalier-prune refreshes it from scout 1.2)"
fi

# --- 3. Config: grep-only-paths (grep-guarded, comment included) -------------
if ! grep -q "^$CFG_KEY:" espalier/.espalier-config 2>/dev/null; then
  if [ -s espalier/.espalier-config ] && [ -n "$(tail -c1 espalier/.espalier-config)" ]; then
    printf '\n' >> espalier/.espalier-config
  fi
  cat >> espalier/.espalier-config <<'CFG'

# Grep-only files (v0.25): space-separated path substrings. Tracked files that
# match are listed in every context pack as "Grep-only" — agents search them
# for a symbol, never Read them whole. Patterns and sizes, no threshold.
grep-only-paths: __generated__/ schema.graphql schema.prisma
CFG
  log "appended grep-only-paths to espalier/.espalier-config"
fi

# --- 4. .gitignore: migration backups --------------------------------------
if ! grep -qxF '*.pre-v0.*.bak' .gitignore 2>/dev/null; then
  if [ -s .gitignore ] && [ -n "$(tail -c1 .gitignore)" ]; then printf '\n' >> .gitignore; fi
  printf '# espalier migration backups (one per file per migration)\n*.pre-v0.*.bak\n' >> .gitignore
  log "added '*.pre-v0.*.bak' to .gitignore (existing tracked backups are left alone)"
fi

# --- 5. Report, do not act ---------------------------------------------------
if [ -f espalier/hooks/drift-helpers.sh ]; then
  . espalier/hooks/drift-helpers.sh
  for sf in espalier/changes/*/*/pipeline-state.md; do
    [ -f "$sf" ] || continue
    grep -q '^- Status: IN_PROGRESS' "$sf" 2>/dev/null || continue
    d=$(dirname "$sf")
    out=$(req_shape_check "$d" 2>/dev/null)
    [ -n "$out" ] && log "requirement shape ($d): $(printf '%s' "$out" | tr '\n' ';')"
  done
  N=0; M=0
  for f in espalier/rules/*.md; do
    [ -f "$f" ] || continue
    n=$(contract_drift_lines "$f" 2>/dev/null | grep -c .)
    [ "${n:-0}" -gt 0 ] && { N=$((N + n)); M=$((M + 1)); }
  done
  log "rules contract drift: $N line(s) in $M rule file(s) — run /espalier-prune when you choose (interactive, per-file gate, Removed-rules ledger). This migration edits no rule."
fi

# --- Verify ------------------------------------------------------------------
grep -qF "$HELPERS_MARK" espalier/hooks/drift-helpers.sh  || die "post-migration verification failed: drift-helpers.sh lacks the context helpers"
grep -qF "$ROUTER_MARK"  espalier/skills/espalier/SKILL.md     || die "post-migration verification failed: espalier SKILL is not the router (lacks '$ROUTER_MARK')"
for _f in $STAGE_FILES; do [ -f "espalier/skills/espalier/stages/$_f.md" ] || die "post-migration verification failed: stages/$_f.md missing"; done
for _f in $MODE_FILES;  do [ -f "espalier/agents/modes/$_f.md" ]          || die "post-migration verification failed: modes/$_f.md missing"; done
grep -qF "$LANE_MARK"    espalier/skills/espalier-fix/SKILL.md || die "post-migration verification failed: espalier-fix SKILL lacks '$LANE_MARK'"
grep -qF "$REQ_MARK"     espalier/skills/espalier-requirements/SKILL.md || die "post-migration verification failed: espalier-requirements SKILL lacks '$REQ_MARK'"
grep -qF "$STATS_MARK"   espalier/hooks/espalier-stats.sh || die "post-migration verification failed: espalier-stats.sh lacks '$STATS_MARK'"
grep -qF "$MAPRUN_MARK"  espalier/hooks/maprun.py         || die "post-migration verification failed: maprun.py lacks '$MAPRUN_MARK'"
grep -q  "^$CFG_KEY:"    espalier/.espalier-config        || die "post-migration verification failed: .espalier-config lacks $CFG_KEY"
[ -f "$CODER" ] && { handled "$CODER_HANDOFF" "$CODER" coder-handoff || die "post-migration verification failed: coder lacks the Handoff section"; }
[ -f "$REV" ]   && { handled "$REV_SPEC" "$REV" reviewer-spec       || die "post-migration verification failed: reviewer lacks '$REV_SPEC'"; }
[ -f "$SEC" ]   && { handled "$SEC_BEFORE" "$SEC" security-before   || die "post-migration verification failed: security agent lacks the Before Auditing lines"; }
if grep -q 'v0.25.0-' "$SKIPFILE" 2>/dev/null; then
  log "done with skips — see $SKIPFILE (each is a manual port from the template; the file works as before until then)."
fi

log "done. v0.25.0 applied — backups at <file>.pre-v0.25.bak (gitignored from now on)."
log "Every gate and cap is unchanged. New: coders hand off at clean points (- HANDOFF: true), the"
log "orchestrator archives prior reports to coding-log/, offers a fresh session at Stage 2 / Stage 4"
log "boundaries, runs the exit gate as one call (exit_gate), and the pack names Grep-only files and"
log "scoped docs. The espalier skill is a router (stages/ read at stage entry; pipeline.md is the"
log "contract) and the agents' mode text lives in espalier/agents/modes/ (read when the prompt names it)."
log "Run 'bash espalier/hooks/espalier-stats.sh' for the new spawn-shape rows."
exit 0
