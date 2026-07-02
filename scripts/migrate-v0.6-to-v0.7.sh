#!/bin/bash
# Migrate an Espalier v0.6.x target repo to v0.7.0 (read-only /espalier-ask lane).
#
# Run from the TARGET project root. Idempotent. Safe to re-run.
# Use --dry-run to preview every change before applying.
#
# v0.7.0 adds the espalier-ask skill — a read-only Q&A lane that answers
# "how / where / why / what-changed" questions from the espalier/ wiki, rules,
# and change history first (verified against code), falling back to a codebase
# search. It is purely additive: no pipeline stage, no gate. This migration:
#   1. Backs up any user-customised pure-copy pipeline file (diff vs the v0.7
#      template) to <file>.pre-v0.7.bak — bootstrap --force re-copies ALL of
#      them, so a customisation would otherwise be lost.
#   2. Runs bootstrap-espalier.sh --force — creates the espalier-ask skill
#      directory, copies the new SKILL.md, and symlinks
#      .claude/skills/espalier-ask. (bootstrap also re-copies the other
#      pure-copy skills; none changed in v0.7.)
#   3. Patches CLAUDE.md and espalier/agent.md to mention /espalier-ask —
#      bootstrap's CLAUDE.md writer is append-once (skips an existing
#      ## Espalier section) and never touches the per-project agent.md.
#   4. Verifies the result.
#
# What this script does NOT do:
#   - Touch espalier/rules/*, espalier/wiki/*, espalier/changes/*, or any
#     LLM-substituted hook — none changed in v0.7.
#   - Change any existing pipeline behaviour. /espalier and /espalier-fix are
#     untouched.
#
# Usage:
#   bash migrate-v0.6-to-v0.7.sh [--dry-run] [--yes] [--plugin-dir=<path>]

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
      sed -n '2,30p' "$0"
      exit 0
      ;;
    *)
      echo "ERROR: unknown flag: $arg (use --help)" >&2
      exit 2
      ;;
  esac
done

log() { echo "[migrate v0.6→v0.7] $*"; }

# In-place edit helpers ------------------------------------------------------

# insert_after FILE ANCHOR INSERT — insert INSERT immediately after the FIRST
# line that CONTAINS the fixed string ANCHOR. INSERT may contain newlines.
# Fixed-string match (grep -F / awk index) — no regex escaping. Returns 1 if
# the anchor is not found (caller decides whether that is fatal).
#
# INSERT is staged through a temp file and emitted with getline, NOT passed via
# `awk -v`: BSD/macOS awk rejects a literal newline inside a -v value
# ("awk: newline in string"), so a multi-line -v insert silently fails there.
insert_after() {
  local file="$1" anchor="$2" text="$3"
  grep -qF "$anchor" "$file" 2>/dev/null || return 1
  local insf; insf=$(mktemp) || return 2
  printf '%s\n' "$text" > "$insf"
  local tmp; tmp=$(mktemp "${file}.XXXXXX") || { rm -f "$insf"; return 2; }
  awk -v anchor="$anchor" -v insf="$insf" '
    { print }
    index($0, anchor) && !done {
      while ((getline line < insf) > 0) print line
      close(insf)
      done=1
    }
  ' "$file" > "$tmp"
  local rc=$?
  [ "$rc" -eq 0 ] && mv "$tmp" "$file" || rm -f "$tmp"
  rm -f "$insf"
  return $rc
}

# --- Preflight ---------------------------------------------------------------

if [ -d "harness" ] && [ ! -d "espalier" ]; then
  echo "ERROR: this is a pre-v0.4 install (harness/ present, no espalier/)." >&2
  echo "Run /espalier-migrate to apply the earlier migrations first." >&2
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

# v0.6 prerequisite — the grill skill must already be present.
if [ ! -f "espalier/skills/espalier-grill/SKILL.md" ]; then
  echo "ERROR: install looks pre-v0.6 (espalier-grill skill missing)." >&2
  echo "Run /espalier-migrate to apply the v0.5→v0.6 upgrade first." >&2
  exit 1
fi

# Already-v0.7 detector — the ask skill is present.
if [ -f "espalier/skills/espalier-ask/SKILL.md" ]; then
  echo "Already on v0.7.0 (espalier-ask skill present)."
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

