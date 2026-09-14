#!/bin/bash
# Migrate a v0.25.x Espalier install to v0.26.0.
#
# v0.26.0 is the turn-economy release: the pipeline spends fewer agent
# turns and fewer spawns for the same gates. Contract-equal to v0.25.1:
# every gate, rubric, sentinel, round cap, and escalation path is unchanged;
# NOTHING here sets a budget or refuses on size.
#
#   - Pure-copy refresh (backup-on-diff → <file>.pre-v0.26.bak):
#     espalier/pipeline.md; the espalier SKILL (router) plus its five stage
#     files under espalier/skills/espalier/stages/; the five agent mode
#     files under espalier/agents/modes/; the espalier-fix SKILL;
#     espalier/hooks/{drift-helpers.sh, espalier-stats.sh}.
#   - Anchored edits, text EXTRACTED from the plugin templates at run time so
#     a migrated install is byte-identical to a fresh one in those sections:
#     harness-coder.md (Abuse test, now; the contract phase's GAPS list and
#     entry point; Verify in One Call; the You Must NOT pointer);
#     harness-security.md (the contract's `covered_by:` line and the
#     test-file scope sentence); the espalier-testing, espalier-security and
#     espalier-coding SKILLs (one sentence each); espalier/hooks/
#     pre-push-gate.sh (build ∥ lint by default — the two serial sections
#     become one concurrent section; the discovered commands are untouched).
#     A customised file missing its anchor is skipped with a record in
#     espalier/.migrations-skipped, never mangled.
#   No config key, no new instruction-file line, no hooks, no symlinks.
#
# Usage:
#   bash migrate-v0.25.1-to-v0.26.0.sh [--dry-run] [--yes] [--plugin-dir=<path>]

set -u

DRY_RUN=no
SKIP_PROMPT=no
PLUGIN_DIR="${ESPALIER_PLUGIN_DIR:-}"

for arg in "$@"; do
  case "$arg" in
    --dry-run)       DRY_RUN=yes ;;
    --yes)           SKIP_PROMPT=yes ;;
    --plugin-dir=*)  PLUGIN_DIR="${arg#--plugin-dir=}" ;;
    -h|--help)       sed -n '2,28p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown flag: $arg (use --help)" >&2; exit 2 ;;
  esac
done

log() { echo "[migrate v0.25.1→v0.26.0] $*"; }
die() { echo "[migrate v0.25.1→v0.26.0] ERROR: $*" >&2; exit 1; }

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

# --- v0.26.0 markers (also the idempotency check) ----------------------------
HELPERS_MARK='contract_gaps()'
STATS_MARK='contract phases: covered-at-Stage-3'
PIPE_MARK='contract_gaps'
ROUTER_MARK='Session-Boundary'
LANE_MARK='backlink_all'
STAGE_FILES='1-2-requirements 3-coding 4-panel 5-6-contract 7-10-delivery'
MODE_FILES='fix-round simplification re-review repo-audit stage6-abuse-coverage'
GATE_MARK='gate_build_lint_section'
# coder
CODER_ABUSE='**Abuse test, now.**'
CODER_ABUSE_END='`covered_by:` line names it).'
CODER_GAPS='"Listed" means the entries under your prompt'
CODER_GAPS_START='When you run in CONTRACT PHASE mode, read the contract in'
CODER_GAPS_END='`espalier/skills/espalier-security/SKILL.md` for the recipe.'
CODER_ENTRY='contract phase at all.)'
CODER_ENTRY_START='- **`CONTRACT PHASE:`** — the panel has passed. Read `security-contract.md`'
CODER_ENTRY_OLD_END='the code and reviewed with it.)'
CODER_VERIFY='## Verify in One Call'
CODER_VERIFY_END='orchestrator gates the combined tree.'
CODER_MUSTNOT='- Skip the build/lint check (see Verify in One Call)'
CODER_MUSTNOT_OLD='- Skip the build/lint check'
# security
SEC_SCOPE='`covered_by:` line: a test that performs'
SEC_SCOPE_START='Test files in the diff are in scope for secrets, live-endpoint calls, and'
SEC_SCOPE_END="changed code's handlers, consumers, and sinks) is unchanged."
SEC_CONTRACT='ROUTING fact, never a verdict'
SEC_CONTRACT_START='Emit one block per sensitive field in scope.'
SEC_CONTRACT_END='## Priority Rubric'
# skills (LLM-written at init; anchored, never pure-copied)
TEST_MARK='covered_by'
TEST_START='A happy-path test does NOT satisfy the contract. See'
TEST_END='a contracted field with no abuse test is a P0.'
SECSK_MARK='covered_by'
SECSK_START='6. **Emit the abuse-test contract**'
SECSK_OLD_END='6. **Emit the abuse-test contract** — one entry per sensitive field.'
SECSK_END='writes only the `none` entries.'
CODESK_MARK='Verify in One Call'
CODESK_START='files cannot drift. This skill adds the project-specific parts: the Layer'
CODESK_OLD_END='Specs map and the Implementation Checklist above.'
CODESK_END='a formatter in three.'

