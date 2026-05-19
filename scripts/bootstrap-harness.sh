#!/bin/bash
# Bootstrap a fresh harness-engineering install (v0.3.0+).
#
# Run from the TARGET project root. Idempotent. Safe to re-run.
#
# Designed to be called by the /harness-engineering skill AFTER the LLM has:
#   1. Captured a Phase 0 squash-merge decision.
#   2. Run Phase 1 (parallel discovery scouts) and synthesized DISCOVERY.
#   3. Written all substitution files (rules, agent.md, harness-coding/testing/review
#      SKILL.md, sub-agents, wiki, pre-push-gate.sh, check-layer-boundaries.sh,
#      per-layer specs) via parallel Write batch.
#
# This script then runs ONE invocation that:
#   - Creates remaining directories (idempotent against existing).
#   - Copies pure-copy templates (pipeline.md, harness-run/harness-fix/
#     harness-requirements SKILL.md, non-substitution hooks).
#   - chmod +x every harness/hooks/*.sh (catches LLM-written hooks too — R10).
#   - Creates symlinks via portable abspath helper (R-extra).
#   - Appends CLAUDE.md harness section (idempotent grep-guard).
#   - Merges .claude/settings.json hooks (Appendix A algorithm).
#   - Persists squash-merge decision + installs post-merge hook if needed.
#   - Appends .gitignore entry for commit-index cache.
#   - Runs 24 validation checks in parallel (R6).
#
# Usage:
#   bash bootstrap-harness.sh --merge-decision=<val> [options]
#
# Required:
#   --merge-decision=<val>   One of: not-needed | installed | fuzzy-allowed |
#                            skip-only | never-ask | ask-later
#
# Options:
#   --project-dir=<path>     Default: $PWD
#   --plugin-dir=<path>      Auto-detect from $HARNESS_PLUGIN_DIR + common locs
#   --lang=<ts|py|go|unsupported>
#                            Boundary-check variant. "unsupported" emits a no-op.
#   --dry-run                Print actions without executing.
#   --yes                    Non-interactive (used by tests + CI smoke).
#   --force                  Override re-run safety check on existing harness/.
#
# Debug flags (not used by normal /harness-engineering flow):
#   --copy-only              Only Stages 1-4 (mkdir + pure-copy + hooks).
#   --wire-only              Only Stages 5-11 (symlinks + wiring + validation).
#   --validate-only          Only Stage 11 (24-check parallel validation).

set -u

# --- Argument parsing --------------------------------------------------------

PROJECT_DIR="$PWD"
PLUGIN_DIR="${HARNESS_PLUGIN_DIR:-}"
LANG_VARIANT="unsupported"
MERGE_DECISION=""
DRY_RUN=no
SKIP_PROMPT=no
FORCE=no
MODE="full"  # full | copy-only | wire-only | validate-only

for arg in "$@"; do
  case "$arg" in
    --project-dir=*)        PROJECT_DIR="${arg#--project-dir=}" ;;
    --plugin-dir=*)         PLUGIN_DIR="${arg#--plugin-dir=}" ;;
    --lang=*)               LANG_VARIANT="${arg#--lang=}" ;;
    --merge-decision=*)     MERGE_DECISION="${arg#--merge-decision=}" ;;
    --dry-run)              DRY_RUN=yes ;;
    --yes)                  SKIP_PROMPT=yes ;;
    --force)                FORCE=yes ;;
    --copy-only)            MODE="copy-only" ;;
    --wire-only)            MODE="wire-only" ;;
    --validate-only)        MODE="validate-only" ;;
    -h|--help)
      sed -n '2,49p' "$0"
      exit 0
      ;;
    *)
      echo "ERROR: unknown flag: $arg (use --help)" >&2
      exit 2
      ;;
  esac
done

# --- Helpers -----------------------------------------------------------------

run() {
  if [ "$DRY_RUN" = "yes" ]; then
    echo "[dry-run] $*"
  else
    eval "$@"
  fi
}

# R-extra: portable abspath (no realpath dependency — macOS lacks it by default)
abspath() {
  if [ -d "$1" ]; then
    ( cd "$1" && pwd )
  else
    ( cd "$(dirname "$1")" 2>/dev/null && echo "$(pwd)/$(basename "$1")" )
  fi
}