# Sanity-check the plugin actually contains v0.7 assets before we touch anything.
if [ ! -f "$PLUGIN_INIT/templates/skills/espalier-ask.md" ]; then
  echo "ERROR: plugin at $PLUGIN_DIR is pre-v0.7 (no templates/skills/espalier-ask.md)." >&2
  echo "Update the plugin to v0.7+ (or pass --plugin-dir to a v0.7 checkout)." >&2
  exit 1
fi

cat << EOF

Espalier read-only ask lane upgrade (v0.6.x → v0.7.0)

Plan:
  1. Backup-on-diff: any user-customised pure-copy pipeline file → <file>.pre-v0.7.bak
  2. bootstrap-espalier.sh --force  (merge-decision=$DECISION, doctor-cadence=$DOCTOR_CADENCE)
       → new espalier-ask skill + .claude/skills/espalier-ask link
  3. Patch CLAUDE.md + espalier/agent.md to mention /espalier-ask
  4. Verify

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

# --- Step 1: backup-on-diff --------------------------------------------------
#
# bootstrap --force re-copies EVERY pure-copy file unconditionally, even the
# ones v0.7 did not change. If a user (or a prior LLM run) customised any of
# them, that customisation is lost. For each file we compare current content to
# the v0.7 template; if they differ, copy the current file aside to
# <file>.pre-v0.7.bak BEFORE bootstrap runs. Identical files (clean install)
# need no backup.

log "Step 1: backup-on-diff for pure-copy pipeline files"
BACKUPS_MADE=""

backup_if_differs() {
  local current="$1"
  local new_template="$2"
  if [ ! -f "$current" ]; then
    return 0
  fi
  if [ ! -f "$new_template" ]; then
    echo "  WARN: plugin template missing: $new_template (skipping backup check)" >&2
    return 0
  fi
  if cmp -s "$current" "$new_template"; then
    echo "  unchanged: $current (no backup needed)"
    return 0
  fi
  local backup="${current}.pre-v0.7.bak"
  if [ "$DRY_RUN" = "yes" ]; then
    echo "  [dry-run] backup: $current → $backup"
  else
    cp "$current" "$backup"
    echo "  backed up: $current → $backup"
  fi
  BACKUPS_MADE="${BACKUPS_MADE}${backup}
"
}

backup_if_differs "espalier/pipeline.md"                              "$PLUGIN_INIT/templates/pipeline.md"
backup_if_differs "espalier/skills/espalier/SKILL.md"                 "$PLUGIN_INIT/templates/skills/espalier.md"
backup_if_differs "espalier/skills/espalier-fix/SKILL.md"             "$PLUGIN_INIT/templates/skills/espalier-fix.md"
backup_if_differs "espalier/skills/espalier-requirements/SKILL.md"    "$PLUGIN_INIT/templates/skills/espalier-requirements.md"
backup_if_differs "espalier/skills/espalier-grill/SKILL.md"           "$PLUGIN_INIT/templates/skills/espalier-grill.md"
backup_if_differs "espalier/skills/espalier-prune/SKILL.md"           "$PLUGIN_INIT/templates/skills/espalier-prune.md"
backup_if_differs "espalier/skills/espalier-doctor/SKILL.md"          "$PLUGIN_INIT/templates/skills/espalier-doctor.md"

# --- Step 2: bootstrap --force (mechanical 100%) -----------------------------
#
# Bootstrap stages relevant to v0.7:
#   Stage 2: mkdir espalier/skills/espalier-ask
#   Stage 3: cp templates/skills/espalier-ask.md → espalier/skills/espalier-ask/SKILL.md
#   Stage 5: symlink .claude/skills/espalier-ask → espalier/skills/espalier-ask

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

# --- Step 3: patch CLAUDE.md + agent.md --------------------------------------
#
# bootstrap's CLAUDE.md writer is append-once (it skips when ## Espalier
# already exists), and it never touches the per-project espalier/agent.md.
# A migrated install therefore needs both files patched here.

CLAUDE_LINE='**For questions** ("how does X work", "where is Y"), use `/espalier-ask <question>` — read-only, answers from espalier/ docs first.'
ASK_ROW='| Ask      | espalier/skills/espalier-ask/ | Read-only Q&A over espalier/ docs | Via /espalier-ask |'

