#!/bin/bash
# Migrate an Espalier v0.8.1 target repo to v0.8.2.
#
# Run from the TARGET project root. Idempotent. Safe to re-run.
# Use --dry-run to preview before applying.
#
# v0.8.2 closes the open-review-loop gap: a coder fix that follows a P0
# finding was not guaranteed to be re-reviewed, so a NEW bug introduced by
# the fix could ship unreviewed. v0.8.2 makes code review a FIXPOINT LOOP —
# every coder fix is re-reviewed until a fresh review of the current code is
# clean — and adds a push-gate certificate so the guarantee fails closed:
# the pushed code must match the fingerprint the last review actually saw.
#
# This migration:
#   1. Backs up any customised pure-copy pipeline file → <file>.pre-v0.8.2.bak
#   2. bootstrap --force — refreshes the two changed pure-copy files
#      (pipeline.md, espalier-fix) with the loop + Base-Ref/Reviewed-Diff writes.
#   3. Appends a "## Re-review Rounds" section to the reviewer sub-agent.
#   4. Inserts the review-certificate check into the LLM-written push gate.
#   5. Verifies all four landed.
#
# What this script does NOT do:
#   - Re-gate any in-flight feat or fix. v0.8.2 only affects new pipeline runs;
#     an in-flight change with no certificate falls through the push gate with
#     a warning (fail-open for legacy state).
#
# Usage:
#   bash migrate-v0.8.1-to-v0.8.2.sh [--dry-run] [--yes] [--plugin-dir=<path>]

set -u

DRY_RUN=no
SKIP_PROMPT=no
PLUGIN_DIR="${ESPALIER_PLUGIN_DIR:-${HARNESS_PLUGIN_DIR:-}}"

for arg in "$@"; do
  case "$arg" in
    --dry-run)            DRY_RUN=yes ;;
    --yes)                SKIP_PROMPT=yes ;;
    --plugin-dir=*)       PLUGIN_DIR="${arg#--plugin-dir=}" ;;
    -h|--help)
      sed -n '2,28p' "$0"
      exit 0
      ;;
    *)
      echo "ERROR: unknown flag: $arg (use --help)" >&2
      exit 2
      ;;
  esac
done

log() { echo "[migrate v0.8.1→v0.8.2] $*"; }

REVIEWER="espalier/agents/harness-reviewer.md"
GATE="espalier/hooks/pre-push-gate.sh"

# --- Preflight ---------------------------------------------------------------

if [ -d "harness" ] && [ ! -d "espalier" ]; then
  echo "ERROR: this is a pre-v0.4 install (harness/ present, no espalier/)." >&2
  echo "Run the earlier migrations first (via /espalier-migrate)." >&2
  exit 1
fi

if [ ! -d "espalier" ]; then
  echo "ERROR: no espalier/ directory — not an Espalier install." >&2
  echo "Use /espalier-init to set up Espalier in a fresh project." >&2
  exit 1
fi

if [ ! -f "espalier/.merge-hook-decision" ]; then
  echo "ERROR: espalier/.merge-hook-decision missing — install looks incomplete." >&2
  echo "Re-run /espalier-init (or bootstrap-espalier.sh --force) to repair it first." >&2
  exit 1
fi

if [ ! -f "espalier/hooks/drift-detect.sh" ] || [ ! -f "espalier/.doctor-cadence" ]; then
  echo "ERROR: install looks pre-v0.5 (drift hooks or .doctor-cadence missing)." >&2
  echo "Run /espalier-migrate to apply the earlier upgrades first." >&2
  exit 1
fi

# Prerequisite: v0.8.1 must already be applied (the reviewer carries the
# Runtime-Surface Review section the new Re-review Rounds text points at). The
# chain runs in order so this normally holds; guard anyway.
if ! grep -qF "## Runtime-Surface Review" "$REVIEWER" 2>/dev/null; then
  echo "ERROR: $REVIEWER has no '## Runtime-Surface Review' section (pre-v0.8.1)." >&2
  echo "Run /espalier-migrate to apply the v0.8.1 patch first." >&2
  exit 1
fi

# Already-v0.8.2 detector — all three per-project artifacts present.
PIPE_DONE=no; REV_DONE=no; GATE_DONE=no
grep -qF "fixpoint loop" espalier/pipeline.md 2>/dev/null && PIPE_DONE=yes
grep -qF "## Re-review Rounds" "$REVIEWER" 2>/dev/null && REV_DONE=yes
grep -qF "Reviewed-Diff:" "$GATE" 2>/dev/null && GATE_DONE=yes
if [ "$PIPE_DONE" = yes ] && [ "$REV_DONE" = yes ] && [ "$GATE_DONE" = yes ]; then
  echo "Already on v0.8.2 (fixpoint loop + reviewer section + push-gate certificate present)."
  echo "Nothing to do."
  exit 0
