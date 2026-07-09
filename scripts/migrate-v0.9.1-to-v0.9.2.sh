#!/bin/bash
# Migrate an Espalier v0.9.1 target repo to v0.9.2.
#
# Run from the TARGET project root. Idempotent. Safe to re-run.
# Use --dry-run to preview before applying.
#
# v0.9.2 is a correctness patch — no new lane, no new stage:
#   - fix lane: late-escalation gates detect via a marker line (the old text
#     called a shell helper that was never shipped); the Stage 7.2 back-link
#     reads the real '# Bug:' title and its per-entry guards exit cleanly; the
#     Stage 5 regression verification is scoped + dep-linked and can no longer
#     certify a test that never ran.
#   - gates: /espalier-audit's fix handoff and /espalier-prune's unattended
#     path key off interactivity_mode (a TTY test is always false inside
#     Claude Code); the push gate gates the ACTIVE change (terminal statuses
#     stop gating — completed changes no longer block later manual pushes)
#     and parses test counts from jest/mocha/rspec/go-shaped output.
#   - discovery: ci_checks gains a null convention; scout 1.11 ships in
#     .scout-prompts.md; prune/doctor map the security/production rules.
#   - orchestrator: session resumption is scoped to the invoked requirement.
#
# This migration:
#   1. Backs up any customised pure-copy pipeline file → <file>.pre-v0.9.2.bak
#   2. bootstrap --force — refreshes ALL pure-copy skills (espalier,
#      espalier-fix, prune, doctor, ask, audit, pipeline.md, scout-prompts)
#      and re-copies the hook templates (lookup-helpers, post-merge-backlink,
#      rebuild-commit-index, drift-helpers), then re-validates (37 checks).
#   3. Surgically patches the per-project (substituted) pre-push-gate.sh:
#      the active-change state selection and the portable test-count parse —
#      preserving the target's substituted {test_command}.
#   4. Verifies everything landed.
#
# Usage: bash migrate-v0.9.1-to-v0.9.2.sh [--dry-run] [--yes] [--plugin-dir=<path>]

set -u

DRY_RUN=no
SKIP_PROMPT=no
PLUGIN_DIR="${ESPALIER_PLUGIN_DIR:-${HARNESS_PLUGIN_DIR:-}}"
for arg in "$@"; do
  case "$arg" in
    --dry-run)      DRY_RUN=yes ;;
    --yes)          SKIP_PROMPT=yes ;;
    --plugin-dir=*) PLUGIN_DIR="${arg#--plugin-dir=}" ;;
    -h|--help)      sed -n '2,34p' "$0"; exit 0 ;;
    *) echo "ERROR: unknown flag: $arg (use --help)" >&2; exit 2 ;;
  esac
done

log() { echo "[migrate-v0.9.2] $*"; }

FIX="espalier/skills/espalier-fix/SKILL.md"
ORCH="espalier/skills/espalier/SKILL.md"
PIPELINE="espalier/pipeline.md"
PRUNE="espalier/skills/espalier-prune/SKILL.md"
DOCTOR="espalier/skills/espalier-doctor/SKILL.md"
AUDIT="espalier/skills/espalier-audit/SKILL.md"
SCOUTS="espalier/.scout-prompts.md"
GATE="espalier/hooks/pre-push-gate.sh"

# --- Preflight (target) -----------------------------------------------------
if [ -d "harness" ] && [ ! -d "espalier" ]; then
  echo "ERROR: pre-v0.4 install detected (harness/ directory)." >&2
  echo "Run /espalier-migrate first to apply the earlier chain, then re-run." >&2
  exit 1
fi
if [ ! -f "$PIPELINE" ]; then
  echo "ERROR: $PIPELINE not found — run this from the target project root." >&2
  exit 1
fi
if [ ! -f "espalier/.merge-hook-decision" ]; then
  echo "ERROR: espalier/.merge-hook-decision missing — install looks incomplete." >&2
  echo "Re-run /espalier-init (or bootstrap-espalier.sh --force) to repair it first." >&2
  exit 1