safe_ln() {
  local src="$1" dst="$2"
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    echo "ERROR: $dst exists as regular file (not symlink). Refusing to overwrite user content." >&2
    echo "Move/remove it manually, then re-run." >&2
    exit 1
  fi
  if [ "$DRY_RUN" = "yes" ]; then
    echo "[dry-run] ln -sf \"$src\" \"$dst\""
  else
    ln -sf "$src" "$dst"
  fi
}

log() { echo "[bootstrap] $*"; }

# --- Stage 1: Preflight + re-run detection -----------------------------------

cd "$PROJECT_DIR" || { echo "ERROR: cannot cd to $PROJECT_DIR" >&2; exit 1; }

# Auto-detect plugin dir if not given
if [ -z "$PLUGIN_DIR" ]; then
  for candidate in \
    "$HOME/.claude/plugins/harness-engineering" \
    "$HOME/repos/harness-engineering" \
    "$HOME/SBM_Projects/harness-engineering"; do
    if [ -d "$candidate/skills/harness-engineering/hook-templates" ]; then
      PLUGIN_DIR="$candidate/skills/harness-engineering"
      break
    fi
    if [ -d "$candidate/hook-templates" ]; then
      PLUGIN_DIR="$candidate"
      break
    fi
  done
fi

if [ -z "$PLUGIN_DIR" ] || [ ! -d "$PLUGIN_DIR/hook-templates" ]; then
  echo "ERROR: --plugin-dir not found. Set HARNESS_PLUGIN_DIR or pass --plugin-dir=<path>" >&2
  echo "Expected: <path>/hook-templates/post-merge-backlink.sh" >&2
  exit 1
fi

# Re-run detection (only blocks in full mode; debug modes bypass).
# Signals:
#   .merge-hook-decision present → complete install, re-run = validate only
#   .claude/skills/harness-* symlink exists AND no decision file → v0.1.x install
#   harness/ exists with LLM-written files but NO wiring → fresh install in
#     progress (Phase 2 writes complete, Phase 3 hasn't wired yet) → proceed
if [ "$MODE" = "full" ] && [ "$FORCE" != "yes" ]; then
  if [ -f "harness/.merge-hook-decision" ]; then
    log "Existing complete install detected (harness/.merge-hook-decision present)."
    log "Running validation only (Stage 11). Pass --force to redo install."
    MODE="validate-only"
  elif [ -L ".claude/skills/harness-coding" ] || [ -L ".claude/rules/harness-structure.md" ]; then
    echo "ERROR: v0.1.x install detected (wired symlinks present but no .merge-hook-decision)." >&2
    echo "Run /harness-migrate first, or use --force to bypass." >&2
    exit 1
  fi
  # Else: harness/ may exist with partial LLM writes — proceed (fresh install).
fi

# Validate --merge-decision (required for full and wire-only)
case "$MODE" in
  full|wire-only)
    case "$MERGE_DECISION" in
      not-needed|installed|fuzzy-allowed|skip-only|never-ask|ask-later) ;;
      "")
        echo "ERROR: --merge-decision=<val> required for mode '$MODE'" >&2
        echo "Valid: not-needed | installed | fuzzy-allowed | skip-only | never-ask | ask-later" >&2
        exit 1
        ;;
      *)
        echo "ERROR: invalid --merge-decision='$MERGE_DECISION'" >&2
        echo "Valid: not-needed | installed | fuzzy-allowed | skip-only | never-ask | ask-later" >&2
        exit 1
        ;;
    esac
    ;;
esac

# Validate --lang
case "$LANG_VARIANT" in
  ts|py|go|unsupported) ;;
  *)
    echo "WARNING: unknown --lang='$LANG_VARIANT', falling back to 'unsupported' (no-op hook)" >&2
    LANG_VARIANT=unsupported
    ;;
esac

log "Mode: $MODE | project: $PROJECT_DIR | plugin: $PLUGIN_DIR | lang: $LANG_VARIANT"

# --- Stage 2: Make directories ----------------------------------------------

stage_mkdirs() {
  log "Stage 2: mkdir -p (idempotent)"
  run "mkdir -p harness/rules"
  run "mkdir -p harness/skills/harness-coding/specs"
  run "mkdir -p harness/skills/harness-review"
  run "mkdir -p harness/skills/harness-testing"
  run "mkdir -p harness/skills/harness-requirements"
  run "mkdir -p harness/skills/harness-run"
  run "mkdir -p harness/skills/harness-fix"
  run "mkdir -p harness/agents"
  run "mkdir -p harness/hooks"
  run "mkdir -p harness/wiki"
  run "mkdir -p harness/changes/_template"
  run "mkdir -p harness/changes/feat"
  run "mkdir -p harness/changes/fix"
  run "mkdir -p harness/changes/refactor"
  run "mkdir -p .claude/rules"
  run "mkdir -p .claude/skills"
  run "mkdir -p .claude/agents"
}