fi

# Locate the plugin root (must contain scripts/bootstrap-espalier.sh).
if [ -z "$PLUGIN_DIR" ] || [ ! -f "$PLUGIN_DIR/scripts/bootstrap-espalier.sh" ]; then
  PLUGIN_DIR=""
  for candidate in \
    "$HOME/.claude/plugins/espalier-engineering" \
    "$HOME/.claude/plugins/espalier" \
    "$HOME/repos/espalier-engineering" \
    "$HOME/SBM_Projects/espalier-engineering"; do
    if [ -f "$candidate/scripts/bootstrap-espalier.sh" ]; then
      PLUGIN_DIR="$candidate"
      break
    fi
  done
fi

if [ -z "$PLUGIN_DIR" ] || [ ! -f "$PLUGIN_DIR/scripts/bootstrap-espalier.sh" ]; then
  echo "ERROR: couldn't find the Espalier plugin (scripts/bootstrap-espalier.sh)." >&2
  echo "Update the plugin first (/plugin update espalier-engineering), or pass" >&2
  echo "--plugin-dir=<path to espalier-engineering checkout>." >&2
  exit 1
fi

BOOTSTRAP="$PLUGIN_DIR/scripts/bootstrap-espalier.sh"
PLUGIN_INIT="$PLUGIN_DIR/skills/espalier-init"
DECISION=$(cat espalier/.merge-hook-decision 2>/dev/null)
DOCTOR_CADENCE=$(sed -n 's/^cadence: //p' espalier/.doctor-cadence 2>/dev/null)
[ -z "$DOCTOR_CADENCE" ] && DOCTOR_CADENCE=weekly

# Sanity-check the plugin actually carries the v0.8.2 template before we touch anything.
if ! grep -qF "fixpoint loop" "$PLUGIN_INIT/templates/pipeline.md" 2>/dev/null; then
  echo "ERROR: plugin at $PLUGIN_DIR is pre-v0.8.2 (no fixpoint loop in templates/pipeline.md)." >&2
  echo "Update the plugin to v0.8.2+ (or pass --plugin-dir to a v0.8.2 checkout)." >&2
  exit 1
fi

cat << EOF

Espalier re-review fixpoint loop + push-gate certificate upgrade (v0.8.1 → v0.8.2)

Plan:
  1. Backup-on-diff: any customised pipeline file → <file>.pre-v0.8.2.bak
  2. bootstrap-espalier.sh --force  (merge-decision=$DECISION, doctor-cadence=$DOCTOR_CADENCE)
       → refreshed pipeline.md / espalier-fix (fixpoint loop + Reviewed-Diff certificate)
  3. Append "## Re-review Rounds" to $REVIEWER
  4. Insert the review-certificate check into $GATE
  5. Verify all four landed

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

# --- Text to append / insert (quoted heredocs — emitted verbatim) ------------

emit_reviewer_section() {
cat << 'EOF'

## Re-review Rounds (you may be re-spawned on a fix)

You are stateless and will be spawned again after the coder fixes your findings.
A fix is the single most likely place for a NEW bug to enter, so a re-review is a
real review, not a rubber stamp:

1. You will be handed the "changed since last review" set — the files/hunks the
   coder just touched. Scrutinize those hardest.
2. Confirm the fix did not regress code that previously passed — check callers and
   any surface the changed code feeds (run the Runtime-Surface Review on the delta).
3. Your verdict still covers the WHOLE diff, not only the delta. Return PASS only
   when the code AS IT STANDS NOW is clean. If the fix introduced a new P0, report
   it — you will be re-spawned again after the next fix.

Never assume the fix is correct because it addresses your previous finding. Review
the new code as fresh code.
EOF
}

