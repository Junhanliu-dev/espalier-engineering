#!/bin/bash
# Migrate a v0.26.0 Espalier install to v0.27.0.
#
# v0.27.0 is the unknowns release: the pipeline gains a channel for what the
# territory (the code) teaches during and after implementation, without
# unfreezing the contract. Contract-equal to v0.26.0: every gate, rubric,
# sentinel, round cap, and escalation path is unchanged; the coder never
# edits requirements.md; the human resolves every criterion the code
# contradicts. NOTHING here sets a budget or refuses on size.
#
#   - Pure-copy refresh (backup-on-diff → <file>.pre-v0.27.bak):
#     espalier/pipeline.md; the espalier SKILL (router) plus its five stage
#     files under espalier/skills/espalier/stages/; the espalier-fix,
#     espalier-grill and espalier-requirements SKILLs;
#     espalier/hooks/{drift-helpers.sh, espalier-stats.sh}.
#   - Anchored edits, text EXTRACTED from the plugin templates at run time so
#     a migrated install is byte-identical to a fresh one in those sections:
#     harness-coder.md (Territory vs Contract: Deviations — the `###
#     Deviations` block, the `- BLOCKED-ON-REQUIREMENT:` sentinel, the
#     References line; the report-hygiene list; the You Must NOT line);
#     harness-reviewer.md (the Deviation Review section, its Review Process
#     step, its You Must NOT line); harness-security.md (Audit Process step
#     5). A customised file missing its anchor is skipped with a record in
#     espalier/.migrations-skipped, never mangled.
#   No config key, no new instruction-file line, no hooks, no symlinks.
#
# Usage:
#   bash migrate-v0.26.0-to-v0.27.0.sh [--dry-run] [--yes] [--plugin-dir=<path>]

set -u

DRY_RUN=no
SKIP_PROMPT=no
PLUGIN_DIR="${ESPALIER_PLUGIN_DIR:-}"

for arg in "$@"; do
  case "$arg" in
    --dry-run)       DRY_RUN=yes ;;
    --yes)           SKIP_PROMPT=yes ;;
    --plugin-dir=*)  PLUGIN_DIR="${arg#--plugin-dir=}" ;;
    -h|--help)       sed -n '2,29p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown flag: $arg (use --help)" >&2; exit 2 ;;
  esac
done

log() { echo "[migrate v0.26.0→v0.27.0] $*"; }
die() { echo "[migrate v0.26.0→v0.27.0] ERROR: $*" >&2; exit 1; }

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

# --- v0.27.0 markers (also the idempotency check) ----------------------------
HELPERS_MARK='delivery_brief()'
STATS_MARK='changes-with-logged-deviations'
PIPE_MARK='BLOCKED-ON-REQUIREMENT'
ROUTER_MARK='delivery_brief'
LANE_MARK='BLOCKED-ON-REQUIREMENT'
GRILL_MARK='Step 1.6'
REQ_MARK='## References'
STAGE_FILES='1-2-requirements 3-coding 4-panel 5-6-contract 7-10-delivery'
# coder
CODER_TERR='## Territory vs Contract: Deviations'
CODER_TERR_END='entry, not a licence.'
CODER_HYG='`### Retired Surface`, `### Test Scope Signal`, `### Deviations` — is'
CODER_HYG_START='and a block the panel re-verifies each round — `### Class Sweep`,'
CODER_HYG_END='report it came from)'          # the v0.27 template's (reflowed) last line
CODER_HYG_OLD_END='report when it still applies (cite the archived report it came from)'
CODER_MUSTNOT='- Edit requirements.md, or build past a criterion the code contradicts'
CODER_MUSTNOT_END='sentinel (see Territory vs Contract)'
CODER_MUSTNOT_ANCHOR='- Land the whole task as one commit at the end,'
# reviewer
REV_STEP='9. Run the **Deviation Review** (see section below)'
REV_STEP_START='8. Contract delta-review rounds only (and serial Stage 6): run the'
REV_STEP_OLD_END='9. Produce findings in the required format'
REV_STEP_END='10. Produce findings in the required format'
REV_SECTION='## Deviation Review (every round)'
REV_SECTION_END='says otherwise.'
REV_SECTION_ANCHOR='## Convention Drift Reporting'
REV_MUSTNOT='- Accept a departure from an acceptance criterion that is unlogged or not'
REV_MUSTNOT_END='conservative (run the Deviation Review), or resolve one yourself'
REV_MUSTNOT_ANCHOR='- File a minimalism finding above P2 (sole exception: the new-dependency P1),'
# security
SEC_STEP='5. **Read `### Deviations` in coding-report.md.**'
SEC_STEP_END='there.'
SEC_STEP_ANCHOR='## Output Format'