fi
# Prerequisite: v0.9.1 (config-driven caps) must already be applied.
if ! grep -qF "max-code-rounds" "$PIPELINE" 2>/dev/null; then
  echo "ERROR: $PIPELINE does not reference max-code-rounds (pre-v0.9.1)." >&2
  echo "Run /espalier-migrate to apply the v0.9.1 step first." >&2
  exit 1
fi

# --- Locate the plugin (must contain scripts/bootstrap-espalier.sh) ----------
if [ -z "$PLUGIN_DIR" ] || [ ! -f "$PLUGIN_DIR/scripts/bootstrap-espalier.sh" ]; then
  PLUGIN_DIR=""
  self_dir="$(cd "$(dirname "$0")" && pwd)"
  candidate="$(cd "$self_dir/.." 2>/dev/null && pwd)"
  if [ -n "$candidate" ] && [ -f "$candidate/scripts/bootstrap-espalier.sh" ]; then
    PLUGIN_DIR="$candidate"
  fi
fi
if [ -z "$PLUGIN_DIR" ] || [ ! -f "$PLUGIN_DIR/scripts/bootstrap-espalier.sh" ]; then
  echo "ERROR: couldn't find the Espalier plugin (scripts/bootstrap-espalier.sh)." >&2
  echo "Pass --plugin-dir=<path to espalier-engineering checkout>." >&2
  exit 1
fi
BOOTSTRAP="$PLUGIN_DIR/scripts/bootstrap-espalier.sh"
PLUGIN_INIT="$PLUGIN_DIR/skills/espalier-init"
GATE_TPL="$PLUGIN_INIT/hook-templates/pre-push-gate.sh"

# Plugin must be v0.9.2+ (its fix-lane template has no phantom helper and its
# gate template selects the active change).
if grep -qF "_fire_late_escalation_prompt" "$PLUGIN_INIT/templates/skills/espalier-fix.md" 2>/dev/null \
   || ! grep -qF "Find the ACTIVE change" "$GATE_TPL" 2>/dev/null \
   || ! grep -qF "Scout 1.11" "$PLUGIN_INIT/templates/scout-prompts.md" 2>/dev/null; then
  echo "ERROR: plugin at $PLUGIN_DIR is pre-v0.9.2." >&2
  echo "Update the plugin (or pass --plugin-dir to a v0.9.2+ checkout)." >&2
  exit 1
fi

DECISION=$(cat espalier/.merge-hook-decision 2>/dev/null)
DOCTOR_CADENCE=$(sed -n 's/^cadence: //p' espalier/.doctor-cadence 2>/dev/null)
[ -z "$DOCTOR_CADENCE" ] && DOCTOR_CADENCE=weekly

# --- Idempotency --------------------------------------------------------------
FIX_DONE=no; GATE_SEL_DONE=no; GATE_CNT_DONE=no; SCOUTS_DONE=no; AUDIT_DONE=no
{ [ -f "$FIX" ] && ! grep -qF "_fire_late_escalation_prompt" "$FIX" \
    && grep -qF "LATE_ESCALATION_GATE" "$FIX"; } 2>/dev/null && FIX_DONE=yes
grep -qF "Find the ACTIVE change" "$GATE" 2>/dev/null && GATE_SEL_DONE=yes
grep -qF "could not parse a test count" "$GATE" 2>/dev/null && GATE_CNT_DONE=yes
grep -qF "Scout 1.11" "$SCOUTS" 2>/dev/null && SCOUTS_DONE=yes
grep -qF "interactivity_mode" "$AUDIT" 2>/dev/null && AUDIT_DONE=yes

if [ "$FIX_DONE" = yes ] && [ "$GATE_SEL_DONE" = yes ] && [ "$GATE_CNT_DONE" = yes ] \
   && [ "$SCOUTS_DONE" = yes ] && [ "$AUDIT_DONE" = yes ]; then
  log "Already at v0.9.2 — fix lane, gate, scout-prompts, and audit skill all current. Nothing to do."
  exit 0
fi

# --- Plan / dry run -----------------------------------------------------------
cat << EOF

Espalier correctness patch (v0.9.1 → v0.9.2)