emit_gate_block() {
cat << 'EOF'
# Review-certificate check — the code being pushed must match what the last review
# (Stage 4 code / Stage 6 test) actually saw. Reviewed-Diff is a content fingerprint
# of the source diff (espalier/ bookkeeping excluded), anchored to the Base-Ref
# recorded at Stage 3. A code change after review changes the fingerprint and blocks
# the push until a fresh review re-certifies the current diff. This is what makes the
# coder→reviewer→coder loop fail closed: a fix that skipped re-review cannot ship.
REVIEWED=$(grep "Reviewed-Diff:" "$STATE_FILE" | tail -1 | sed 's/.*Reviewed-Diff:[[:space:]]*//' | tr -d '[:space:]')
BASE_REF=$(grep "Base-Ref:" "$STATE_FILE" | tail -1 | sed 's/.*Base-Ref:[[:space:]]*//' | tr -d '[:space:]')
if [ -n "$REVIEWED" ] && [ -n "$BASE_REF" ]; then
  CURRENT=$(git diff "$BASE_REF" -- . ':(exclude)espalier/' | git hash-object --stdin)
  if [ "$CURRENT" != "$REVIEWED" ]; then
    echo "BLOCKED: Source changed after its last review (Reviewed-Diff mismatch)."
    echo "  reviewed fingerprint: $REVIEWED"
    echo "  current  fingerprint: $CURRENT"
    echo "Re-run code review on the current diff (Stage 4) before pushing."
    exit 1
  fi
else
  echo "WARNING: No review certificate (Base-Ref/Reviewed-Diff) in $STATE_FILE —"
  echo "         legacy or pre-review change. Skipping the re-review check."
fi
EOF
}

# --- Step 1: backup-on-diff --------------------------------------------------
#
# bootstrap --force overwrites the pure-copy pipeline files. If a user (or a
# prior LLM run) customised one, the customisation is lost — so for each file we
# compare current content to the new v0.8.2 template and, if they differ, copy
# the current file aside to <file>.pre-v0.8.2.bak BEFORE bootstrap runs.

log "Step 1: backup-on-diff for pure-copy pipeline files"
BACKUPS_MADE=""

backup_if_differs() {
  local current="$1"
  local new_template="$2"
  if [ ! -f "$current" ]; then return 0; fi
  if [ ! -f "$new_template" ]; then
    echo "  WARN: plugin template missing: $new_template (skipping backup check)" >&2
    return 0
  fi
  if cmp -s "$current" "$new_template"; then
    echo "  unchanged: $current (no backup needed)"
    return 0
  fi
  local backup="${current}.pre-v0.8.2.bak"
  if [ "$DRY_RUN" = "yes" ]; then
    echo "  [dry-run] backup: $current → $backup"
  else
    cp "$current" "$backup"
    echo "  backed up: $current → $backup"
  fi
  BACKUPS_MADE="${BACKUPS_MADE}${backup}
"
}

backup_if_differs "espalier/pipeline.md"                  "$PLUGIN_INIT/templates/pipeline.md"
backup_if_differs "espalier/skills/espalier-fix/SKILL.md" "$PLUGIN_INIT/templates/skills/espalier-fix.md"

# --- Step 2: bootstrap --force (refreshes pure-copy pipeline files) ----------

log "Step 2: bootstrap-espalier.sh --force"
BOOT_FLAGS="--force --project-dir=. --plugin-dir=$PLUGIN_INIT --merge-decision=$DECISION --doctor-cadence=$DOCTOR_CADENCE --yes"
if [ "$DRY_RUN" = "yes" ]; then
  bash "$BOOTSTRAP" $BOOT_FLAGS --dry-run
else
  _boot_log=$(mktemp)
  bash "$BOOTSTRAP" $BOOT_FLAGS > "$_boot_log" 2>&1
  _boot_exit=$?
  cat "$_boot_log"
  if [ "$_boot_exit" -ne 0 ]; then
    # A failure AFTER wiring (the "Validation: N/M FAILED" line was printed)
    # means stages 1-10 completed and only the final health check is red —
    # expected MID-CHAIN when the plugin is newer than this migration's target
    # version (later-version artifacts are not installed yet; the next
    # migration in the chain installs them, and the chain's final step
    # re-validates everything). Anything else is a real bootstrap failure.
    if grep -qE 'Validation: [0-9]+/[0-9]+ FAILED' "$_boot_log"; then
      echo "WARN: bootstrap health check reports missing artifacts — expected mid-chain" >&2
      echo "      with a newer plugin; continuing (a later migration completes them)." >&2
    else
      echo "ERROR: bootstrap-espalier.sh failed — see output above. Aborting." >&2
      rm -f "$_boot_log"
      exit 1
    fi
  fi
  rm -f "$_boot_log"
fi

# --- Step 3: append the Re-review Rounds section to the reviewer agent -------
#
# harness-reviewer.md is written per-project at init (it carries {project_name}),
# so bootstrap never refreshes it — append the section in place, idempotently.