grep -qF "$HELPERS_MARK" "$HTPL/drift-helpers.sh" 2>/dev/null \
  && grep -qF "$CODER_TERR" "$TPL/agents/harness-coder.md" 2>/dev/null \
  && grep -qF "$REV_SECTION" "$TPL/agents/harness-reviewer.md" 2>/dev/null \
  && grep -qF "$SEC_STEP" "$TPL/agents/harness-security.md" 2>/dev/null \
  && grep -qF "$ROUTER_MARK" "$TPL/skills/espalier.md" 2>/dev/null \
  && grep -qF "$PIPE_MARK" "$TPL/skills/espalier-stages/3-coding.md" 2>/dev/null \
  && grep -qF "$LANE_MARK" "$TPL/skills/espalier-fix.md" 2>/dev/null \
  && grep -qF "$GRILL_MARK" "$TPL/skills/espalier-grill.md" 2>/dev/null \
  && grep -qF "$REQ_MARK" "$TPL/skills/espalier-requirements.md" 2>/dev/null \
  && grep -qF "$STATS_MARK" "$HTPL/espalier-stats.sh" 2>/dev/null \
  || die "plugin dir $PLUGIN_DIR is not v0.27.0 (templates lack the unknowns channel). Update the plugin first."

handled() {  # $1 = marker, $2 = file, $3 = skip label
  grep -qF -- "$1" "$2" 2>/dev/null || grep -qF "v0.27.0-$3" "$SKIPFILE" 2>/dev/null
}

missing=""
mark() { missing="$missing
  - $1"; }
grep -qF "$HELPERS_MARK" espalier/hooks/drift-helpers.sh  2>/dev/null || mark "drift-helpers.sh unknowns helpers (deviations_list / open_question_append / delivery_brief; req_shape_check knows References)"
grep -qF "$STATS_MARK"   espalier/hooks/espalier-stats.sh 2>/dev/null || mark "espalier-stats.sh deviations row"
grep -qF "$PIPE_MARK"    espalier/pipeline.md             2>/dev/null || mark "pipeline.md (BLOCKED sentinel, Deviation Review, delivery brief)"
grep -qF "$ROUTER_MARK"  espalier/skills/espalier/SKILL.md 2>/dev/null || mark "espalier SKILL router (territory notes, delivery brief)"
for _f in $STAGE_FILES; do cmp -s "$TPL/skills/espalier-stages/$_f.md" "espalier/skills/espalier/stages/$_f.md" 2>/dev/null || mark "espalier/skills/espalier/stages/$_f.md (stage procedure)"; done
grep -qF "$LANE_MARK"    espalier/skills/espalier-fix/SKILL.md 2>/dev/null || mark "espalier-fix SKILL (BLOCKED sentinel, deviations surfaced, delivery brief)"
grep -qF "$GRILL_MARK"   espalier/skills/espalier-grill/SKILL.md 2>/dev/null || mark "espalier-grill SKILL (familiarity, Step 1.6 requester brief, shown candidates, approach undecided)"
grep -qF "$REQ_MARK"     espalier/skills/espalier-requirements/SKILL.md 2>/dev/null || mark "espalier-requirements SKILL (References section, familiarity pass-through)"
CODER=espalier/agents/harness-coder.md
REV=espalier/agents/harness-reviewer.md
SEC=espalier/agents/harness-security.md
handled "$CODER_TERR"    "$CODER" coder-territory      || mark "coder Territory vs Contract section (Deviations block, BLOCKED sentinel, References)"
handled "$CODER_HYG"     "$CODER" coder-hygiene-deviations || mark "coder report-hygiene list — ### Deviations carried forward"
handled "$CODER_MUSTNOT" "$CODER" coder-must-not-contract || mark "coder You Must NOT — never edit requirements.md"
handled "$REV_STEP"      "$REV" reviewer-deviation-step  || mark "reviewer Review Process — Deviation Review step"
handled "$REV_SECTION"   "$REV" reviewer-deviation-review || mark "reviewer Deviation Review section"
handled "$REV_MUSTNOT"   "$REV" reviewer-must-not-deviation || mark "reviewer You Must NOT — unlogged / non-conservative departure"
handled "$SEC_STEP"      "$SEC" security-deviation-step || mark "security Audit Process step 5 — deviations on a trust boundary"

if [ -z "$missing" ]; then
  log "already at v0.27.0 (every marker present). Nothing to do."
  exit 0
fi

if [ "$DRY_RUN" = yes ]; then
  log "DRY RUN — missing markers:$missing"
  log "DRY RUN — would refresh up to 12 pure-copy files (pipeline.md, the espalier router + 5 stage files, the espalier-fix / espalier-grill / espalier-requirements SKILLs, drift-helpers.sh, espalier-stats.sh; backup-on-diff → .pre-v0.27.bak)"
  log "DRY RUN — would anchored-edit harness-coder.md, harness-reviewer.md and harness-security.md from the templates (skip-with-record if customised; no-op where the v0.27 text is already present)"
  exit 0
fi

if [ "$SKIP_PROMPT" != yes ]; then
  echo "This migration will:"
  echo "  - refresh pipeline.md, the espalier router + its stages/ files, the espalier-fix / grill / requirements SKILLs, drift-helpers.sh, espalier-stats.sh from templates (backups: <file>.pre-v0.27.bak)"
  echo "  - insert the v0.27 sections into harness-coder.md / harness-reviewer.md / harness-security.md (customised files skipped, never mangled)"
  printf "Proceed? [y/N] "
  read -r ans
  case "$ans" in y|Y|yes|YES) ;; *) log "aborted."; exit 0 ;; esac