grep -qF "$HELPERS_MARK" "$HTPL/drift-helpers.sh" 2>/dev/null \
  && grep -qF "$CODER_ABUSE" "$TPL/agents/harness-coder.md" 2>/dev/null \
  && grep -qF "$CODER_VERIFY" "$TPL/agents/harness-coder.md" 2>/dev/null \
  && grep -qF "$SEC_CONTRACT" "$TPL/agents/harness-security.md" 2>/dev/null \
  && grep -qF "$ROUTER_MARK" "$TPL/skills/espalier.md" 2>/dev/null \
  && grep -qF "$PIPE_MARK" "$TPL/skills/espalier-stages/5-6-contract.md" 2>/dev/null \
  && grep -qF "$LANE_MARK" "$TPL/skills/espalier-fix.md" 2>/dev/null \
  && grep -qF "$STATS_MARK" "$HTPL/espalier-stats.sh" 2>/dev/null \
  && grep -qF "$GATE_MARK" "$HTPL/pre-push-gate.sh" 2>/dev/null \
  || die "plugin dir $PLUGIN_DIR is not v0.26.0 (templates lack the turn-economy helpers / contract coverage). Update the plugin first."

handled() {  # $1 = marker, $2 = file, $3 = skip label
  grep -qF -- "$1" "$2" 2>/dev/null || grep -qF "v0.26.0-$3" "$SKIPFILE" 2>/dev/null
}