# --- Stage 3: Pure-copy templates -------------------------------------------

stage_pure_copy() {
  log "Stage 3: cp pure-copy templates"
  # Pure copies — LLM never writes these (no placeholders).
  # NOTE: harness-review.md is NOT pure-copy (has {project} placeholder).
  run "cp '$PLUGIN_DIR/templates/pipeline.md' harness/pipeline.md"
  run "cp '$PLUGIN_DIR/templates/skills/harness-run.md' harness/skills/harness-run/SKILL.md"
  run "cp '$PLUGIN_DIR/templates/skills/harness-fix.md' harness/skills/harness-fix/SKILL.md"
  run "cp '$PLUGIN_DIR/templates/skills/harness-requirements.md' harness/skills/harness-requirements/SKILL.md"
}

# --- Stage 4: Hooks (non-substitution subset) + chmod-glob (R10) ------------

stage_hooks() {
  log "Stage 4: cp non-substitution hooks + chmod glob (R10)"
  run "cp '$PLUGIN_DIR/hook-templates/post-edit-wrapper.sh' harness/hooks/post-edit-wrapper.sh"
  run "cp '$PLUGIN_DIR/hook-templates/pre-push-gate-wrapper.sh' harness/hooks/pre-push-gate-wrapper.sh"
  run "cp '$PLUGIN_DIR/hook-templates/post-merge-backlink.sh' harness/hooks/post-merge-backlink.sh"
  run "cp '$PLUGIN_DIR/hook-templates/lookup-helpers.sh' harness/hooks/lookup-helpers.sh"
  run "cp '$PLUGIN_DIR/hook-templates/rebuild-commit-index.sh' harness/hooks/rebuild-commit-index.sh"
  # R10 — chmod every *.sh in harness/hooks/ (catches LLM-written pre-push-gate.sh
  # and check-layer-boundaries.sh from Phase 2-7 Write batch).
  if [ "$DRY_RUN" = "yes" ]; then
    echo "[dry-run] chmod +x harness/hooks/*.sh"
  else
    for hook in harness/hooks/*.sh; do
      [ -f "$hook" ] && chmod +x "$hook"
    done
  fi
}

# --- Stage 5: Symlinks ------------------------------------------------------

stage_symlinks() {
  log "Stage 5: symlinks into .claude/ (safe + portable abspath)"
  # chmod-glob also runs here (idempotent) so wire-only mode picks up
  # LLM-written hooks. Full mode already chmodded in Stage 4 — harmless re-chmod.
  if [ "$DRY_RUN" != "yes" ]; then
    for hook in harness/hooks/*.sh; do
      [ -f "$hook" ] && chmod +x "$hook" 2>/dev/null || true
    done
  fi
  safe_ln "$(abspath harness/rules/engineering-structure.md)" .claude/rules/harness-structure.md
  safe_ln "$(abspath harness/rules/coding-standards.md)"      .claude/rules/harness-standards.md
  safe_ln "$(abspath harness/rules/development-process.md)"   .claude/rules/harness-process.md
  for s in harness-coding harness-review harness-testing harness-requirements harness-run harness-fix; do
    safe_ln "$(abspath "harness/skills/$s")" ".claude/skills/$s"
  done
  safe_ln "$(abspath harness/agents/harness-coder.md)"    .claude/agents/harness-coder.md
  safe_ln "$(abspath harness/agents/harness-reviewer.md)" .claude/agents/harness-reviewer.md
}

# --- Stage 6: pipeline-state.md template heredoc ----------------------------

stage_state_template() {
  log "Stage 6: pipeline-state.md template"
  if [ "$DRY_RUN" = "yes" ]; then
    echo "[dry-run] write harness/changes/_template/pipeline-state.md"
    return
  fi
  cat > harness/changes/_template/pipeline-state.md << 'STATETMPL'
# Pipeline State: {requirement}

## Status
- Current Stage: 0
- Started: {timestamp}
- Last Updated: {timestamp}
- Total Rollbacks: 0
- Review Rounds: req=0/3, code=0/2, test=0/2

## Stage History
| Stage | Status | Timestamp | Notes |
|-------|--------|-----------|-------|
STATETMPL
}

# --- Stage 7: CLAUDE.md append ----------------------------------------------

stage_claudemd() {
  log "Stage 7: CLAUDE.md append (idempotent grep-guard)"
  if [ -f CLAUDE.md ] && grep -q "## Harness Engineering" CLAUDE.md 2>/dev/null; then
    log "  CLAUDE.md already has Harness section — skipping"
    return
  fi
  if [ "$DRY_RUN" = "yes" ]; then
    echo "[dry-run] append harness section to CLAUDE.md"
    return
  fi
  cat >> CLAUDE.md << 'CLAUDETMPL'

## Harness Engineering

This project uses a Harness Engineering system for AI code quality.

**Always-loaded rules** are symlinked in .claude/rules/harness-*.md

**For any implementation work**, use `/harness-run` to execute the full pipeline.

**Agent definition:** Read `harness/agent.md` for your operating instructions.

**Key principle:** The coder agent and reviewer agent are ALWAYS separate.
Never review your own code in the same invocation that wrote it.
CLAUDETMPL
}

# --- Stage 8: .claude/settings.json merge (Appendix A algorithm) ------------

stage_settings_json() {
  log "Stage 8: .claude/settings.json merge"
  if [ "$DRY_RUN" = "yes" ]; then
    echo "[dry-run] merge .claude/settings.json (Appendix A algorithm)"
    return
  fi

  # Backup existing
  if [ -f .claude/settings.json ]; then
    cp .claude/settings.json ".claude/settings.json.harness-backup-$(date +%s)"
    # Rotate — keep last 5
    ls -t .claude/settings.json.harness-backup-* 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null || true
  fi

  python3 - << 'PYMERGE'
import json
import os
import sys
import tempfile

SETTINGS = ".claude/settings.json"

HARNESS_HOOKS = {
    "PostToolUse": [
        {
            "matcher": "Write|Edit",
            "hooks": [{
                "type": "command",
                "command": 'bash "$CLAUDE_PROJECT_DIR/harness/hooks/post-edit-wrapper.sh"',
                "timeout": 10
            }]
        }
    ],
    "PreToolUse": [
        {
            "matcher": "Bash",
            "hooks": [{
                "type": "command",
                "command": 'bash "$CLAUDE_PROJECT_DIR/harness/hooks/pre-push-gate-wrapper.sh"',
                "timeout": 30
            }]
        }
    ]
}

def has_matching_entry(existing_entries, new_entry):
    """True if any existing entry shares matcher AND any command with new_entry."""
    new_commands = {h.get("command") for h in new_entry.get("hooks", [])}
    for e in existing_entries:
        if e.get("matcher") != new_entry.get("matcher"):
            continue
        existing_commands = {h.get("command") for h in e.get("hooks", [])}
        if new_commands & existing_commands:
            return True
    return False

if not os.path.exists(SETTINGS):
    data = {"hooks": HARNESS_HOOKS}
    mode = "wrote-fresh"
else:
    try:
        with open(SETTINGS) as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        print(f"ERROR: .claude/settings.json is invalid JSON: {e}", file=sys.stderr)
        sys.exit(1)

    if "hooks" not in data or not isinstance(data["hooks"], dict):
        data["hooks"] = {}

    added = 0
    for event, new_entries in HARNESS_HOOKS.items():
        existing = data["hooks"].setdefault(event, [])
        for new_entry in new_entries:
            if has_matching_entry(existing, new_entry):
                continue
            existing.append(new_entry)
            added += 1
    mode = f"merged (added {added} new entries)" if added else "merged (no changes — already present)"

# Atomic write
dirname = os.path.dirname(SETTINGS) or "."
fd, tmp = tempfile.mkstemp(dir=dirname, suffix=".tmp", prefix=".settings-")
try:
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    # Validate before rename
    with open(tmp) as f:
        json.load(f)
    os.replace(tmp, SETTINGS)
    print(f"[bootstrap]   settings.json: {mode}")
except Exception as e:
    os.unlink(tmp)
    print(f"ERROR: failed to write settings.json: {e}", file=sys.stderr)
    sys.exit(1)
PYMERGE
}

# --- Stage 9: Squash-merge decision + post-merge hook -----------------------

stage_merge_decision() {
  log "Stage 9: merge decision = $MERGE_DECISION"
  if [ "$DRY_RUN" = "yes" ]; then
    echo "[dry-run] write harness/.merge-hook-decision = $MERGE_DECISION"
    [ "$MERGE_DECISION" = "installed" ] && echo "[dry-run] install post-merge hook"
    return
  fi

  echo "$MERGE_DECISION" > harness/.merge-hook-decision

  if [ "$MERGE_DECISION" != "installed" ]; then
    log "  Hook install skipped (decision=$MERGE_DECISION)"
    return
  fi

  # Detect husky
  HUSKY_PRESENT=no
  if [ -d ".husky" ]; then
    if [ -f ".husky/_/husky.sh" ] || [ -f ".husky/install.mjs" ]; then
      HUSKY_PRESENT=yes
    elif [ -f package.json ] && grep -q '"husky"' package.json 2>/dev/null; then
      HUSKY_PRESENT=yes
    fi
  fi

  if [ "$HUSKY_PRESENT" = "yes" ]; then
    HOOK_DST=".husky/post-merge"
  else
    HOOK_DST=".git/hooks/post-merge"
  fi

  HOOK_SRC="harness/hooks/post-merge-backlink.sh"

  if [ ! -d "$(dirname "$HOOK_DST")" ]; then
    log "  ERROR: $(dirname "$HOOK_DST") does not exist (run 'git init' first?)"
    return
  fi

  if [ -f "$HOOK_DST" ] && grep -q "HARNESS_BACKLINK_HOOK" "$HOOK_DST" 2>/dev/null; then
    log "  Post-merge hook already installed"
  elif [ -f "$HOOK_DST" ]; then
    echo "" >> "$HOOK_DST"
    cat "$HOOK_SRC" >> "$HOOK_DST"
    chmod +x "$HOOK_DST"
    log "  Appended harness section to existing $HOOK_DST"
  else
    cp "$HOOK_SRC" "$HOOK_DST"
    chmod +x "$HOOK_DST"
    log "  Installed $HOOK_DST"
  fi
}

# --- Stage 10: .gitignore append --------------------------------------------

stage_gitignore() {
  log "Stage 10: .gitignore append (idempotent + newline guard)"
  if [ "$DRY_RUN" = "yes" ]; then
    echo "[dry-run] append 'harness/.commit-index.tsv' to .gitignore"
    return
  fi
  if grep -qxF "harness/.commit-index.tsv" .gitignore 2>/dev/null; then
    log "  .gitignore already has entry — skipping"
    return
  fi
  if [ -s .gitignore ] && [ -n "$(tail -c1 .gitignore)" ]; then
    printf '\n' >> .gitignore
  fi
  echo "harness/.commit-index.tsv" >> .gitignore
}

# --- Stage 11: Validation (parallel — R6) -----------------------------------

stage_validate() {
  log "Stage 11: validation (24 checks in parallel — R6)"
  if [ "$DRY_RUN" = "yes" ]; then
    echo "[dry-run] would run 24 parallel validation checks (skipped — nothing to validate yet)"
    return 0
  fi

  local tmpdir
  tmpdir=$(mktemp -d -t harness-validate.XXXXXX)
  local failed=0

  run_check() {
    local n=$1 check_name=$2 cmd=$3
    local idx
    idx=$(printf '%02d' "$n")
    # Subshell isolates eval — prevents (a) variable bleed-back (loop vars
    # like $name leaking into outer scope), (b) `exit` inside cmd killing
    # the run_check function.
    if ( eval "$cmd" ) >/dev/null 2>&1; then
      echo "[$n/24] OK   $check_name" > "$tmpdir/$idx"
    else
      local err
      err=$( ( eval "$cmd" ) 2>&1 | head -1 )
      echo "[$n/24] FAIL $check_name: $err" > "$tmpdir/$idx"
      echo "fail" > "$tmpdir/$idx.fail"
    fi
  }

  run_check  1 "rules-load"          'ls .claude/rules/harness-*.md' &
  run_check  2 "skills-load"         'ls -d .claude/skills/harness-coding .claude/skills/harness-review .claude/skills/harness-testing .claude/skills/harness-requirements .claude/skills/harness-run .claude/skills/harness-fix' &
  run_check  3 "agents-load"         'ls .claude/agents/harness-coder.md .claude/agents/harness-reviewer.md' &
  run_check  4 "hooks-configured"    'grep -q "harness/hooks" .claude/settings.json' &
  run_check  5 "symlinks-valid"      '[ -L .claude/rules/harness-structure.md ] && [ -e .claude/rules/harness-structure.md ]' &
  run_check  6 "hooks-executable"    'test -x harness/hooks/post-edit-wrapper.sh && test -x harness/hooks/pre-push-gate.sh && test -x harness/hooks/pre-push-gate-wrapper.sh' &
  run_check  7 "state-template"      'test -f harness/changes/_template/pipeline-state.md' &
  run_check  8 "claudemd-updated"    'grep -q "## Harness Engineering" CLAUDE.md' &
  run_check  9 "harness-agent-md"    'test -f harness/agent.md' &
  run_check 10 "harness-pipeline-md" 'test -f harness/pipeline.md' &
  run_check 11 "skill-name-parity"   'for f in harness/skills/*/SKILL.md; do dir=$(basename $(dirname "$f")); name=$(grep "^name:" "$f" | awk "{print \$2}"); [ "$dir" = "$name" ] || exit 1; done' &
  run_check 12 "typed-changes-dirs"  '[ -d harness/changes/feat ] && [ -d harness/changes/fix ] && [ -d harness/changes/refactor ]' &
  run_check 13 "harness-fix-skill"   'test -f .claude/skills/harness-fix/SKILL.md' &
  run_check 14 "harness-fix-name"    'grep -q "^name: harness-fix" .claude/skills/harness-fix/SKILL.md' &
  run_check 15 "rules-engineering"   'test -f harness/rules/engineering-structure.md' &
  run_check 16 "rules-standards"     'test -f harness/rules/coding-standards.md' &
  run_check 17 "merge-decision"      'grep -qE "^(not-needed|installed|fuzzy-allowed|skip-only|never-ask|ask-later)$" harness/.merge-hook-decision' &
  run_check 18 "hook-template-copy"  'test -f harness/hooks/post-merge-backlink.sh && test -x harness/hooks/post-merge-backlink.sh' &
  run_check 19 "lookup-helpers"      'test -f harness/hooks/lookup-helpers.sh' &
  run_check 20 "post-merge-installed" '
    DECISION=$(cat harness/.merge-hook-decision 2>/dev/null);
    if [ "$DECISION" = "installed" ]; then
      grep -q HARNESS_BACKLINK_HOOK .git/hooks/post-merge 2>/dev/null || grep -q HARNESS_BACKLINK_HOOK .husky/post-merge 2>/dev/null;
    else
      exit 0;
    fi' &
  run_check 21 "rebuild-script"      'test -x harness/hooks/rebuild-commit-index.sh' &
  run_check 22 "gitignore-cache"     'grep -qxF "harness/.commit-index.tsv" .gitignore' &
  run_check 23 "rebuild-runs"        'bash harness/hooks/rebuild-commit-index.sh && test -f harness/.commit-index.tsv' &
  run_check 24 "cache-tsv-format"    '[ ! -s harness/.commit-index.tsv ] || awk -F"\t" "NF != 4 { exit 1 }" harness/.commit-index.tsv' &

  wait

  # Emit sorted output (deterministic order)
  cat "$tmpdir"/[0-9]* 2>/dev/null

  failed=$(ls "$tmpdir"/*.fail 2>/dev/null | wc -l | tr -d ' ')
  rm -rf "$tmpdir"

  if [ "$failed" -gt 0 ]; then
    log "Validation: $failed/24 FAILED"
    return 1
  fi
  log "Validation: 24/24 passed"
  return 0
}

# --- Stage dispatcher --------------------------------------------------------

case "$MODE" in
  full)
    stage_mkdirs
    stage_pure_copy
    stage_hooks
    stage_symlinks
    stage_state_template
    stage_claudemd
    stage_settings_json
    stage_merge_decision
    stage_gitignore
    stage_validate
    ;;
  copy-only)
    stage_mkdirs
    stage_pure_copy
    stage_hooks
    log "copy-only mode — stopping after Stage 4"
    ;;
  wire-only)
    stage_symlinks
    stage_state_template
    stage_claudemd
    stage_settings_json
    stage_merge_decision
    stage_gitignore
    stage_validate
    ;;
  validate-only)
    stage_validate
    ;;
esac

EXIT_CODE=$?

if [ "$DRY_RUN" = "yes" ]; then
  log "Dry-run complete. No changes made."
fi

exit $EXIT_CODE