Plan:
  1. Backup-on-diff: customised pure-copy files → <file>.pre-v0.9.2.bak
  2. bootstrap-espalier.sh --force  (merge-decision=$DECISION, doctor-cadence=$DOCTOR_CADENCE)
       → refreshes pure-copy skills (espalier, espalier-fix, prune, doctor,
         ask, audit), pipeline.md, .scout-prompts.md, and the hook templates
         (lookup-helpers, post-merge-backlink, rebuild-commit-index,
         drift-helpers); 37-check validation
  3. Surgical gate patches (per-project $GATE):
       - active-change state selection (terminal statuses stop gating)
       - portable test-count parse (test command preserved)
  4. Verify everything landed

Plugin: $PLUGIN_DIR
EOF

if [ "$DRY_RUN" = "yes" ]; then
  echo "Mode: DRY RUN (no changes will be written)"
elif [ "$SKIP_PROMPT" != "yes" ]; then
  printf 'Apply upgrade? [y/N]: '
  read -r confirm
  case "$confirm" in
    y|Y|yes) ;;
    *) echo "Cancelled."; exit 0 ;;
  esac
fi

# --- Step 1: backup-on-diff for pure-copy files --------------------------------

log "Step 1: backup-on-diff for pure-copy files"
BACKUPS_MADE=""
backup_if_differs() {
  local current="$1" new_template="$2"
  [ -f "$current" ] || return 0
  [ -f "$new_template" ] || { echo "  WARN: plugin template missing: $new_template" >&2; return 0; }
  if cmp -s "$current" "$new_template"; then
    echo "  unchanged: $current (no backup needed)"; return 0
  fi
  local backup="${current}.pre-v0.9.2.bak"
  if [ "$DRY_RUN" = "yes" ]; then
    echo "  [dry-run] backup: $current → $backup"
  else
    cp "$current" "$backup"; echo "  backed up: $current → $backup"
  fi
  BACKUPS_MADE="${BACKUPS_MADE}${backup}
"
}
backup_if_differs "$PIPELINE" "$PLUGIN_INIT/templates/pipeline.md"
backup_if_differs "$ORCH"     "$PLUGIN_INIT/templates/skills/espalier.md"
backup_if_differs "$FIX"      "$PLUGIN_INIT/templates/skills/espalier-fix.md"
backup_if_differs "$PRUNE"    "$PLUGIN_INIT/templates/skills/espalier-prune.md"
backup_if_differs "$DOCTOR"   "$PLUGIN_INIT/templates/skills/espalier-doctor.md"
backup_if_differs "$AUDIT"    "$PLUGIN_INIT/templates/skills/espalier-audit.md"

# --- Step 2: bootstrap --force --------------------------------------------------

log "Step 2: bootstrap-espalier.sh --force"
BOOT_FLAGS="--force --project-dir=. --plugin-dir=$PLUGIN_INIT --merge-decision=$DECISION --doctor-cadence=$DOCTOR_CADENCE --yes"
if [ "$DRY_RUN" = "yes" ]; then
  bash "$BOOTSTRAP" $BOOT_FLAGS --dry-run
else
  if ! bash "$BOOTSTRAP" $BOOT_FLAGS; then
    echo "ERROR: bootstrap-espalier.sh failed — see output above. Aborting." >&2
    exit 1
  fi
fi

# --- Step 3: surgical gate patches ----------------------------------------------
# The gate is a per-project SUBSTITUTION file ({build/lint/test_command} were
# filled at init), so bootstrap --force never touches it. Replace two spans,
# each extracted from the v0.9.2 gate template at run time (no duplication),
# bounded by anchors present in every v0.8.2+ gate:
#   selection: first '^# Find the ' line  → line before '^CURRENT_STAGE='
#   count:     '^# Run tests and check count' → line before '^echo "All gates passed'
# The count span carries the target's OWN substituted test command forward.