missing=""
mark() { missing="$missing
  - $1"; }
grep -qF "$HELPERS_MARK" espalier/hooks/drift-helpers.sh  2>/dev/null || mark "drift-helpers.sh turn-economy helpers (contract_gaps / certificate_write / record_commits / drift_index / stage85_drift / backlink_all / regression_verify; exit_gate scoping + lint overlap)"
grep -qF "$STATS_MARK"   espalier/hooks/espalier-stats.sh 2>/dev/null || mark "espalier-stats.sh contract-phase + session-boundary rows"
grep -qF "$PIPE_MARK"    espalier/pipeline.md             2>/dev/null || mark "pipeline.md (contract coverage first, Session-Boundary, helper names)"
grep -qF "$ROUTER_MARK"  espalier/skills/espalier/SKILL.md 2>/dev/null || mark "espalier SKILL router (session-boundary preference)"
for _f in $STAGE_FILES; do cmp -s "$TPL/skills/espalier-stages/$_f.md" "espalier/skills/espalier/stages/$_f.md" 2>/dev/null || mark "espalier/skills/espalier/stages/$_f.md (stage procedure)"; done
for _f in $MODE_FILES;  do cmp -s "$TPL/agents/modes/$_f.md" "espalier/agents/modes/$_f.md" 2>/dev/null || mark "espalier/agents/modes/$_f.md (agent mode file)"; done
grep -qF "$LANE_MARK"    espalier/skills/espalier-fix/SKILL.md 2>/dev/null || mark "espalier-fix SKILL (regression_verify, record_commits + backlink_all, Session-Boundary, GAPS routing)"
CODER=espalier/agents/harness-coder.md
SEC=espalier/agents/harness-security.md
TESTSK=espalier/skills/espalier-testing/SKILL.md
SECSK=espalier/skills/espalier-security/SKILL.md
CODESK=espalier/skills/espalier-coding/SKILL.md
GATE=espalier/hooks/pre-push-gate.sh
handled "$CODER_ABUSE"   "$CODER" coder-abuse-now      || mark "coder Security-Aware Coding — Abuse test, now"
handled "$CODER_GAPS"    "$CODER" coder-contract-gaps  || mark "coder Writing Abuse Tests — the GAPS list"
handled "$CODER_ENTRY"   "$CODER" coder-contract-entry || mark "coder CONTRACT PHASE entry point — gap entries only"
handled "$CODER_VERIFY"  "$CODER" coder-verify-one-call || mark "coder Verify in One Call section"
handled "$CODER_MUSTNOT" "$CODER" coder-must-not-verify || mark "coder You Must NOT — build/lint pointer"
handled "$SEC_SCOPE"     "$SEC" security-test-scope    || mark "security test-file scope sentence (covered_by)"
handled "$SEC_CONTRACT"  "$SEC" security-contract-covered-by || mark "security Abuse-Test Contract — covered_by line"
if [ -f "$TESTSK" ]; then handled "$TEST_MARK"   "$TESTSK" testing-covered-by || mark "espalier-testing SKILL — Stage 3 abuse-test duty sentence"; fi
if [ -f "$SECSK" ];  then handled "$SECSK_MARK"  "$SECSK"  security-skill-covered-by || mark "espalier-security SKILL — contract step 6 covered_by"; fi
if [ -f "$CODESK" ]; then handled "$CODESK_MARK" "$CODESK" coding-skill-verify || mark "espalier-coding SKILL — Verify in One Call pointer"; fi
if [ -f "$GATE" ] && grep -q '^run_build()' "$GATE" 2>/dev/null; then
  handled "$GATE_MARK" "$GATE" gate-build-lint-overlap || mark "pre-push-gate.sh — build ∥ lint by default"
fi

if [ -z "$missing" ]; then
  log "already at v0.26.0 (every marker present). Nothing to do."
  exit 0
fi

if [ "$DRY_RUN" = yes ]; then
  log "DRY RUN — missing markers:$missing"
  log "DRY RUN — would refresh up to 14 pure-copy files (pipeline.md, the espalier router + 5 stage files, 5 agent mode files, the espalier-fix SKILL, drift-helpers.sh, espalier-stats.sh; backup-on-diff → .pre-v0.26.bak)"
  log "DRY RUN — would anchored-edit harness-coder.md, harness-security.md, the espalier-testing / espalier-security / espalier-coding SKILLs, and pre-push-gate.sh from the templates (skip-with-record if customised; no-op where the v0.26 text is already present)"
  exit 0
fi

if [ "$SKIP_PROMPT" != yes ]; then
  echo "This migration will:"
  echo "  - refresh pipeline.md, the espalier router + its stages/ files, the agents' modes/ files, the espalier-fix SKILL, drift-helpers.sh, espalier-stats.sh from templates (backups: <file>.pre-v0.26.bak)"
  echo "  - insert the v0.26 sections into harness-coder.md / harness-security.md, the testing / security / coding SKILLs, and make pre-push-gate.sh run build and lint concurrently (customised files skipped, never mangled; discovered commands untouched)"
  printf "Proceed? [y/N] "
  read -r ans
  case "$ans" in y|Y|yes|YES) ;; *) log "aborted."; exit 0 ;; esac
fi

backup_once() { [ -f "$1.pre-v0.26.bak" ] || cp "$1" "$1.pre-v0.26.bak"; }

# --- 1. Pure-copy refresh (backup-on-diff) -----------------------------------
refresh() {  # $1 = template path, $2 = installed path
  [ -f "$1" ] || die "template missing: $1"
  if [ -f "$2" ] && ! cmp -s "$1" "$2"; then
    cp "$2" "$2.pre-v0.26.bak"
  fi
  cp "$1" "$2"
  log "refreshed $2"
}
grep -qF "$PIPE_MARK"   espalier/pipeline.md 2>/dev/null                  || refresh "$TPL/pipeline.md"              espalier/pipeline.md
grep -qF "$ROUTER_MARK" espalier/skills/espalier/SKILL.md 2>/dev/null     || refresh "$TPL/skills/espalier.md"       espalier/skills/espalier/SKILL.md
mkdir -p espalier/skills/espalier/stages espalier/agents/modes
for _f in $STAGE_FILES; do
  cmp -s "$TPL/skills/espalier-stages/$_f.md" "espalier/skills/espalier/stages/$_f.md" 2>/dev/null \
    || refresh "$TPL/skills/espalier-stages/$_f.md" "espalier/skills/espalier/stages/$_f.md"
