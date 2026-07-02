#!/bin/bash
# Bootstrap a fresh Espalier install (v0.4.0+).
#
# Run from the TARGET project root. Idempotent. Safe to re-run.
#
# Designed to be called by the /espalier-init skill AFTER the LLM has:
#   1. Captured a Phase 0 squash-merge decision.
#   2. Run Phase 1 (parallel discovery scouts) and synthesized DISCOVERY.
#   3. Written all substitution files (rules incl. security-standards, agent.md,
#      espalier-coding/testing/review/security SKILL.md, sub-agents incl.
#      harness-security, wiki, pre-push-gate.sh, check-layer-boundaries.sh,
#      per-layer specs) via parallel Write batch.
#
# This script then runs ONE invocation that:
#   - Creates remaining directories (idempotent against existing).
#   - Copies pure-copy templates (pipeline.md, espalier, espalier-fix,
#     espalier-requirements, espalier-grill, espalier-prune, espalier-doctor,
#     espalier-ask, espalier-audit SKILL.md + hooks).
#   - chmod +x every espalier/hooks/*.sh (catches LLM-written hooks too — R10).
#   - Creates symlinks via portable abspath helper (R-extra).
#   - Appends CLAUDE.md Espalier section (idempotent grep-guard).
#   - Merges .claude/settings.json hooks (Appendix A algorithm).
#   - Persists squash-merge decision + installs the post-merge dispatcher.
#   - Appends .gitignore entries for the commit-index + drift sidecars.
#   - Runs 37 validation checks (R6).
#
# Usage:
#   bash bootstrap-espalier.sh --merge-decision=<val> [options]
#
# Required:
#   --merge-decision=<val>   One of: not-needed | installed | fuzzy-allowed |
#                            skip-only | never-ask | ask-later
#
# Options:
#   --project-dir=<path>     Default: $PWD
#   --plugin-dir=<path>      Auto-detect from $ESPALIER_PLUGIN_DIR (or legacy
#                            $HARNESS_PLUGIN_DIR) + common locations.
#   --lang=<ts|py|go|unsupported>
#                            Boundary-check variant. "unsupported" emits a no-op.
#   --doctor-cadence=<val>   every-change | weekly | monthly | manual (default: weekly).
#   --dry-run                Print actions without executing.
#   --yes                    Non-interactive (used by tests + CI smoke).
#   --force                  Override re-run safety check on existing espalier/.
#
# Debug flags (not used by normal /espalier-init flow):
#   --copy-only              Only Stages 1-4 (mkdir + pure-copy + hooks).
#   --wire-only              Only Stages 5-11 (symlinks + wiring + validation).
#   --validate-only          Only Stage 11 (37-check validation).
#   --ignore-drift           Skip check #25's hard fail on expired (>90d) drift.
#   --ignore-drift-reason=<s> Audit reason recorded with --ignore-drift.

set -u

# --- Argument parsing --------------------------------------------------------

PROJECT_DIR="$PWD"
PLUGIN_DIR="${ESPALIER_PLUGIN_DIR:-${HARNESS_PLUGIN_DIR:-}}"
LANG_VARIANT="unsupported"
MERGE_DECISION=""
DRY_RUN=no
SKIP_PROMPT=no
FORCE=no
IGNORE_DRIFT=no
IGNORE_DRIFT_REASON=""
DOCTOR_CADENCE=weekly
MODE="full"  # full | copy-only | wire-only | validate-only

for arg in "$@"; do
  case "$arg" in
    --project-dir=*)        PROJECT_DIR="${arg#--project-dir=}" ;;
    --plugin-dir=*)         PLUGIN_DIR="${arg#--plugin-dir=}" ;;
    --lang=*)               LANG_VARIANT="${arg#--lang=}" ;;
    --merge-decision=*)     MERGE_DECISION="${arg#--merge-decision=}" ;;
    --doctor-cadence=*)     DOCTOR_CADENCE="${arg#--doctor-cadence=}" ;;
    --dry-run)              DRY_RUN=yes ;;
    --yes)                  SKIP_PROMPT=yes ;;
    --force)                FORCE=yes ;;
    --ignore-drift)         IGNORE_DRIFT=yes ;;
    --ignore-drift-reason=*) IGNORE_DRIFT_REASON="${arg#--ignore-drift-reason=}" ;;
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
    echo "[dry-run] ln -sfn \"$src\" \"$dst\""
  else
    # -n: if dst is already a symlink-to-dir, replace the link itself —
    # without -n, ln dereferences it and nests the new link inside (re-run bug).
    ln -sfn "$src" "$dst"
  fi
}