# replace_span FILE OUT START_RE END_RE NEWTEXT_FILE — copy FILE to OUT with the
# span [first START_RE line .. line before first END_RE line at-or-after it]
# replaced by NEWTEXT_FILE's content. Returns 1 if either anchor is missing.
replace_span() {
  local file="$1" out="$2" start_re="$3" end_re="$4" newf="$5"
  grep -qE "$start_re" "$file" || return 1
  grep -qE "$end_re"   "$file" || return 1
  awk -v start_re="$start_re" -v end_re="$end_re" -v newf="$newf" '
    !inspan && $0 ~ start_re && !done {
      inspan=1
      while ((getline line < newf) > 0) print line
      close(newf)
      next
    }
    inspan && $0 ~ end_re { inspan=0; done=1 }
    !inspan { print }
  ' "$file" > "$out"
}

# extract_span FILE START_RE END_RE — print [first START_RE line .. line before
# first END_RE line after it].
extract_span() {
  awk -v start_re="$2" -v end_re="$3" '
    !f && $0 ~ start_re { f=1 }
    f && $0 ~ end_re { exit }
    f { print }
  ' "$1"
}

log "Step 3: surgical gate patches"
if [ ! -f "$GATE" ]; then
  echo "  WARN: $GATE not found — skipping (run /espalier-init to repair)." >&2
else
  # 3a — active-change state selection
  if grep -qF "Find the ACTIVE change" "$GATE"; then
    log "  selection already present — skip."
  elif ! grep -qE '^# Find the ' "$GATE" || ! grep -qE '^CURRENT_STAGE=' "$GATE"; then
    echo "  WARN: selection anchors not found in $GATE — looks customised." >&2
    echo "  Replace its state-file selection manually with this block:" >&2
    extract_span "$GATE_TPL" '^# Find the ' '^CURRENT_STAGE=' | sed 's/^/    | /' >&2
  elif [ "$DRY_RUN" = "yes" ]; then
    log "  [dry-run] would replace the state-file selection block"
  else
    _new=$(mktemp); _out=$(mktemp)
    extract_span "$GATE_TPL" '^# Find the ' '^CURRENT_STAGE=' > "$_new"
    if replace_span "$GATE" "$_out" '^# Find the ' '^CURRENT_STAGE=' "$_new"; then
      mv "$_out" "$GATE"; chmod +x "$GATE"; log "  selection block replaced."
    else
      rm -f "$_out"; echo "  WARN: selection replace failed — patch manually." >&2
    fi
    rm -f "$_new"
  fi

  # 3b — portable test-count parse (preserve the substituted test command)
  if grep -qF "could not parse a test count" "$GATE"; then
    log "  count parse already present — skip."
  elif ! grep -qE '^# Run tests and check count' "$GATE" || ! grep -qE '^echo "All gates passed' "$GATE"; then
    echo "  WARN: count anchors not found in $GATE — looks customised." >&2
    echo "  Replace its test-count section manually with the template's" >&2
    echo "  '# Run tests and check count' block ({test_command} = your runner)." >&2
  elif [ "$DRY_RUN" = "yes" ]; then
    log "  [dry-run] would replace the test-count block (test command preserved)"
  else
    OLD_TEST_CMD=$(sed -n 's/^TEST_OUTPUT=\$(\(.*\) 2>&1)$/\1/p' "$GATE" | head -1)
    if [ -z "$OLD_TEST_CMD" ]; then
      echo "  WARN: could not read the substituted test command from $GATE — patch manually." >&2
    else
      _esc=$(printf '%s' "$OLD_TEST_CMD" | sed 's/[&\\|]/\\&/g')
      _new=$(mktemp); _out=$(mktemp)
      extract_span "$GATE_TPL" '^# Run tests and check count' '^echo "All gates passed' \
        | sed "s|{test_command}|$_esc|g" > "$_new"
      if replace_span "$GATE" "$_out" '^# Run tests and check count' '^echo "All gates passed' "$_new"; then
        mv "$_out" "$GATE"; chmod +x "$GATE"; log "  count block replaced (test command: $OLD_TEST_CMD)."
      else
        rm -f "$_out"; echo "  WARN: count replace failed — patch manually." >&2
      fi
      rm -f "$_new"
    fi
  fi
fi

# --- Step 4: verification --------------------------------------------------------