done
for _f in $MODE_FILES; do
  cmp -s "$TPL/agents/modes/$_f.md" "espalier/agents/modes/$_f.md" 2>/dev/null \
    || refresh "$TPL/agents/modes/$_f.md" "espalier/agents/modes/$_f.md"
done
grep -qF "$LANE_MARK"    espalier/skills/espalier-fix/SKILL.md 2>/dev/null || refresh "$TPL/skills/espalier-fix.md"   espalier/skills/espalier-fix/SKILL.md
grep -qF "$HELPERS_MARK" espalier/hooks/drift-helpers.sh 2>/dev/null       || refresh "$HTPL/drift-helpers.sh"        espalier/hooks/drift-helpers.sh
if ! grep -qF "$STATS_MARK" espalier/hooks/espalier-stats.sh 2>/dev/null; then
  refresh "$HTPL/espalier-stats.sh" espalier/hooks/espalier-stats.sh
  chmod +x espalier/hooks/espalier-stats.sh 2>/dev/null || true
fi

# --- 2. Anchored edits (text extracted from the templates) -------------------
BLK=$(mktemp -t v0260blk.XXXX)
trap 'rm -f "$BLK"' EXIT

record_skip() {  # $1 = label, $2 = file, $3 = anchor description
  log "WARN: $2 is customised past the stock shape ($3 not found) — skipped."
  log "      Manual step: port the v0.26.0 '$1' text from the template yourself."
  grep -qF "v0.26.0-$1" "$SKIPFILE" 2>/dev/null \
    || echo "v0.26.0-$1: customised, manual port needed ($2)" >> "$SKIPFILE"
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
  local f="$1" anchor="$2" tmp="$1.v0260tmp"
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

# swap_block FILE START END — the span from the first line containing START
# through the first later line containing END (inclusive) becomes $BLK.
swap_block() {
  local f="$1" start="$2" end="$3" tmp="$1.v0260tmp"
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
    espalier/agents/harness-coder.md)           echo agents/harness-coder.md ;;
    espalier/agents/harness-security.md)        echo agents/harness-security.md ;;
    espalier/skills/espalier-testing/SKILL.md)  echo skills/espalier-testing.md ;;
    espalier/skills/espalier-security/SKILL.md) echo skills/espalier-security.md ;;
    espalier/skills/espalier-coding/SKILL.md)   echo skills/espalier-coding.md ;;
    *) die "no template mapping for $1" ;;
  esac
}
# swap_step LABEL FILE MARKER TPL_START TPL_END OLD_START OLD_END — no-op when
# MARKER is present; otherwise swap the OLD span (stock v0.25 anchors) with
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
# insert_step LABEL FILE MARKER TPL_START TPL_END ANCHOR — $BLK before ANCHOR.
insert_step() {
  local label="$1" f="$2" marker="$3" ts="$4" te="$5" anchor="$6"
  handled "$marker" "$f" "$label" && return 0
  if grep -qF -- "$anchor" "$f" 2>/dev/null; then
    extract_block "$TPL/$(_tpl_of "$f")" "$ts" "$te"
    insert_before "$f" "$anchor"
    log "applied $label ($f)"
  else
    record_skip "$label" "$f" "the '$anchor' anchor"
  fi
}