fi

backup_once() { [ -f "$1.pre-v0.27.bak" ] || cp "$1" "$1.pre-v0.27.bak"; }

# --- 1. Pure-copy refresh (backup-on-diff) -----------------------------------
refresh() {  # $1 = template path, $2 = installed path
  [ -f "$1" ] || die "template missing: $1"
  if [ -f "$2" ] && ! cmp -s "$1" "$2"; then
    cp "$2" "$2.pre-v0.27.bak"
  fi
  cp "$1" "$2"
  log "refreshed $2"
}
grep -qF "$PIPE_MARK"   espalier/pipeline.md 2>/dev/null                  || refresh "$TPL/pipeline.md"              espalier/pipeline.md
grep -qF "$ROUTER_MARK" espalier/skills/espalier/SKILL.md 2>/dev/null     || refresh "$TPL/skills/espalier.md"       espalier/skills/espalier/SKILL.md
mkdir -p espalier/skills/espalier/stages
for _f in $STAGE_FILES; do
  cmp -s "$TPL/skills/espalier-stages/$_f.md" "espalier/skills/espalier/stages/$_f.md" 2>/dev/null \
    || refresh "$TPL/skills/espalier-stages/$_f.md" "espalier/skills/espalier/stages/$_f.md"
done
grep -qF "$LANE_MARK"    espalier/skills/espalier-fix/SKILL.md 2>/dev/null   || refresh "$TPL/skills/espalier-fix.md"   espalier/skills/espalier-fix/SKILL.md
grep -qF "$GRILL_MARK"   espalier/skills/espalier-grill/SKILL.md 2>/dev/null || refresh "$TPL/skills/espalier-grill.md" espalier/skills/espalier-grill/SKILL.md
grep -qF "$REQ_MARK"     espalier/skills/espalier-requirements/SKILL.md 2>/dev/null || refresh "$TPL/skills/espalier-requirements.md" espalier/skills/espalier-requirements/SKILL.md
grep -qF "$HELPERS_MARK" espalier/hooks/drift-helpers.sh 2>/dev/null       || refresh "$HTPL/drift-helpers.sh"        espalier/hooks/drift-helpers.sh
if ! grep -qF "$STATS_MARK" espalier/hooks/espalier-stats.sh 2>/dev/null; then
  refresh "$HTPL/espalier-stats.sh" espalier/hooks/espalier-stats.sh
  chmod +x espalier/hooks/espalier-stats.sh 2>/dev/null || true