log "Step 4: verification"
if [ "$DRY_RUN" = "yes" ]; then
  echo "(dry run — skipping verification)"
else
  pass=0; fail=0; warn=0
  check() { if eval "$2" >/dev/null 2>&1; then pass=$((pass+1)); echo "  ✓ $1"; else fail=$((fail+1)); echo "  ✗ $1"; fi; }
  warn_check() { if eval "$2" >/dev/null 2>&1; then pass=$((pass+1)); echo "  ✓ $1"; else warn=$((warn+1)); echo "  ! $1 (warn-only)"; fi; }
  check "fix lane has no phantom helper"          "! grep -qF '_fire_late_escalation_prompt' $FIX"
  check "fix lane detects via marker line"        "grep -qF 'LATE_ESCALATION_GATE' $FIX"
  check "fix lane scoped regression verification" "grep -qF 'REG_RUN' $FIX"
  check "back-link reads the bug title"           "grep -qF \"grep -m1 '^# Bug:'\" $FIX"
  check "orchestrator scopes resumption"          "grep -qF 'never hijack' $ORCH"
  check "audit handoff uses interactivity_mode"   "grep -qF 'interactivity_mode' $AUDIT"
  check "prune unattended uses interactivity_mode" "grep -qF 'interactivity_mode' $PRUNE"
  check "prune maps security-standards"           "grep -qF 'rules/security-standards.md' $PRUNE"
  check "doctor maps production-standards"        "grep -qF 'rules/production-standards.md' $DOCTOR"
  check "scout-prompts ships scout 1.11"          "grep -qF 'Scout 1.11' $SCOUTS"
  check "pipeline paths are typed"                "! grep -qF 'changes/{slug}' $PIPELINE"
  check "gate selects the active change"          "grep -qF 'Find the ACTIVE change' $GATE"
  check "gate count parse is portable"            "grep -qF 'could not parse a test count' $GATE"
  # The REAL invariant: no placeholder was left unsubstituted. Hard-check that.
  check "gate left no {test_command} placeholder"  "! grep -qF '{test_command}' $GATE"
  # The canonical `TEST_OUTPUT=$(...)` shape is what the template generates, but a
  # project whose gate was customised at init to run tests another way (per-container
  # `docker compose exec`, a bespoke runner loop) will never have it. That is a
  # template-shape mismatch, not a failed migration — a blocking gate that cries
  # wolf gets disabled. Warn instead.
  warn_check "gate uses the template's TEST_OUTPUT shape" "grep -qE '^TEST_OUTPUT=' $GATE"
  check "gate parses clean (bash -n)"             "/bin/bash -n $GATE"
  check "backlink hook uses shared matcher"       "grep -qF '_fuzzy_scan' espalier/hooks/post-merge-backlink.sh"
  echo ""
  echo "  Verification: $pass passed, $fail failed, $warn warn-only"
  if [ "$warn" -gt 0 ]; then
    echo "  ($warn warn-only: the gate is customised past the template shape — it still"
    echo "   gates; re-check by hand that its test step blocks on failure and on 0 tests.)"
  fi
  [ "$fail" -eq 0 ] || exit 1
fi

# --- Summary ---------------------------------------------------------------------

echo ""
echo "Upgrade complete. v0.9.2 is a correctness patch: the fix lane's escalation"
echo "gates, back-link, and regression verification are now mechanically sound;"
echo "the audit/prune human gates fire in interactive Claude Code sessions; the"
echo "push gate gates the ACTIVE change (completed changes no longer block later"
echo "manual pushes) and understands mocha/rspec/go output; prune/doctor can"
echo "refresh security-standards.md and production-standards.md."
echo ""
if [ -n "$BACKUPS_MADE" ]; then
  echo "Backups written (pre-existing customisations preserved):"
  printf '%s' "$BACKUPS_MADE" | sed 's/^/  - /'
  echo "Diff each backup against the live file to re-apply any customisation."
  echo ""
fi
echo "Next steps:"
echo "  1. Review the diff: git diff --stat && git status"
echo "  2. Commit:"
echo "       git add -A"
echo "       git commit -m 'chore: migrate to Espalier v0.9.2'"
exit 0