# 2a. coder
if [ -f "$CODER" ]; then
  insert_step coder-abuse-now "$CODER" "$CODER_ABUSE" "$CODER_ABUSE" "$CODER_ABUSE_END" '### Writing Abuse Tests (contract phase)'
  swap_step coder-contract-gaps "$CODER" "$CODER_GAPS" \
    "$CODER_GAPS_START" "$CODER_GAPS_END" "$CODER_GAPS_START" "$CODER_GAPS_END"
  swap_step coder-contract-entry "$CODER" "$CODER_ENTRY" \
    "$CODER_ENTRY_START" "$CODER_ENTRY" "$CODER_ENTRY_START" "$CODER_ENTRY_OLD_END"
  insert_step coder-verify-one-call "$CODER" "$CODER_VERIFY" "$CODER_VERIFY" "$CODER_VERIFY_END" '## Handoff: Finish Bounded, Hand Off Clean'
  swap_step coder-must-not-verify "$CODER" "$CODER_MUSTNOT" \
    "$CODER_MUSTNOT_OLD" "$CODER_MUSTNOT_OLD" "$CODER_MUSTNOT_OLD" "$CODER_MUSTNOT_OLD"
fi

# 2b. security
if [ -f "$SEC" ]; then
  swap_step security-test-scope "$SEC" "$SEC_SCOPE" \
    "$SEC_SCOPE_START" "$SEC_SCOPE_END" "$SEC_SCOPE_START" "$SEC_SCOPE_END"
  # The contract block through the Priority Rubric heading (inclusive on both
  # sides, so the heading is preserved): the two example entries gain their
  # covered_by lines and the routing-fact paragraph follows the fence.
  swap_step security-contract-covered-by "$SEC" "$SEC_CONTRACT" \
    "$SEC_CONTRACT_START" "$SEC_CONTRACT_END" "$SEC_CONTRACT_START" "$SEC_CONTRACT_END"
fi

# 2c. the three LLM-written skills — one sentence each
if [ -f "$TESTSK" ]; then
  swap_step testing-covered-by "$TESTSK" "$TEST_MARK" "$TEST_START" "$TEST_END" "$TEST_START" "$TEST_END"
fi
if [ -f "$SECSK" ]; then
  swap_step security-skill-covered-by "$SECSK" "$SECSK_MARK" "$SECSK_START" "$SECSK_END" "$SECSK_OLD_END" "$SECSK_OLD_END"
fi
if [ -f "$CODESK" ]; then
  swap_step coding-skill-verify "$CODESK" "$CODESK_MARK" "$CODESK_START" "$CODESK_END" "$CODESK_START" "$CODESK_OLD_END"
fi

# 2d. pre-push-gate.sh — build ∥ lint by default. The discovered run_build /
# run_lint bodies are the install's own and stay; only the two serial
# section functions and their call lines become the one concurrent section
# from the template. A gate without the stock call lines (customised past
# the v0.22 shape) is skipped with a record; the greenfield placeholder
# (no run_build) is left for Pass 2.
_del_fn() {  # FILE NAME — delete the `NAME() {` … `}` definition by brace depth
  local f="$1" name="$2" tmp="$1.v0260tmp"
  cp "$f" "$tmp"
  awk -v fn="$name" '
    !insp && index($0, fn "() {") == 1 { insp = 1 }
    insp {
      line = $0
      depth += gsub(/\{/, "{", line) - gsub(/\}/, "}", line)
      if (depth <= 0) insp = 0
      next
    }
    { print }
  ' "$tmp" > "$f"
  rm -f "$tmp"
}
if [ -f "$GATE" ] && grep -q '^run_build()' "$GATE" 2>/dev/null && ! handled "$GATE_MARK" "$GATE" gate-build-lint-overlap; then
  B_CALL='if [ "${PIPELINE_TRACKED:-yes}" = "yes" ] && [ "$HOOK_PARALLEL" != "yes" ]; then gate_build_section; fi'
  L_CALL='if [ "${PIPELINE_TRACKED:-yes}" = "yes" ] && [ "$HOOK_PARALLEL" != "yes" ]; then gate_lint_section; fi'
  if grep -qxF -- "$B_CALL" "$GATE" && grep -qxF -- "$L_CALL" "$GATE" \
     && grep -q '^gate_build_section() {' "$GATE" && grep -q '^gate_lint_section() {' "$GATE"; then
    backup_once "$GATE"
    extract_block "$HTPL/pre-push-gate.sh" '# Pipeline-only gate: wrapped in a function' 'then gate_build_lint_section; fi'
    swap_block "$GATE" "$L_CALL" "$L_CALL"
    grep -vxF -- "$B_CALL" "$GATE" > "$GATE.v0260tmp" && mv "$GATE.v0260tmp" "$GATE"
    _del_fn "$GATE" gate_build_section
    _del_fn "$GATE" gate_lint_section
    # the parallel-mode comment's last line describes the default
    OLD_C='# absent (the default): the serial sections below run exactly as before.'
    NEW_C='# absent (the default): build and lint overlap, tests follow a green build.'
    awk -v o="$OLD_C" -v n="$NEW_C" '$0 == o { print n; next } { print }' "$GATE" > "$GATE.v0260tmp" && mv "$GATE.v0260tmp" "$GATE"
    # the old comment above gate_build_section now sits orphaned after run_build
    awk 'BEGIN{skip=0} /^# Pipeline-only gate: wrapped in a function so a no-state-file push can skip it$/ && !seen {seen=1; skip=2} skip>0 {skip--; next} {print}' "$GATE" > "$GATE.v0260tmp" && mv "$GATE.v0260tmp" "$GATE"
    chmod +x "$GATE" 2>/dev/null || true
    bash -n "$GATE" || die "pre-push-gate.sh no longer parses after the build ∥ lint edit — restore $GATE.pre-v0.26.bak"
    log "applied gate-build-lint-overlap ($GATE)"
  else
    record_skip gate-build-lint-overlap "$GATE" "the stock gate_build_section / gate_lint_section call lines"
  fi