log() { echo "[bootstrap] $*"; }

# --- Stage 1: Preflight + re-run detection -----------------------------------

cd "$PROJECT_DIR" || { echo "ERROR: cannot cd to $PROJECT_DIR" >&2; exit 1; }

# Auto-detect plugin dir if not given.
# Looks for new (espalier-engineering) AND legacy (harness-engineering) install
# paths so users still on the legacy github repo / clone dir can run v0.4 bootstrap.
if [ -z "$PLUGIN_DIR" ]; then
  for candidate in \
    "$HOME/.claude/plugins/espalier-engineering" \
    "$HOME/.claude/plugins/espalier" \
    "$HOME/.claude/plugins/harness-engineering" \
    "$HOME/repos/espalier-engineering" \
    "$HOME/repos/harness-engineering" \
    "$HOME/SBM_Projects/espalier-engineering" \
    "$HOME/SBM_Projects/harness-engineering"; do
    if [ -d "$candidate/skills/espalier-init/hook-templates" ]; then
      PLUGIN_DIR="$candidate/skills/espalier-init"
      break
    fi
    if [ -d "$candidate/hook-templates" ]; then
      PLUGIN_DIR="$candidate"
      break
    fi
  done
fi

if [ -z "$PLUGIN_DIR" ] || [ ! -d "$PLUGIN_DIR/hook-templates" ]; then
  echo "ERROR: --plugin-dir not found. Set ESPALIER_PLUGIN_DIR or pass --plugin-dir=<path>" >&2
  echo "Expected: <path>/hook-templates/post-merge-backlink.sh" >&2
  exit 1
fi

# Re-run detection (only blocks in full mode; debug modes bypass).
# Signals:
#   espalier/.merge-hook-decision present → complete v0.4 install, re-run = validate only
#   .claude/skills/harness-* symlink exists AND no espalier/ dir → legacy pre-v0.4 install
#   espalier/ exists with LLM-written files but NO wiring → fresh install in
#     progress (Phase 2 writes complete, Phase 3 hasn't wired yet) → proceed
if [ "$MODE" = "full" ] && [ "$FORCE" != "yes" ]; then
  if [ -f "espalier/.merge-hook-decision" ]; then
    log "Existing complete install detected (espalier/.merge-hook-decision present)."
    log "Running validation only (Stage 11). Pass --force to redo install."
    MODE="validate-only"
  elif [ -d "harness" ] && [ -f "harness/.merge-hook-decision" ]; then
    echo "ERROR: v0.3.x install detected (harness/.merge-hook-decision present, no espalier/ dir)." >&2
    echo "Run /espalier-migrate to upgrade harness/ → espalier/ in place." >&2
    exit 1
  elif [ -L ".claude/skills/harness-coding" ] || [ -L ".claude/rules/harness-structure.md" ]; then
    echo "ERROR: legacy v0.1.x install detected (wired symlinks present but no .merge-hook-decision)." >&2
    echo "Run /espalier-migrate first, or use --force to bypass." >&2
    exit 1
  fi
  # Else: espalier/ may exist with partial LLM writes — proceed (fresh install).
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

# Validate --doctor-cadence
case "$DOCTOR_CADENCE" in
  every-change|weekly|monthly|manual) ;;
  *)
    echo "WARNING: unknown --doctor-cadence='$DOCTOR_CADENCE', falling back to 'weekly'" >&2
    DOCTOR_CADENCE=weekly
    ;;
esac

log "Mode: $MODE | project: $PROJECT_DIR | plugin: $PLUGIN_DIR | lang: $LANG_VARIANT"

# Resolve the --ignore-drift audit reason once (prompt only when interactive).
if [ "$IGNORE_DRIFT" = "yes" ] && [ -z "$IGNORE_DRIFT_REASON" ]; then
  if [ "$SKIP_PROMPT" = "no" ] && [ -t 0 ]; then
    printf '[bootstrap] --ignore-drift: reason for ignoring expired drift? '
    read -r IGNORE_DRIFT_REASON
  fi
  [ -z "$IGNORE_DRIFT_REASON" ] && IGNORE_DRIFT_REASON="(no reason given)"
fi

# --- Stage 2: Make directories ----------------------------------------------