log "Step 3: patch CLAUDE.md + espalier/agent.md"

# CLAUDE.md — insert the questions bullet after the bug-fixes bullet.
if [ -f CLAUDE.md ]; then
  if grep -qF "/espalier-ask" CLAUDE.md; then
    echo "  CLAUDE.md already mentions /espalier-ask — skipping"
  elif ! grep -qF "## Espalier" CLAUDE.md; then
    echo "  CLAUDE.md has no ## Espalier section — skipping (user removed it?)"
  elif [ "$DRY_RUN" = "yes" ]; then
    echo "  [dry-run] insert /espalier-ask bullet into CLAUDE.md after the bug-fixes line"
  else
    # Leading newline → a blank line before the bullet (matches heredoc spacing).
    if insert_after CLAUDE.md "**For bug fixes**" "$(printf '\n%s' "$CLAUDE_LINE")"; then
      echo "  patched CLAUDE.md"
    else
      echo "  WARN: couldn't find the '**For bug fixes**' line in CLAUDE.md — patch skipped" >&2
    fi
  fi
else
  echo "  no CLAUDE.md — skipping"
fi

# agent.md — insert the Ask row after the Fix row in the config-index table.
AGENT="espalier/agent.md"
if [ -f "$AGENT" ]; then
  if grep -qF "/espalier-ask" "$AGENT"; then
    echo "  $AGENT already mentions /espalier-ask — skipping"
  elif [ "$DRY_RUN" = "yes" ]; then
    echo "  [dry-run] insert the Ask row into $AGENT after the Fix row"
  else
    if insert_after "$AGENT" "Via /espalier-fix |" "$ASK_ROW"; then
      echo "  patched $AGENT"
    else
      echo "  WARN: couldn't find the Fix row in $AGENT — patch skipped (table customised?)" >&2
    fi
  fi
else
  echo "  no $AGENT — skipping"
fi

# --- Step 4: verification ----------------------------------------------------

log "Step 4: verification"
if [ "$DRY_RUN" = "yes" ]; then
  echo "(dry run — skipping verification)"
else
  pass=0; fail=0; warn=0
  check() {
    if eval "$2" >/dev/null 2>&1; then pass=$((pass+1)); echo "  ✓ $1"
    else fail=$((fail+1)); echo "  ✗ $1"; fi
  }
  warn_check() {
    if eval "$2" >/dev/null 2>&1; then pass=$((pass+1)); echo "  ✓ $1"
    else warn=$((warn+1)); echo "  ! $1 (warn-only)"; fi
  }
  check "espalier-ask skill present"        "test -f espalier/skills/espalier-ask/SKILL.md"
  check ".claude/skills/espalier-ask link"  "test -L .claude/skills/espalier-ask"
  check "ask skill name parity"             "grep -q '^name: espalier-ask' espalier/skills/espalier-ask/SKILL.md"
  warn_check "CLAUDE.md mentions /espalier-ask"  "grep -qF '/espalier-ask' CLAUDE.md"
  warn_check "agent.md mentions /espalier-ask"   "grep -qF '/espalier-ask' espalier/agent.md"
  echo ""
  echo "  Verification: $pass passed, $fail failed, $warn warn-only"
  [ "$fail" -gt 0 ] && exit 1
fi

# --- Summary -----------------------------------------------------------------

echo ""
echo "Upgrade complete. v0.7 adds /espalier-ask — a read-only Q&A lane that"
echo "answers from your espalier/ docs first, verified against code."
echo ""

if [ -n "$BACKUPS_MADE" ]; then
  echo "Backups written (pre-existing customisations preserved):"
  printf '%s' "$BACKUPS_MADE" | sed 's/^/  - /'
  echo ""
  echo "Diff each backup against the live file to re-apply any customisation:"
  echo "  diff espalier/<file>.pre-v0.7.bak espalier/<file>"
  echo ""
fi

echo "Next steps:"
echo "  1. Review the diff: git diff && git status"
echo "  2. Commit:"
echo "       git add -A"
echo "       git commit -m 'chore: upgrade Espalier to v0.7.0 (/espalier-ask lane)'"
echo "  3. Try it: /espalier-ask how does <some feature> work"