fi

# --- 3. .gitignore: migration backups (already there from #35 on most installs)
if ! grep -qxF '*.pre-v0.*.bak' .gitignore 2>/dev/null; then
  if [ -s .gitignore ] && [ -n "$(tail -c1 .gitignore)" ]; then printf '\n' >> .gitignore; fi
  printf '# espalier migration backups (one per file per migration)\n*.pre-v0.*.bak\n' >> .gitignore
  log "added '*.pre-v0.*.bak' to .gitignore"
fi

# --- Verify ------------------------------------------------------------------
grep -qF "$HELPERS_MARK" espalier/hooks/drift-helpers.sh  || die "post-migration verification failed: drift-helpers.sh lacks the turn-economy helpers"
grep -qF "$ROUTER_MARK"  espalier/skills/espalier/SKILL.md     || die "post-migration verification failed: espalier SKILL lacks '$ROUTER_MARK'"
for _f in $STAGE_FILES; do cmp -s "$TPL/skills/espalier-stages/$_f.md" "espalier/skills/espalier/stages/$_f.md" || die "post-migration verification failed: stages/$_f.md differs from the template"; done
grep -qF "$LANE_MARK"    espalier/skills/espalier-fix/SKILL.md || die "post-migration verification failed: espalier-fix SKILL lacks '$LANE_MARK'"
grep -qF "$STATS_MARK"   espalier/hooks/espalier-stats.sh || die "post-migration verification failed: espalier-stats.sh lacks '$STATS_MARK'"
[ -f "$CODER" ] && { handled "$CODER_VERIFY" "$CODER" coder-verify-one-call || die "post-migration verification failed: coder lacks Verify in One Call"; }
[ -f "$SEC" ]   && { handled "$SEC_CONTRACT" "$SEC" security-contract-covered-by || die "post-migration verification failed: security agent lacks covered_by"; }
if grep -q 'v0.26.0-' "$SKIPFILE" 2>/dev/null; then
  log "done with skips — see $SKIPFILE (each is a manual port from the template; the file works as before until then)."
fi

log "done. v0.26.0 applied — backups at <file>.pre-v0.26.bak (gitignored)."
log "Every gate and cap is unchanged. New: coders write the abuse tests for the fields they classify"
log "with the code and verify in one exit_gate call; the auditor's contract carries covered_by:, so a"
log "covered contract spawns no contract-phase coder (the delta review still proves every entry); the"
log "session-boundary preference is asked once at the approval gate; the orchestrator's retyped bash"
log "blocks are helpers (regression_verify, record_commits, certificate_write, drift_index, stage85_drift,"
log "backlink_all); exit_gate scopes monorepo and uv/poetry test bodies and starts tests as soon as the"
log "build is green; the push hook runs build and lint concurrently."
log "Run 'bash espalier/hooks/espalier-stats.sh' for the contract-phase and session-boundary rows."
exit 0