fi

# --- 2. Anchored edits (text extracted from the templates) -------------------
BLK=$(mktemp -t v0270blk.XXXX)
trap 'rm -f "$BLK"' EXIT

record_skip() {  # $1 = label, $2 = file, $3 = anchor description
  log "WARN: $2 is customised past the stock shape ($3 not found) — skipped."
  log "      Manual step: port the v0.27.0 '$1' text from the template yourself."
  grep -qF "v0.27.0-$1" "$SKIPFILE" 2>/dev/null \
    || echo "v0.27.0-$1: customised, manual port needed ($2)" >> "$SKIPFILE"
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
  local f="$1" anchor="$2" tmp="$1.v0270tmp"
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

# insert_before_nogap FILE ANCHOR — $BLK goes right before the first line
# containing ANCHOR, with NO blank line (list items inside one list).
insert_before_nogap() {
  local f="$1" anchor="$2" tmp="$1.v0270tmp"
  backup_once "$f"
  cp "$f" "$tmp"
  awk -v blk="$BLK" -v anchor="$anchor" '
    !done && index($0, anchor) {
      while ((getline line < blk) > 0) print line
      close(blk); done=1
    }
    { print }
  ' "$tmp" > "$f"
  rm -f "$tmp"
}

# swap_block FILE START END — the span from the first line containing START
# through the first later line containing END (inclusive) becomes $BLK.
swap_block() {
  local f="$1" start="$2" end="$3" tmp="$1.v0270tmp"
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
    espalier/agents/harness-security.md) echo agents/harness-security.md ;;
    *) die "no template mapping for $1" ;;
  esac
}
# swap_step LABEL FILE MARKER TPL_START TPL_END OLD_START OLD_END — no-op when
# MARKER is present; otherwise swap the OLD span (stock v0.26 anchors) with
# the template block; skip-with-record when the span is absent.
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
# insert_step LABEL FILE MARKER TPL_START TPL_END ANCHOR [nogap] — $BLK before ANCHOR.
insert_step() {
  local label="$1" f="$2" marker="$3" ts="$4" te="$5" anchor="$6" gap="${7:-gap}"
  handled "$marker" "$f" "$label" && return 0
  if grep -qF -- "$anchor" "$f" 2>/dev/null; then
    extract_block "$TPL/$(_tpl_of "$f")" "$ts" "$te"
    if [ "$gap" = nogap ]; then insert_before_nogap "$f" "$anchor"; else insert_before "$f" "$anchor"; fi
    log "applied $label ($f)"
  else
    record_skip "$label" "$f" "the '$anchor' anchor"
  fi
}

# 2a. coder — the section lands before the Handoff section (after Verify in
# One Call on a v0.26 install — the same anchor #36 used, so the order
# matches a fresh template); the hygiene list and the You Must NOT line are
# in-place edits.
if [ -f "$CODER" ]; then
  insert_step coder-territory "$CODER" "$CODER_TERR" "$CODER_TERR" "$CODER_TERR_END" '## Handoff: Finish Bounded, Hand Off Clean'
  swap_step coder-hygiene-deviations "$CODER" "$CODER_HYG" \
    "$CODER_HYG_START" "$CODER_HYG_END" "$CODER_HYG_START" "$CODER_HYG_OLD_END"
  insert_step coder-must-not-contract "$CODER" "$CODER_MUSTNOT" "$CODER_MUSTNOT" "$CODER_MUSTNOT_END" "$CODER_MUSTNOT_ANCHOR" nogap
fi

# 2b. reviewer
if [ -f "$REV" ]; then
  swap_step reviewer-deviation-step "$REV" "$REV_STEP" \
    "$REV_STEP_START" "$REV_STEP_END" "$REV_STEP_START" "$REV_STEP_OLD_END"
  insert_step reviewer-deviation-review "$REV" "$REV_SECTION" "$REV_SECTION" "$REV_SECTION_END" "$REV_SECTION_ANCHOR"
  insert_step reviewer-must-not-deviation "$REV" "$REV_MUSTNOT" "$REV_MUSTNOT" "$REV_MUSTNOT_END" "$REV_MUSTNOT_ANCHOR" nogap
fi