stage_mkdirs() {
  log "Stage 2: mkdir -p (idempotent)"
  run "mkdir -p espalier/rules"
  run "mkdir -p espalier/skills/espalier-coding/specs"
  run "mkdir -p espalier/skills/espalier-review"
  run "mkdir -p espalier/skills/espalier-security"
  run "mkdir -p espalier/skills/espalier-testing"
  run "mkdir -p espalier/skills/espalier-requirements"
  run "mkdir -p espalier/skills/espalier-grill"
  run "mkdir -p espalier/skills/espalier"
  run "mkdir -p espalier/skills/espalier-fix"
  run "mkdir -p espalier/skills/espalier-prune"
  run "mkdir -p espalier/skills/espalier-doctor"
  run "mkdir -p espalier/skills/espalier-ask"
  run "mkdir -p espalier/skills/espalier-audit"
  run "mkdir -p espalier/agents"
  run "mkdir -p espalier/hooks"
  run "mkdir -p espalier/wiki"
  run "mkdir -p espalier/changes/_template"
  run "mkdir -p espalier/changes/feat"
  run "mkdir -p espalier/changes/fix"
  run "mkdir -p espalier/changes/refactor"
  run "mkdir -p .claude/rules"
  run "mkdir -p .claude/skills"
  run "mkdir -p .claude/agents"
}

# --- Stage 3: Pure-copy templates -------------------------------------------

stage_pure_copy() {
  log "Stage 3: cp pure-copy templates"
  # Pure copies — LLM never writes these (no placeholders).
  # NOTE: espalier-review.md is NOT pure-copy (has {project} placeholder).
  run "cp '$PLUGIN_DIR/templates/pipeline.md' espalier/pipeline.md"
  run "cp '$PLUGIN_DIR/templates/skills/espalier.md' espalier/skills/espalier/SKILL.md"
  run "cp '$PLUGIN_DIR/templates/skills/espalier-fix.md' espalier/skills/espalier-fix/SKILL.md"
  run "cp '$PLUGIN_DIR/templates/skills/espalier-requirements.md' espalier/skills/espalier-requirements/SKILL.md"
  run "cp '$PLUGIN_DIR/templates/skills/espalier-grill.md' espalier/skills/espalier-grill/SKILL.md"
  run "cp '$PLUGIN_DIR/templates/skills/espalier-prune.md' espalier/skills/espalier-prune/SKILL.md"
  run "cp '$PLUGIN_DIR/templates/skills/espalier-doctor.md' espalier/skills/espalier-doctor/SKILL.md"
  run "cp '$PLUGIN_DIR/templates/skills/espalier-ask.md' espalier/skills/espalier-ask/SKILL.md"
  run "cp '$PLUGIN_DIR/templates/skills/espalier-audit.md' espalier/skills/espalier-audit/SKILL.md"
  # Shared shipped scout prompts — read by /espalier-prune AND /espalier-doctor
  # (single source of truth; a dotfile so it stays out of the way).
  run "cp '$PLUGIN_DIR/templates/scout-prompts.md' espalier/.scout-prompts.md"
}

# --- Stage 4: Hooks (non-substitution subset) + chmod-glob (R10) ------------