log "Step 3: append '## Re-review Rounds' to $REVIEWER"
if [ ! -f "$REVIEWER" ]; then
  echo "  WARN: $REVIEWER not found — skipping (run /espalier-init to repair)." >&2
elif grep -qF "## Re-review Rounds" "$REVIEWER"; then
  log "  already present — skip."
elif [ "$DRY_RUN" = "yes" ]; then
  log "  [dry-run] would append:"
  emit_reviewer_section | sed 's/^/    | /'
else
  # ensure a trailing newline so the appended heading is not glued to the last line
  if [ -n "$(tail -c1 "$REVIEWER" 2>/dev/null)" ]; then echo >> "$REVIEWER"; fi
  emit_reviewer_section >> "$REVIEWER"
  log "  appended."
fi

# --- Step 4: insert the review-certificate check into the push gate ----------
#
# pre-push-gate.sh is written per-project at init (build/lint/test commands are
# substituted in), so it cannot be refreshed from the template — insert the
# certificate block before its build check. Idempotent; degrades to a warning +
# manual snippet if the gate was customised past the anchor.

log "Step 4: insert the review-certificate check into $GATE"
if [ ! -f "$GATE" ]; then
  echo "  WARN: $GATE not found — skipping (run /espalier-init to repair)." >&2
elif grep -qF "Reviewed-Diff:" "$GATE"; then
  log "  already present — skip."
elif ! grep -qF "# Run build check" "$GATE"; then
  echo "  WARN: anchor '# Run build check' not found in $GATE — looks customised." >&2
  echo "  Add this block manually, immediately before your build check:" >&2
  emit_gate_block | sed 's/^/    | /' >&2
elif [ "$DRY_RUN" = "yes" ]; then
  log "  [dry-run] would insert before '# Run build check':"
  emit_gate_block | sed 's/^/    | /'
else
  _tmp="${GATE}.tmp.$$"
  {
    awk '/^# Run build check/{exit} {print}' "$GATE"
    emit_gate_block
    echo ""
    awk 'f{print} !f && /^# Run build check/{f=1; print}' "$GATE"
  } > "$_tmp"
  mv "$_tmp" "$GATE"
  chmod +x "$GATE"
  log "  inserted."
fi

# --- Step 5: verification ----------------------------------------------------

log "Step 5: verification"
if [ "$DRY_RUN" = "yes" ]; then
  echo "(dry run — skipping verification)"
else
  pass=0; fail=0
  check() {
    if eval "$2" >/dev/null 2>&1; then pass=$((pass+1)); echo "  ✓ $1"
    else fail=$((fail+1)); echo "  ✗ $1"; fi
  }
  check "pipeline.md has the fixpoint loop"         "grep -qF 'fixpoint loop' espalier/pipeline.md"
  check "pipeline.md writes the Reviewed-Diff cert" "grep -qF 'Reviewed-Diff' espalier/pipeline.md"
  check "espalier-fix has the fixpoint loop"        "grep -qF 'fixpoint loop' espalier/skills/espalier-fix/SKILL.md"
  check "reviewer has the Re-review Rounds section" "grep -qF '## Re-review Rounds' espalier/agents/harness-reviewer.md"
  check "push gate has the certificate check"       "grep -qF 'Reviewed-Diff:' espalier/hooks/pre-push-gate.sh"
  echo ""
  echo "  Verification: $pass passed, $fail failed"
  [ "$fail" -eq 0 ] || exit 1
fi

# --- Summary -----------------------------------------------------------------

echo ""
echo "Upgrade complete. v0.8.2 makes code review a fixpoint loop: every coder fix"
echo "is re-reviewed until a fresh review of the current code is clean, and the push"
echo "gate blocks unless the pushed code matches the fingerprint the last review saw."
echo ""

if [ -n "$BACKUPS_MADE" ]; then
  echo "Backups written (pre-existing customisations preserved):"
  printf '%s' "$BACKUPS_MADE" | sed 's/^/  - /'
  echo ""
  echo "Diff each backup against the live file to re-apply any customisation:"
  echo "  diff espalier/<file>.pre-v0.8.2.bak espalier/<file>"
  echo ""
fi

echo "Next steps:"
echo "  1. Review the diff: git diff && git status"
echo "  2. Commit:"
echo "       git add -A"
echo "       git commit -m 'chore: upgrade Espalier to v0.8.2 (re-review fixpoint loop)'"
echo "  3. Try it: run /espalier on a small feat — a P0 in code review now loops"
echo "     coder→reviewer until the current code is clean before tests."