# 2c. security — step 5 joins the Audit Process list right before the Output
# Format heading; the list's last line is step 4's, so the block is inserted
# with the blank line the heading already has above it.
if [ -f "$SEC" ]; then
  if ! handled "$SEC_STEP" "$SEC" security-deviation-step; then
    if grep -qF -- "$SEC_STEP_ANCHOR" "$SEC" && grep -qF 'it; missing control → the test is the reproduction.' "$SEC"; then
      extract_block "$TPL/agents/harness-security.md" "$SEC_STEP" "$SEC_STEP_END"
      # the block replaces the blank line between step 4 and the heading:
      # insert it right after step 4's last line, then the original blank
      # line still precedes the heading.
      backup_once "$SEC"
      awk -v blk="$BLK" '
        { print }
        !done && index($0, "it; missing control → the test is the reproduction.") {
          while ((getline line < blk) > 0) print line
          close(blk); done=1
        }
      ' "$SEC" > "$SEC.v0270tmp" && mv "$SEC.v0270tmp" "$SEC"
      log "applied security-deviation-step ($SEC)"
    else
      record_skip security-deviation-step "$SEC" "the 'missing control → the test is the reproduction.' line before '## Output Format'"
    fi
  fi
fi

# --- 3. .gitignore: migration backups (already there from #35 on most installs)
if ! grep -qxF '*.pre-v0.*.bak' .gitignore 2>/dev/null; then
  if [ -s .gitignore ] && [ -n "$(tail -c1 .gitignore)" ]; then printf '\n' >> .gitignore; fi
  printf '# espalier migration backups (one per file per migration)\n*.pre-v0.*.bak\n' >> .gitignore
  log "added '*.pre-v0.*.bak' to .gitignore"
fi

# --- Verify ------------------------------------------------------------------
grep -qF "$HELPERS_MARK" espalier/hooks/drift-helpers.sh  || die "post-migration verification failed: drift-helpers.sh lacks the unknowns helpers"
grep -qF "$ROUTER_MARK"  espalier/skills/espalier/SKILL.md     || die "post-migration verification failed: espalier SKILL lacks '$ROUTER_MARK'"
for _f in $STAGE_FILES; do cmp -s "$TPL/skills/espalier-stages/$_f.md" "espalier/skills/espalier/stages/$_f.md" || die "post-migration verification failed: stages/$_f.md differs from the template"; done
grep -qF "$LANE_MARK"    espalier/skills/espalier-fix/SKILL.md || die "post-migration verification failed: espalier-fix SKILL lacks '$LANE_MARK'"
grep -qF "$GRILL_MARK"   espalier/skills/espalier-grill/SKILL.md || die "post-migration verification failed: espalier-grill SKILL lacks '$GRILL_MARK'"
grep -qF "$STATS_MARK"   espalier/hooks/espalier-stats.sh || die "post-migration verification failed: espalier-stats.sh lacks '$STATS_MARK'"
[ -f "$CODER" ] && { handled "$CODER_TERR" "$CODER" coder-territory || die "post-migration verification failed: coder lacks Territory vs Contract"; }
[ -f "$REV" ]   && { handled "$REV_SECTION" "$REV" reviewer-deviation-review || die "post-migration verification failed: reviewer lacks the Deviation Review"; }
if grep -q 'v0.27.0-' "$SKIPFILE" 2>/dev/null; then
  log "done with skips — see $SKIPFILE (each is a manual port from the template; the file works as before until then)."
fi

log "done. v0.27.0 applied — backups at <file>.pre-v0.27.bak (gitignored)."
log "Every gate and cap is unchanged. New: the coder logs every departure from the approved"
log "contract under ### Deviations (conservative option, cited) or stops with"
log "- BLOCKED-ON-REQUIREMENT: for the human to resolve — it never edits requirements.md; the"
log "panel verifies the block ([deviation] P1; a relaxed control is the auditor's P0); the Stage 4"
log "PASS prints the deviations; Stage 10 presents delivery-brief.md (assembled from the records)"
log "and offers a quiz; the grill reads the map to an unfamiliar requester first (Step 1.6), shows"
log "its candidate builds at full tier, records an undecided approach instead of choosing; the"
log "approval gate leads with the decisions most likely to change; ## References carries the"
log "requester's model. Run 'bash espalier/hooks/espalier-stats.sh' for the deviations row."
exit 0