stage_hooks() {
  log "Stage 4: cp non-substitution hooks + chmod glob (R10)"
  run "cp '$PLUGIN_DIR/hook-templates/post-edit-wrapper.sh' espalier/hooks/post-edit-wrapper.sh"
  run "cp '$PLUGIN_DIR/hook-templates/pre-push-gate-wrapper.sh' espalier/hooks/pre-push-gate-wrapper.sh"
  run "cp '$PLUGIN_DIR/hook-templates/post-merge-backlink.sh' espalier/hooks/post-merge-backlink.sh"
  run "cp '$PLUGIN_DIR/hook-templates/lookup-helpers.sh' espalier/hooks/lookup-helpers.sh"
  run "cp '$PLUGIN_DIR/hook-templates/rebuild-commit-index.sh' espalier/hooks/rebuild-commit-index.sh"
  run "cp '$PLUGIN_DIR/hook-templates/drift-detect.sh' espalier/hooks/drift-detect.sh"
  run "cp '$PLUGIN_DIR/hook-templates/drift-helpers.sh' espalier/hooks/drift-helpers.sh"
  run "cp '$PLUGIN_DIR/hook-templates/parse-drift-blocks.py' espalier/hooks/parse-drift-blocks.py"
  # R10 — chmod every *.sh in espalier/hooks/ (catches LLM-written pre-push-gate.sh
  # and check-layer-boundaries.sh from Phase 2-7 Write batch).
  if [ "$DRY_RUN" = "yes" ]; then
    echo "[dry-run] chmod +x espalier/hooks/*.sh"
  else
    for hook in espalier/hooks/*.sh; do
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
    for hook in espalier/hooks/*.sh; do
      [ -f "$hook" ] && chmod +x "$hook" 2>/dev/null || true
    done
  fi
  safe_ln "$(abspath espalier/rules/engineering-structure.md)" .claude/rules/espalier-structure.md
  safe_ln "$(abspath espalier/rules/coding-standards.md)"      .claude/rules/espalier-standards.md
  safe_ln "$(abspath espalier/rules/development-process.md)"   .claude/rules/espalier-process.md
  safe_ln "$(abspath espalier/rules/security-standards.md)"    .claude/rules/espalier-security.md
  safe_ln "$(abspath espalier/rules/production-standards.md)"  .claude/rules/espalier-production.md
  for s in espalier-coding espalier-review espalier-security espalier-testing espalier-requirements espalier-grill espalier espalier-fix espalier-prune espalier-doctor espalier-ask espalier-audit; do
    safe_ln "$(abspath "espalier/skills/$s")" ".claude/skills/$s"
  done
  # Sub-agent identifiers intentionally kept as harness-coder / harness-reviewer
  # (see SKILL.md Phase 0 note).
  safe_ln "$(abspath espalier/agents/harness-coder.md)"    .claude/agents/harness-coder.md
  safe_ln "$(abspath espalier/agents/harness-reviewer.md)" .claude/agents/harness-reviewer.md
  safe_ln "$(abspath espalier/agents/harness-security.md)" .claude/agents/harness-security.md
}

# --- Stage 6: pipeline-state.md template heredoc ----------------------------

stage_state_template() {
  log "Stage 6: pipeline-state.md template"
  if [ "$DRY_RUN" = "yes" ]; then
    echo "[dry-run] write espalier/changes/_template/pipeline-state.md"
    return
  fi
  cat > espalier/changes/_template/pipeline-state.md << 'STATETMPL'
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
  if [ -f CLAUDE.md ] && grep -q "## Espalier" CLAUDE.md 2>/dev/null; then
    log "  CLAUDE.md already has Espalier section — skipping"
    return
  fi
  if [ "$DRY_RUN" = "yes" ]; then
    echo "[dry-run] append Espalier section to CLAUDE.md"
    return
  fi
  cat >> CLAUDE.md << 'CLAUDETMPL'

## Espalier

This project uses Espalier for AI code quality — auto-discovered, project-specific guardrails.

**Always-loaded rules** are symlinked in .claude/rules/espalier-*.md

**For any implementation work**, use `/espalier <requirement>` to execute the full pipeline.

**For bug fixes**, use `/espalier-fix <bug>` for the slim 5-stage lane.

**For questions** ("how does X work", "where is Y"), use `/espalier-ask <question>` — read-only, answers from espalier/ docs first.

**For a repo-wide security audit**, use `/espalier-audit` — inventories trust-boundary defects in the existing code to `espalier/wiki/security-audit.md`; dispatch fixes via `/espalier-fix`.

**Agent definition:** Read `espalier/agent.md` for your operating instructions.

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
    cp .claude/settings.json ".claude/settings.json.espalier-backup-$(date +%s)"
    # Rotate — keep last 5
    ls -t .claude/settings.json.espalier-backup-* 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null || true
  fi

  python3 - << 'PYMERGE'
import json
import os
import sys
import tempfile

SETTINGS = ".claude/settings.json"

ESPALIER_HOOKS = {
    "PostToolUse": [
        {
            "matcher": "Write|Edit",
            "hooks": [{
                "type": "command",
                "command": 'bash "$CLAUDE_PROJECT_DIR/espalier/hooks/post-edit-wrapper.sh"',
                "timeout": 10
            }]
        }
    ],
    "PreToolUse": [
        {
            "matcher": "Bash",
            "hooks": [{
                "type": "command",
                "command": 'bash "$CLAUDE_PROJECT_DIR/espalier/hooks/pre-push-gate-wrapper.sh"',
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
    data = {"hooks": ESPALIER_HOOKS}
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
    for event, new_entries in ESPALIER_HOOKS.items():
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

# --- Stage 9: Squash-merge decision + post-merge dispatcher -----------------

stage_merge_decision() {
  log "Stage 9: persist Phase 0 decisions + post-merge dispatcher"
  if [ "$DRY_RUN" = "yes" ]; then
    echo "[dry-run] write espalier/.merge-hook-decision = $MERGE_DECISION"
    echo "[dry-run] write espalier/.doctor-cadence = $DOCTOR_CADENCE (if absent)"
    echo "[dry-run] install post-merge dispatcher (drift-detect every merge; backlink if installed)"
    return
  fi

  echo "$MERGE_DECISION" > espalier/.merge-hook-decision

  # espalier/.doctor-cadence — tracked, cadence-line only. Written ONCE; never
  # auto-rewritten, so a user's later edit to the cadence survives re-bootstrap.
  if [ -f espalier/.doctor-cadence ]; then
    log "  espalier/.doctor-cadence already exists — preserving"
  else
    echo "cadence: $DOCTOR_CADENCE" > espalier/.doctor-cadence
    log "  wrote espalier/.doctor-cadence = $DOCTOR_CADENCE"
  fi

  # The post-merge dispatcher is installed UNCONDITIONALLY: drift-detect.sh must
  # run on every merge regardless of the squash-merge decision. Whether
  # post-merge-backlink.sh runs is gated at RUNTIME by .merge-hook-decision, so
  # flipping that file toggles backlink with no hook reinstall.

  # Detect husky
  HUSKY_PRESENT=no
  if [ -d ".husky" ]; then
    if [ -f ".husky/_/husky.sh" ] || [ -f ".husky/install.mjs" ]; then
      HUSKY_PRESENT=yes
    elif [ -f package.json ] && grep -q '"husky"' package.json 2>/dev/null; then
      HUSKY_PRESENT=yes
    fi
  fi

  # Resolve where git ACTUALLY looks for hooks. A set core.hooksPath overrides
  # .git/hooks entirely, so a dispatcher written to .git/hooks would be a silent
  # no-op. husky manages its own core.hooksPath (-> .husky/_) and routes
  # .husky/post-merge for us, so when husky is present we trust it.
  HOOK_DST=""
  if [ "$HUSKY_PRESENT" = "yes" ]; then
    HOOK_DST=".husky/post-merge"
  else
    HOOKS_PATH_CFG=$(git config core.hooksPath 2>/dev/null || true)
    if [ -z "$HOOKS_PATH_CFG" ]; then
      HOOK_DST=".git/hooks/post-merge"
    else
      # core.hooksPath is set and husky is not managing it. The dispatcher must
      # land where git reads — and only if that is inside this repo. A hooksPath
      # pointing elsewhere (another repo, a global hooks dir) cannot be wired.
      REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
      HOOKS_DIR_ABS=""
      case "$HOOKS_PATH_CFG" in
        *..*) ;;                                                 # '..' may escape the repo — reject
        /*)   HOOKS_DIR_ABS="${HOOKS_PATH_CFG%/}" ;;             # absolute
        *)    HOOKS_DIR_ABS="$REPO_ROOT/${HOOKS_PATH_CFG%/}" ;;  # relative to repo root
      esac
      if [ -z "$HOOKS_DIR_ABS" ]; then
        log "  WARN: core.hooksPath ('$HOOKS_PATH_CFG') contains '..' — cannot place"
        log "        the post-merge dispatcher safely. Skipping hook install."
        log "        Fix core.hooksPath, then re-run: bash bootstrap-espalier.sh --wire-only ..."
      else
        case "$HOOKS_DIR_ABS/" in
          "$REPO_ROOT"/*)
            HOOK_DST="$HOOKS_DIR_ABS/post-merge"
            log "  core.hooksPath set → targeting $HOOK_DST"
            ;;
          *)
            log "  WARN: core.hooksPath ('$HOOKS_PATH_CFG') points outside this repo."
            log "        git ignores .git/hooks here, so the post-merge dispatcher"
            log "        cannot be installed — drift-detect + squash-backlink will NOT run."
            log "        Fix: 'git config --unset core.hooksPath' (or point it inside the"
            log "        repo), then re-run: bash bootstrap-espalier.sh --wire-only ..."
            ;;
        esac
      fi
    fi
  fi

  if [ -z "$HOOK_DST" ]; then
    return   # hooks dir unreachable — warning already emitted; check #20 will flag it
  fi

  HOOK_DST_PARENT=$(dirname "$HOOK_DST")
  if [ ! -d "$HOOK_DST_PARENT" ]; then
    if [ "$HOOK_DST_PARENT" = ".git/hooks" ]; then
      log "  ERROR: .git/hooks does not exist (run 'git init' first?)"
      return
    fi
    mkdir -p "$HOOK_DST_PARENT" || { log "  ERROR: cannot create $HOOK_DST_PARENT"; return; }
  fi

  # Already on the dispatcher → nothing to do (idempotent).
  if [ -f "$HOOK_DST" ] && grep -q "ESPALIER_POSTMERGE_DISPATCH" "$HOOK_DST" 2>/dev/null; then
    log "  Post-merge dispatcher already installed"
    return
  fi

  # Strip a legacy inlined backlink block. Pre-dispatcher bootstraps copied or
  # appended the whole post-merge-backlink.sh into the hook; that block runs
  # from its marker comment (or the shebang just above it) to EOF.
  if [ -f "$HOOK_DST" ] && grep -qE "ESPALIER_BACKLINK_HOOK|HARNESS_BACKLINK_HOOK" "$HOOK_DST" 2>/dev/null; then
    MLINE=$(grep -nE "ESPALIER_BACKLINK_HOOK|HARNESS_BACKLINK_HOOK" "$HOOK_DST" | head -1 | cut -d: -f1)
    START="$MLINE"
    if [ "$MLINE" -gt 1 ]; then
      PREV=$(sed -n "$((MLINE - 1))p" "$HOOK_DST")
      [ "$PREV" = "#!/bin/bash" ] && START=$((MLINE - 1))
    fi
    STRIP_TMP=$(mktemp)
    if [ "$START" -gt 1 ]; then
      sed -n "1,$((START - 1))p" "$HOOK_DST" > "$STRIP_TMP"
    fi
    mv "$STRIP_TMP" "$HOOK_DST"
    log "  Stripped legacy inlined backlink block from $HOOK_DST"
  fi

  # Write (fresh) or append (preserving a user hook) the dispatcher block.
  if [ -s "$HOOK_DST" ]; then
    printf '\n' >> "$HOOK_DST"
  else
    echo "#!/bin/bash" > "$HOOK_DST"
  fi
  cat >> "$HOOK_DST" << 'DISPATCH'
# >>> ESPALIER_POSTMERGE_DISPATCH v1 >>>
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$ROOT" || exit 0
[ -f espalier/hooks/drift-detect.sh ] && bash espalier/hooks/drift-detect.sh
if [ "$(cat espalier/.merge-hook-decision 2>/dev/null)" = "installed" ]; then
  [ -f espalier/hooks/post-merge-backlink.sh ] && bash espalier/hooks/post-merge-backlink.sh
fi
# <<< ESPALIER_POSTMERGE_DISPATCH v1 <<<
exit 0
DISPATCH
  chmod +x "$HOOK_DST"
  log "  Installed post-merge dispatcher → $HOOK_DST"
}

# --- Stage 10: .gitignore append --------------------------------------------

stage_gitignore() {
  log "Stage 10: .gitignore append (idempotent + newline guard)"
  if [ "$DRY_RUN" = "yes" ]; then
    echo "[dry-run] append espalier cache + drift-sidecar entries to .gitignore"
    return
  fi
  # commit-index cache + the five drift sidecars (.drift-state.tsv* glob also
  # covers mktemp temp files). Each entry appended once, with a newline guard.
  printf '%s\n' \
    "espalier/.commit-index.tsv" \
    "espalier/.drift-state.tsv*" \
    "espalier/.drift.log" \
    "espalier/.drift-report.md" \
    "espalier/.doctor-last-run" \
    "espalier/.drift-overrides.log" \
  | while IFS= read -r entry; do
      grep -qxF "$entry" .gitignore 2>/dev/null && continue
      if [ -s .gitignore ] && [ -n "$(tail -c1 .gitignore)" ]; then
        printf '\n' >> .gitignore
      fi
      echo "$entry" >> .gitignore
    done
}

# --- Stage 11: Validation (parallel — R6) -----------------------------------

stage_validate() {
  log "Stage 11: validation (37 checks — R6)"
  if [ "$DRY_RUN" = "yes" ]; then
    echo "[dry-run] would run 37 validation checks (skipped — nothing to validate yet)"
    return 0
  fi

  local tmpdir
  tmpdir=$(mktemp -d -t espalier-validate.XXXXXX)
  local failed=0

  run_check() {
    local n=$1 check_name=$2 cmd=$3
    local idx
    idx=$(printf '%02d' "$n")
    # Subshell isolates eval — prevents (a) variable bleed-back (loop vars
    # like $name leaking into outer scope), (b) `exit` inside cmd killing
    # the run_check function.
    if ( eval "$cmd" ) >/dev/null 2>&1; then
      echo "[$n/37] OK   $check_name" > "$tmpdir/$idx"
    else
      local err
      err=$( ( eval "$cmd" ) 2>&1 | head -1 )
      echo "[$n/37] FAIL $check_name: $err" > "$tmpdir/$idx"
      echo "fail" > "$tmpdir/$idx.fail"
    fi
  }

  # Check #25 — invoked DIRECTLY (not via run_check): the run_check harness
  # discards stdout, which would swallow #25's per-tier table.
  run_check_25() {
    [ -f espalier/.drift-state.tsv ] || { echo "[25/37] OK   stale-tiers: no drift"; return 0; }
    local NOW; NOW=$(date -u +%s)
    local fresh=0 aging=0 stale=0 critical=0 expired=0
    while IFS=$'\t' read -r FILE SHA FIRST_SEEN REASON; do
      [ -z "$FILE" ] && continue
      local TS_SEC
      if [ "$(uname)" = "Darwin" ]; then
        TS_SEC=$(date -juf %Y-%m-%dT%H:%M:%SZ "$FIRST_SEEN" +%s 2>/dev/null)
      else
        TS_SEC=$(date -d "$FIRST_SEEN" +%s 2>/dev/null)
      fi
      [ -z "$TS_SEC" ] && { echo "  WARN bad stale_first_seen: $FILE"; continue; }
      local AGE=$(( (NOW - TS_SEC) / 86400 ))
      if   [ "$AGE" -lt 14 ]; then fresh=$((fresh+1))
      elif [ "$AGE" -lt 30 ]; then aging=$((aging+1));       echo "  [aging]    ${AGE}d  $FILE"
      elif [ "$AGE" -lt 60 ]; then stale=$((stale+1));       echo "  [stale]    ${AGE}d  $FILE"
      elif [ "$AGE" -lt 90 ]; then critical=$((critical+1)); echo "  [critical] ${AGE}d  $FILE"
      else expired=$((expired+1));                           echo "  [expired]  ${AGE}d  $FILE"
      fi
    done < espalier/.drift-state.tsv
    echo "[25/37] stale-tiers: fresh=$fresh aging=$aging stale=$stale critical=$critical expired=$expired"
    [ "$critical" -gt 0 ] && echo "  WARN: $critical artifact(s) 60-90d stale"
    if [ "$expired" -gt 0 ]; then
      if [ "${IGNORE_DRIFT:-no}" = "yes" ]; then
        local who; who=$(git config user.email 2>/dev/null || echo unknown)
        printf '%s\t%s\texpired=%s\treason=%s\n' \
          "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$who" "$expired" "${IGNORE_DRIFT_REASON:-(no reason given)}" \
          >> espalier/.drift-overrides.log
        echo "  OVERRIDE: $expired expired artifact(s) ignored (--ignore-drift) — logged"
      else
        echo "  FAIL: $expired expired (>90d) — run /espalier-prune --all-stale"
        return 1
      fi
    fi
    return 0
  }

  run_check  1 "rules-load"          'ls .claude/rules/espalier-*.md' &
  run_check  2 "skills-load"         'ls -d .claude/skills/espalier-coding .claude/skills/espalier-review .claude/skills/espalier-security .claude/skills/espalier-testing .claude/skills/espalier-requirements .claude/skills/espalier-grill .claude/skills/espalier .claude/skills/espalier-fix .claude/skills/espalier-ask .claude/skills/espalier-audit' &
  run_check  3 "agents-load"         'ls .claude/agents/harness-coder.md .claude/agents/harness-reviewer.md .claude/agents/harness-security.md' &
  run_check  4 "hooks-configured"    'grep -q "espalier/hooks" .claude/settings.json' &
  run_check  5 "symlinks-valid"      '[ -L .claude/rules/espalier-structure.md ] && [ -e .claude/rules/espalier-structure.md ]' &
  run_check  6 "hooks-executable"    'test -x espalier/hooks/post-edit-wrapper.sh && test -x espalier/hooks/pre-push-gate.sh && test -x espalier/hooks/pre-push-gate-wrapper.sh' &
  run_check  7 "state-template"      'test -f espalier/changes/_template/pipeline-state.md' &
  run_check  8 "claudemd-updated"    'grep -q "## Espalier" CLAUDE.md' &
  run_check  9 "espalier-agent-md"   'test -f espalier/agent.md' &
  run_check 10 "espalier-pipeline-md" 'test -f espalier/pipeline.md' &
  run_check 11 "skill-name-parity"   'for f in espalier/skills/*/SKILL.md; do dir=$(basename $(dirname "$f")); name=$(grep "^name:" "$f" | awk "{print \$2}"); [ "$dir" = "$name" ] || exit 1; done' &
  run_check 12 "typed-changes-dirs"  '[ -d espalier/changes/feat ] && [ -d espalier/changes/fix ] && [ -d espalier/changes/refactor ]' &
  run_check 13 "espalier-fix-skill"  'test -f .claude/skills/espalier-fix/SKILL.md' &
  run_check 14 "espalier-fix-name"   'grep -q "^name: espalier-fix" .claude/skills/espalier-fix/SKILL.md' &
  run_check 15 "rules-engineering"   'test -f espalier/rules/engineering-structure.md' &
  run_check 16 "rules-standards"     'test -f espalier/rules/coding-standards.md' &
  run_check 17 "merge-decision"      'grep -qE "^(not-needed|installed|fuzzy-allowed|skip-only|never-ask|ask-later)$" espalier/.merge-hook-decision' &
  run_check 18 "hook-template-copy"  'test -f espalier/hooks/post-merge-backlink.sh && test -x espalier/hooks/post-merge-backlink.sh' &
  run_check 19 "lookup-helpers"      'test -f espalier/hooks/lookup-helpers.sh' &
  run_check 20 "post-merge-dispatcher" '_hd=$(git config core.hooksPath 2>/dev/null); [ -n "$_hd" ] || _hd=.git/hooks; grep -qE "ESPALIER_POSTMERGE_DISPATCH" "$_hd/post-merge" 2>/dev/null || grep -qE "ESPALIER_POSTMERGE_DISPATCH" .husky/post-merge 2>/dev/null' &
  run_check 21 "rebuild-script"      'test -x espalier/hooks/rebuild-commit-index.sh' &
  run_check 22 "gitignore-cache"     'grep -qxF "espalier/.commit-index.tsv" .gitignore' &
  run_check 23 "rebuild-runs"        'bash espalier/hooks/rebuild-commit-index.sh && test -f espalier/.commit-index.tsv' &
  run_check 24 "cache-tsv-format"    '[ ! -s espalier/.commit-index.tsv ] || awk -F"\t" "NF != 4 { exit 1 }" espalier/.commit-index.tsv' &
  run_check 26 "drift-state-format"  '[ ! -s espalier/.drift-state.tsv ] || awk -F"\t" "NF != 4 { exit 1 }" espalier/.drift-state.tsv' &
  run_check 27 "conventions-format"  '[ ! -s espalier/.conventions.tsv ] || awk -F"\t" "NF != 5 && NF != 6 { exit 1 }" espalier/.conventions.tsv' &
  run_check 28 "doctor-cadence"      '[ ! -f espalier/.doctor-cadence ] || grep -qE "^cadence: (every-change|weekly|monthly|manual)$" espalier/.doctor-cadence' &
  run_check 29 "espalier-ask-skill"  'test -f .claude/skills/espalier-ask/SKILL.md' &
  run_check 30 "security-rule"       '[ -L .claude/rules/espalier-security.md ] && [ -e .claude/rules/espalier-security.md ]' &
  run_check 31 "security-agent"      'test -f .claude/agents/harness-security.md' &
  run_check 32 "security-skill"      'test -f .claude/skills/espalier-security/SKILL.md' &
  run_check 33 "audit-skill"         'test -f .claude/skills/espalier-audit/SKILL.md' &
  run_check 34 "audit-mode"          'grep -qF "## Repo-Audit Mode" espalier/agents/harness-security.md' &
  run_check 35 "production-rule"     '[ -L .claude/rules/espalier-production.md ] && [ -e .claude/rules/espalier-production.md ]' &
  run_check 36 "production-file"     'test -f espalier/rules/production-standards.md' &
  run_check 37 "scout-prompts"      'test -f espalier/.scout-prompts.md' &

  wait

  # Emit deterministic order: 1-24 (sorted), then #25 (serial — its tier table
  # must reach stdout, which the run_check harness discards), then 26-37.
  cat "$tmpdir"/0? "$tmpdir"/1? "$tmpdir"/2[0-4] 2>/dev/null
  run_check_25 || echo "fail" > "$tmpdir/25.fail"
  cat "$tmpdir"/2[6-9] "$tmpdir"/3[0-7] 2>/dev/null

  failed=$(ls "$tmpdir"/*.fail 2>/dev/null | wc -l | tr -d ' ')
  rm -rf "$tmpdir"

  if [ "$failed" -gt 0 ]; then
    log "Validation: $failed/37 FAILED"
    return 1
  fi
  log "Validation: 37/37 passed"
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
