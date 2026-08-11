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
#     espalier-ask, espalier-audit, espalier-map SKILL.md + hooks).
#   - chmod +x every espalier/hooks/*.sh (catches LLM-written hooks too — R10).
#   - Creates symlinks via portable abspath helper (R-extra).
#   - Appends CLAUDE.md Espalier section (idempotent grep-guard).
#   - Merges .claude/settings.json hooks (Appendix A algorithm).
#   - Persists squash-merge decision + installs the post-merge dispatcher.
#   - Appends .gitignore entries for the commit-index + drift sidecars.
#   - Wires the codex platform when targeted (.agents/skills symlinks,
#     AGENTS.md section, .codex/config.toml hooks, .codex/agents/*.toml).
#   - Wires the copilot platform when targeted (.github/skills symlinks,
#     copilot-instructions.md section, .github/agents/*.agent.md,
#     .github/hooks/espalier-gates.json via the camelCase adapter).
#   - Appends the .gitattributes union entry + optional CODEOWNERS block.
#   - Runs the validation checks (R6) — 52 claude-only, 57 with codex,
#     62 with copilot.
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
#   --lang=<typescript|python|go|unsupported>
#                            Boundary-check variant. "unsupported" emits a no-op.
#   --doctor-cadence=<val>   every-change | weekly | monthly | manual (default: weekly).
#   --platforms=<list>       Comma list of agent platforms to wire:
#                            claude | codex | copilot (shorthands: "both" =
#                            claude,codex; "all" = all three). Default: claude.
#                            claude  → .claude/ symlinks + CLAUDE.md + settings.json
#                            codex   → .agents/skills/ symlinks + AGENTS.md +
#                                      .codex/config.toml hooks + .codex/agents/*.toml
#                            copilot → .github/skills/ symlinks +
#                                      .github/copilot-instructions.md section +
#                                      .github/agents/*.agent.md +
#                                      .github/hooks/espalier-gates.json
#   --codeowners-rules=<h>   GitHub handle/team owning espalier/rules/ (CODEOWNERS
#                            block, R4). '@' prefixed if missing.
#   --codeowners-wiki=<h>    Same for espalier/wiki/. Both empty → sub-step no-ops.
#   --greenfield             Greenfield Pass 1 (near-empty repo): full wiring, but
#                            writes a placeholder pre-push-gate.sh, records
#                            espalier/.greenfield, and validation renders every
#                            Phase-2-artifact check (5, 9, 15-16, 30-32, 34-36,
#                            38-45) as a pending-skip. Cleared by init Pass 2
#                            after the decision map clears.
#   --dry-run                Print actions without executing.
#   --yes                    Non-interactive (used by tests + CI smoke).
#   --force                  Override re-run safety check on existing espalier/.
#
# Debug flags (not used by normal /espalier-init flow):
#   --copy-only              Only Stages 1-4 (mkdir + pure-copy + hooks).
#   --wire-only              Only Stages 5-11 (symlinks + wiring + validation).
#   --validate-only          Only Stage 11 (52/57/62-check validation).
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
PLATFORMS=""          # resolved after parsing: flag > espalier/.platforms > claude
PLATFORMS_FLAG=""     # raw --platforms value (empty = not passed)
CODEOWNERS_RULES=""   # optional @handle owning espalier/rules/ (A4)
CODEOWNERS_WIKI=""    # optional @handle owning espalier/wiki/
GREENFIELD=no         # greenfield Pass 1 (placeholder gate + .greenfield marker)
MODE="full"  # full | copy-only | wire-only | validate-only

for arg in "$@"; do
  case "$arg" in
    --project-dir=*)        PROJECT_DIR="${arg#--project-dir=}" ;;
    --plugin-dir=*)         PLUGIN_DIR="${arg#--plugin-dir=}" ;;
    --lang=*)               LANG_VARIANT="${arg#--lang=}" ;;
    --merge-decision=*)     MERGE_DECISION="${arg#--merge-decision=}" ;;
    --doctor-cadence=*)     DOCTOR_CADENCE="${arg#--doctor-cadence=}" ;;
    --platforms=*)          PLATFORMS_FLAG="${arg#--platforms=}" ;;
    --codeowners-rules=*)   CODEOWNERS_RULES="${arg#--codeowners-rules=}" ;;
    --codeowners-wiki=*)    CODEOWNERS_WIKI="${arg#--codeowners-wiki=}" ;;
    --greenfield)           GREENFIELD=yes ;;
    --dry-run)              DRY_RUN=yes ;;
    --yes)                  SKIP_PROMPT=yes ;;
    --force)                FORCE=yes ;;
    --ignore-drift)         IGNORE_DRIFT=yes ;;
    --ignore-drift-reason=*) IGNORE_DRIFT_REASON="${arg#--ignore-drift-reason=}" ;;
    --copy-only)            MODE="copy-only" ;;
    --wire-only)            MODE="wire-only" ;;
    --validate-only)        MODE="validate-only" ;;
    -h|--help)
      sed -n '2,76p' "$0"
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
    "$HOME/repos/harness-engineering"; do
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

# Validate --merge-decision (required for full and wire-only).
# wire-only convenience: an existing install already persisted the decision —
# reuse it so "add a platform later" runs don't force the user to re-answer.
if [ -z "$MERGE_DECISION" ] && [ "$MODE" = "wire-only" ] && [ -f espalier/.merge-hook-decision ]; then
  MERGE_DECISION=$(head -1 espalier/.merge-hook-decision | tr -d '[:space:]')
  log "wire-only: reusing persisted merge decision '$MERGE_DECISION' (espalier/.merge-hook-decision)"
fi
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

# Validate --lang (single vocabulary end-to-end: typescript|python|go|unsupported)
case "$LANG_VARIANT" in
  typescript|python|go|unsupported) ;;
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

# Resolve + validate platforms. Precedence: --platforms flag > union with any
# existing espalier/.platforms (re-runs are ADDITIVE — wiring codex later never
# unwires claude) > persisted file alone > default claude.
normalize_platforms() {
  # stdin: comma list → stdout: canonical subset of "claude,codex,copilot"
  # (that order); rc 1 on junk / empty
  local raw p want_c=no want_x=no want_p=no out=""
  raw=$(cat | tr 'A-Z' 'a-z' | tr -d '[:space:]')
  raw=${raw//both/claude,codex}
  raw=${raw//all/claude,codex,copilot}
  local IFS=','
  for p in $raw; do
    case "$p" in
      claude)      want_c=yes ;;
      codex)       want_x=yes ;;
      copilot)     want_p=yes ;;
      "")          ;;
      *)           return 1 ;;
    esac
  done
  [ "$want_c" = "yes" ] && out="claude"
  [ "$want_x" = "yes" ] && out="${out:+$out,}codex"
  [ "$want_p" = "yes" ] && out="${out:+$out,}copilot"
  [ -z "$out" ] && return 1
  echo "$out"
}

EXISTING_PLATFORMS=""
if [ -f espalier/.platforms ]; then
  EXISTING_PLATFORMS=$(head -1 espalier/.platforms | tr -d '[:space:]')
elif [ -f espalier/.merge-hook-decision ]; then
  # Complete pre-v0.14 install: predates .platforms, so it is a claude install.
  # Without this inference, "--wire-only --platforms=codex" on a legacy install
  # would record codex-only and validation would stop checking claude wiring.
  EXISTING_PLATFORMS="claude"
fi

if [ -n "$PLATFORMS_FLAG" ]; then
  PLATFORMS=$(printf '%s,%s' "$PLATFORMS_FLAG" "$EXISTING_PLATFORMS" | normalize_platforms) || {
    echo "ERROR: invalid --platforms='$PLATFORMS_FLAG' (valid: any comma list of claude|codex|copilot, or both|all)" >&2
    exit 1
  }
elif [ -n "$EXISTING_PLATFORMS" ]; then
  PLATFORMS=$(printf '%s' "$EXISTING_PLATFORMS" | normalize_platforms) || PLATFORMS="claude"
else
  PLATFORMS="claude"
fi

want_claude()  { case "$PLATFORMS" in *claude*)  return 0 ;; *) return 1 ;; esac; }
want_codex()   { case "$PLATFORMS" in *codex*)   return 0 ;; *) return 1 ;; esac; }
want_copilot() { case "$PLATFORMS" in *copilot*) return 0 ;; *) return 1 ;; esac; }

log "Mode: $MODE | project: $PROJECT_DIR | plugin: $PLUGIN_DIR | lang: $LANG_VARIANT | platforms: $PLATFORMS"

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
  run "mkdir -p espalier/skills/espalier-map"
  run "mkdir -p espalier/skills/espalier-maprun"
  run "mkdir -p espalier/maps"
  run "mkdir -p espalier/agents"
  run "mkdir -p espalier/hooks"
  run "mkdir -p espalier/wiki"
  run "mkdir -p espalier/changes/_template"
  run "mkdir -p espalier/changes/feat"
  run "mkdir -p espalier/changes/fix"
  run "mkdir -p espalier/changes/refactor"
  if want_claude; then
    run "mkdir -p .claude/rules"
    run "mkdir -p .claude/skills"
    run "mkdir -p .claude/agents"
  fi
  if want_codex; then
    run "mkdir -p .agents/skills"
    run "mkdir -p .codex/agents"
  fi
  if want_copilot; then
    run "mkdir -p .github/skills"
    run "mkdir -p .github/agents"
    run "mkdir -p .github/hooks"
  fi
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
  run "cp '$PLUGIN_DIR/templates/skills/espalier-map.md' espalier/skills/espalier-map/SKILL.md"
  run "cp '$PLUGIN_DIR/templates/skills/espalier-maprun.md' espalier/skills/espalier-maprun/SKILL.md"
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
  # Copilot camelCase→snake_case hook shim (pure copy; inert unless
  # .github/hooks/espalier-gates.json references it — Stage 8e, copilot only).
  run "cp '$PLUGIN_DIR/hook-templates/copilot-hook-adapter.sh' espalier/hooks/copilot-hook-adapter.sh"
  # /espalier-map plan-don't-do guard (inert unless espalier/maps/.active-session exists).
  run "cp '$PLUGIN_DIR/hook-templates/map-guard.sh' espalier/hooks/map-guard.sh"
  # Read-only lane-quality report (run manually: bash espalier/hooks/espalier-stats.sh).
  run "cp '$PLUGIN_DIR/hook-templates/espalier-stats.sh' espalier/hooks/espalier-stats.sh"
  # /espalier-maprun engine (write-if-absent: a repo carrying a locally-adapted
  # engine — the lane's field origin — keeps its version on re-runs).
  for mr in maprun.py maprun-dispatch.sh maprun-merge.sh maprun-integration.sh maprun-verify.sh; do
    if [ -f "espalier/hooks/$mr" ]; then
      log "  espalier/hooks/$mr exists — preserving"
    else
      run "cp '$PLUGIN_DIR/hook-templates/$mr' 'espalier/hooks/$mr'"
    fi
  done
  # Greenfield Pass 1: no Phase 2 writes exist yet — a placeholder gate keeps
  # check #6 honest and blocks nothing; init Pass 2 overwrites it with the
  # real substituted gate once the decision map clears. Write-if-absent.
  if [ "$GREENFIELD" = "yes" ]; then
    if [ "$DRY_RUN" = "yes" ]; then
      echo "[dry-run] write placeholder espalier/hooks/pre-push-gate.sh + espalier/.greenfield"
    else
      if [ ! -f espalier/hooks/pre-push-gate.sh ]; then
        printf '#!/bin/bash\n# greenfield placeholder — real gate is written by /espalier-init Pass 2\n# (after the /espalier-map greenfield map clears). Blocks nothing until then.\nexit 0\n' \
          > espalier/hooks/pre-push-gate.sh
      fi
      [ -f espalier/.greenfield ] || printf 'pass1: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > espalier/.greenfield
    fi
  fi
  # --lang=unsupported: guarantee post-edit-wrapper never execs a missing file.
  # Write-if-absent ONLY — never clobber a Phase-2-adapted hook.
  if [ "$LANG_VARIANT" = "unsupported" ] && [ ! -f espalier/hooks/check-layer-boundaries.sh ]; then
    if [ "$DRY_RUN" = "yes" ]; then
      echo "[dry-run] write no-op espalier/hooks/check-layer-boundaries.sh"
    else
      printf '#!/bin/bash\n# no-op: --lang=unsupported at init — no layer-boundary rules for this stack\nexit 0\n' \
        > espalier/hooks/check-layer-boundaries.sh
    fi
  fi
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

ESPALIER_SKILL_NAMES="espalier-coding espalier-review espalier-security espalier-testing espalier-requirements espalier-grill espalier espalier-fix espalier-prune espalier-doctor espalier-ask espalier-audit espalier-map espalier-maprun"

stage_symlinks() {
  log "Stage 5: platform wiring symlinks ($PLATFORMS)"
  # chmod-glob also runs here (idempotent) so wire-only mode picks up
  # LLM-written hooks. Full mode already chmodded in Stage 4 — harmless re-chmod.
  if [ "$DRY_RUN" != "yes" ]; then
    for hook in espalier/hooks/*.sh; do
      [ -f "$hook" ] && chmod +x "$hook" 2>/dev/null || true
    done
  fi
  # Targets are RELATIVE to the symlink's own directory (.claude/{rules,skills,
  # agents}/<link> and .agents/skills/<link> are two levels below the repo root,
  # hence ../../espalier/…) — a repo moved or checked out at another path keeps
  # every link resolving.
  WIRED_RULES=0; WIRED_SKILLS=0; WIRED_AGENTS=0
  if want_claude; then
    safe_ln "../../espalier/rules/engineering-structure.md" .claude/rules/espalier-structure.md && WIRED_RULES=$((WIRED_RULES+1))
    safe_ln "../../espalier/rules/coding-standards.md"      .claude/rules/espalier-standards.md && WIRED_RULES=$((WIRED_RULES+1))
    safe_ln "../../espalier/rules/development-process.md"   .claude/rules/espalier-process.md && WIRED_RULES=$((WIRED_RULES+1))
    safe_ln "../../espalier/rules/security-standards.md"    .claude/rules/espalier-security.md && WIRED_RULES=$((WIRED_RULES+1))
    safe_ln "../../espalier/rules/production-standards.md"  .claude/rules/espalier-production.md && WIRED_RULES=$((WIRED_RULES+1))
    for s in $ESPALIER_SKILL_NAMES; do
      safe_ln "../../espalier/skills/$s" ".claude/skills/$s" && WIRED_SKILLS=$((WIRED_SKILLS+1))
    done
    # Sub-agent identifiers intentionally kept as harness-coder / harness-reviewer
    # (see SKILL.md Phase 0 note).
    safe_ln "../../espalier/agents/harness-coder.md"    .claude/agents/harness-coder.md && WIRED_AGENTS=$((WIRED_AGENTS+1))
    safe_ln "../../espalier/agents/harness-reviewer.md" .claude/agents/harness-reviewer.md && WIRED_AGENTS=$((WIRED_AGENTS+1))
    safe_ln "../../espalier/agents/harness-security.md" .claude/agents/harness-security.md && WIRED_AGENTS=$((WIRED_AGENTS+1))
  fi
  if want_codex; then
    # Codex discovers repo skills by probing .agents/skills/ (SkillScope::Repo).
    # Same folder-name == frontmatter-name invariant as Claude Code, so the
    # very same espalier/skills/<name> dirs wire straight in.
    CODEX_SKILLS=0
    for s in $ESPALIER_SKILL_NAMES; do
      safe_ln "../../espalier/skills/$s" ".agents/skills/$s" && CODEX_SKILLS=$((CODEX_SKILLS+1))
    done
    log "  codex: $CODEX_SKILLS skills linked into .agents/skills/"
    # Codex has no auto-loaded rules dir or agent .md registry; rules load via
    # the AGENTS.md instruction (Stage 7b) and sub-agents via .codex/agents/*.toml
    # (Stage 8c). Count them as wired only when claude didn't already.
    if ! want_claude; then
      WIRED_SKILLS=$CODEX_SKILLS
      WIRED_RULES=5    # bound via the AGENTS.md always-read instruction
      WIRED_AGENTS=3   # bound via .codex/agents/harness-*.toml
    fi
  fi
  if want_copilot; then
    # Copilot Agent Skills read .github/skills/ across ALL its surfaces
    # (VS Code, CLI, cloud agent). VS Code additionally reads .claude/skills/
    # and .agents/skills/, but .github/skills/ is the only cross-surface
    # location — wire it explicitly, same invariant, invoked /espalier….
    COPILOT_SKILLS=0
    for s in $ESPALIER_SKILL_NAMES; do
      safe_ln "../../espalier/skills/$s" ".github/skills/$s" && COPILOT_SKILLS=$((COPILOT_SKILLS+1))
    done
    log "  copilot: $COPILOT_SKILLS skills linked into .github/skills/"
    # Rules load via the copilot-instructions.md instruction (Stage 7c) and
    # sub-agents via .github/agents/*.agent.md (Stage 8d).
    if ! want_claude && ! want_codex; then
      WIRED_SKILLS=$COPILOT_SKILLS
      WIRED_RULES=5    # bound via the copilot-instructions always-read instruction
      WIRED_AGENTS=3   # bound via .github/agents/harness-*.agent.md
    fi
  fi
  # Read by espalier-init SKILL.md Phase 4 for the completion message — keep
  # this exact format.
  echo "WIRED: skills=$WIRED_SKILLS rules=$WIRED_RULES agents=$WIRED_AGENTS"
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
- Review Rounds: req=0/{max-req-rounds}, code=0/{max-code-rounds}, test=0/{max-test-rounds}

## Stage History
| Stage | Status | Timestamp | Notes |
|-------|--------|-----------|-------|
STATETMPL
}

# --- Stage 7: CLAUDE.md append ----------------------------------------------

stage_claudemd() {
  if ! want_claude; then
    log "Stage 7: CLAUDE.md append — skipped (claude not in --platforms)"
    return
  fi
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

**For bug fixes**, use `/espalier-fix <bug>` for the slim lane — 7 stages (0–7, no Stage 2).

**For questions** ("how does X work", "where is Y"), use `/espalier-ask <question>` — read-only, answers from espalier/ docs first.

**For a repo-wide security audit**, use `/espalier-audit` — inventories trust-boundary defects in the existing code to `espalier/wiki/security-audit.md`; dispatch fixes via `/espalier-fix`.

**For multi-session planning** (an epic, a greenfield build — anything too big for one session), use `/espalier-map <idea>` — charts a decision map under `espalier/maps/`, one ticket per session; a cleared map hands back FILED slices for `/espalier`. It plans only, never codes.

**To execute a whole cleared map** over hours/days, use `/espalier-maprun <map-slug>` — one interactive master pass dispatches headless pipeline workers in isolated worktrees, merges what passes, and relays worker questions; run one pass per fresh session.

**Agent definition:** Read `espalier/agent.md` for your operating instructions.

**Key principle:** The coder agent and reviewer agent are ALWAYS separate.
Never review your own code in the same invocation that wrote it.
CLAUDETMPL
}

# --- Stage 8: .claude/settings.json merge (Appendix A algorithm) ------------

stage_settings_json() {
  if ! want_claude; then
    log "Stage 8: .claude/settings.json merge — skipped (claude not in --platforms)"
    return
  fi
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
        },
        {
            "matcher": "Write|Edit",
            "hooks": [{
                "type": "command",
                "command": 'bash "$CLAUDE_PROJECT_DIR/espalier/hooks/map-guard.sh"',
                "timeout": 5
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

# --- Stage 7b: AGENTS.md append (codex) --------------------------------------

stage_agentsmd() {
  if ! want_codex; then
    return
  fi
  log "Stage 7b: AGENTS.md append (idempotent grep-guard)"
  if [ -f AGENTS.md ] && grep -q "## Espalier" AGENTS.md 2>/dev/null; then
    log "  AGENTS.md already has Espalier section — skipping"
    return
  fi
  if [ "$DRY_RUN" = "yes" ]; then
    echo "[dry-run] append Espalier section to AGENTS.md"
    return
  fi
  cat >> AGENTS.md << 'AGENTSTMPL'

## Espalier

This project uses Espalier for AI code quality — auto-discovered, project-specific guardrails.

**Always-loaded rules:** before writing or reviewing ANY code, read every file in
`espalier/rules/` (engineering-structure, coding-standards, development-process,
security-standards, production-standards). Codex has no auto-loaded rules
directory — this instruction IS the load mechanism; do not skip it.

**For any implementation work**, invoke the `espalier` skill (`$espalier <requirement>`) to execute the full pipeline.

**For bug fixes**, invoke `$espalier-fix <bug>` for the slim lane — 7 stages (0–7, no Stage 2).

**For questions** ("how does X work", "where is Y"), invoke `$espalier-ask <question>` — read-only, answers from espalier/ docs first.

**For a repo-wide security audit**, invoke `$espalier-audit` — inventories trust-boundary defects in the existing code to `espalier/wiki/security-audit.md`; dispatch fixes via `$espalier-fix`.

**For multi-session planning** (an epic, a greenfield build — anything too big for one session), invoke `$espalier-map <idea>` — charts a decision map under `espalier/maps/`, one ticket per session; a cleared map hands back FILED slices for `$espalier`. It plans only, never codes.

**To execute a whole cleared map** over hours/days, invoke `$espalier-maprun <map-slug>` — one interactive master pass dispatches headless pipeline workers in isolated worktrees, merges what passes, and relays worker questions; run one pass per fresh session.

**Agent definition:** Read `espalier/agent.md` for your operating instructions.

**Key principle:** The coder agent and reviewer agent are ALWAYS separate.
Never review your own code in the same invocation that wrote it.

### Platform mapping (Codex)

Espalier's skill files use Claude Code vocabulary in places; on Codex apply these mappings:

- `/espalier*` slash commands → `$espalier*` skill invocations.
- `AskUserQuestion` → ask the user directly in chat and WAIT for the reply.
  Where a skill says "if you can call AskUserQuestion you are interactive",
  read it as: if you can ask the user in chat, you ARE interactive.
- "Spawn sub-agent harness-coder / harness-reviewer / harness-security with
  prompt X" → spawn the matching Codex subagent (defined in
  `.codex/agents/<name>.toml`) with the same prompt. If subagent spawning is
  unavailable in this session, execute the roles inline in strict sequence and
  NEVER let the pass that wrote code also approve it: finish the coder role,
  then re-read `espalier/agents/harness-reviewer.md` and review against the
  actual diff as if you had not written it.
- `.claude/settings.json` hooks → already wired in `.codex/config.toml`
  (run `/hooks` once in Codex to trust them; they are the quality gates).
- `$CLAUDE_PROJECT_DIR` in docs → the repo root (`git rev-parse --show-toplevel`).
AGENTSTMPL
}

# --- Stage 8b: .codex/config.toml hooks merge (codex) ------------------------

stage_codex_config() {
  if ! want_codex; then
    return
  fi
  log "Stage 8b: .codex/config.toml hooks merge (marker-guarded)"
  # The map-guard block has its OWN marker so a pre-v0.18 install (whose
  # ESPALIER HOOKS v1 block already exists) still receives it on re-run.
  _codex_map_guard_block() {
    if grep -q "ESPALIER MAP GUARD" .codex/config.toml 2>/dev/null; then
      return 0
    fi
    if [ "$DRY_RUN" = "yes" ]; then
      echo "[dry-run] append Espalier map-guard block to .codex/config.toml"
      return 0
    fi
    [ -s .codex/config.toml ] && printf '\n' >> .codex/config.toml
    cat >> .codex/config.toml << 'CODEXMAPGUARD'
# >>> ESPALIER MAP GUARD v1 >>> (managed by espalier bootstrap — do not edit between markers)
# Blocks writes outside espalier/maps/ while a /espalier-map session marker is
# active (plan, don't do). Inert otherwise. Exit 2 + stderr blocks.
[[hooks.PreToolUse]]
matcher = "^(apply_patch|Edit|Write)$"

[[hooks.PreToolUse.hooks]]
type = "command"
command = "bash espalier/hooks/map-guard.sh"
statusMessage = "Espalier map-session write guard"
timeout = 5
# <<< ESPALIER MAP GUARD v1 <<<
CODEXMAPGUARD
    log "  .codex/config.toml: map-guard block appended"
  }
  if [ -f .codex/config.toml ] && grep -q "ESPALIER HOOKS" .codex/config.toml 2>/dev/null; then
    log "  .codex/config.toml already has Espalier hook block — skipping"
    _codex_map_guard_block
    return
  fi
  if [ "$DRY_RUN" = "yes" ]; then
    echo "[dry-run] append Espalier hook block to .codex/config.toml"
    _codex_map_guard_block
    return
  fi
  mkdir -p .codex
  if [ -f .codex/config.toml ]; then
    cp .codex/config.toml ".codex/config.toml.espalier-backup-$(date +%s)"
    ls -t .codex/config.toml.espalier-backup-* 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null || true
    # Appending [[hooks.*]] tables at EOF is always valid top-level TOML.
    printf '\n' >> .codex/config.toml
  fi
  cat >> .codex/config.toml << 'CODEXHOOKS'
# >>> ESPALIER HOOKS v1 >>> (managed by espalier bootstrap — do not edit between markers)
# Same exit-code contract as Claude Code hooks: exit 2 + stderr blocks/feeds back.
# Codex loads this project layer only when the project is trusted; run /hooks
# once to trust these commands.
[[hooks.PostToolUse]]
matcher = "^(apply_patch|Edit|Write)$"

[[hooks.PostToolUse.hooks]]
type = "command"
command = "bash espalier/hooks/post-edit-wrapper.sh"
statusMessage = "Espalier layer-boundary check"
timeout = 10

[[hooks.PreToolUse]]
matcher = "^(Bash|shell|local_shell)$"

[[hooks.PreToolUse.hooks]]
type = "command"
command = "bash espalier/hooks/pre-push-gate-wrapper.sh"
statusMessage = "Espalier push gate"
timeout = 30
# <<< ESPALIER HOOKS v1 <<<
CODEXHOOKS
  log "  .codex/config.toml: Espalier hook block appended"
  _codex_map_guard_block
}

# --- Stage 8c: .codex/agents/*.toml sub-agents (codex) ------------------------

stage_codex_agents() {
  if ! want_codex; then
    return
  fi
  log "Stage 8c: .codex/agents/harness-*.toml (write-if-absent)"
  if [ "$DRY_RUN" = "yes" ]; then
    echo "[dry-run] write .codex/agents/harness-{coder,reviewer,security}.toml (if absent)"
    return
  fi
  mkdir -p .codex/agents

  # Write-if-absent ONLY — a user's later tuning (model, reasoning effort)
  # survives re-bootstrap, same policy as espalier/.doctor-cadence.
  if [ ! -f .codex/agents/harness-coder.toml ]; then
    cat > .codex/agents/harness-coder.toml << 'CODERAGENT'
# Espalier coder sub-agent (Codex). Instructions live in espalier/agents/harness-coder.md.
name = "harness-coder"
description = "Espalier implementation sub-agent — writes code strictly inside espalier/ rules; never reviews its own work"
sandbox_mode = "workspace-write"
developer_instructions = """
You are the harness-coder. Read espalier/agents/harness-coder.md and follow it
exactly. Before writing any code, read every file in espalier/rules/ and the
skill file espalier/skills/espalier-coding/SKILL.md. You implement; you never
review or approve your own output.
"""
CODERAGENT
    log "  wrote .codex/agents/harness-coder.toml"
  else
    log "  .codex/agents/harness-coder.toml exists — preserving"
  fi

  if [ ! -f .codex/agents/harness-reviewer.toml ]; then
    cat > .codex/agents/harness-reviewer.toml << 'REVIEWERAGENT'
# Espalier reviewer sub-agent (Codex). Instructions live in espalier/agents/harness-reviewer.md.
name = "harness-reviewer"
description = "Espalier review sub-agent — reviews diffs against espalier/ rules; writes ONLY its own review-record file"
sandbox_mode = "workspace-write"
developer_instructions = """
You are the harness-reviewer. Read espalier/agents/harness-reviewer.md and
follow it exactly. Your ONLY permitted write is your own review record file
(review-record.md in the active espalier/changes/ dir) — never source, tests,
or any other file. Review the diff as written by someone else.
"""
REVIEWERAGENT
    log "  wrote .codex/agents/harness-reviewer.toml"
  else
    log "  .codex/agents/harness-reviewer.toml exists — preserving"
  fi

  if [ ! -f .codex/agents/harness-security.toml ]; then
    cat > .codex/agents/harness-security.toml << 'SECURITYAGENT'
# Espalier security sub-agent (Codex). Instructions live in espalier/agents/harness-security.md.
name = "harness-security"
description = "Espalier security sub-agent — trust-boundary review against espalier/rules/security-standards.md; writes ONLY its own security-record file"
sandbox_mode = "workspace-write"
developer_instructions = """
You are the harness-security agent. Read espalier/agents/harness-security.md
and follow it exactly. Your ONLY permitted write is your own security record
file (security-record.md in the active espalier/changes/ dir, or
espalier/wiki/security-audit.md in repo-audit mode) — never source, tests, or
any other file.
"""
SECURITYAGENT
    log "  wrote .codex/agents/harness-security.toml"
  else
    log "  .codex/agents/harness-security.toml exists — preserving"
  fi
}

# --- Stage 7c: .github/copilot-instructions.md append (copilot) --------------

stage_copilot_instructions() {
  if ! want_copilot; then
    return
  fi
  log "Stage 7c: .github/copilot-instructions.md append (idempotent grep-guard)"
  if [ -f .github/copilot-instructions.md ] && grep -q "## Espalier" .github/copilot-instructions.md 2>/dev/null; then
    log "  copilot-instructions.md already has Espalier section — skipping"
    return
  fi
  if [ "$DRY_RUN" = "yes" ]; then
    echo "[dry-run] append Espalier section to .github/copilot-instructions.md"
    return
  fi
  mkdir -p .github
  cat >> .github/copilot-instructions.md << 'COPILOTTMPL'

## Espalier

This project uses Espalier for AI code quality — auto-discovered, project-specific guardrails.

**Always-loaded rules:** before writing or reviewing ANY code, read every file in
`espalier/rules/` (engineering-structure, coding-standards, development-process,
security-standards, production-standards). This instruction IS the load
mechanism — do not skip it. (If AGENTS.md also carries an `## Espalier`
section, it is the same contract — follow it once.)

**For any implementation work**, invoke the `espalier` skill (`/espalier <requirement>`) to execute the full pipeline.

**For bug fixes**, invoke `/espalier-fix <bug>` — 7 stages (0–7, no Stage 2).

**For questions** ("how does X work", "where is Y"), invoke `/espalier-ask <question>` — read-only, answers from espalier/ docs first.

**For a repo-wide security audit**, invoke `/espalier-audit` — inventories trust-boundary defects to `espalier/wiki/security-audit.md`; dispatch fixes via `/espalier-fix`.

**For multi-session planning** (an epic, a greenfield build — anything too big for one session), invoke `/espalier-map <idea>` — charts a decision map under `espalier/maps/`, one ticket per session; a cleared map hands back FILED slices for `/espalier`. It plans only, never codes.

**To execute a whole cleared map** over hours/days, invoke `/espalier-maprun <map-slug>` — one interactive master pass dispatches headless pipeline workers in isolated worktrees, merges what passes, and relays worker questions (requires a local Claude Code or Codex CLI for the workers).

**Agent definition:** Read `espalier/agent.md` for your operating instructions.

**Key principle:** The coder agent and reviewer agent are ALWAYS separate.
Never review your own code in the same invocation that wrote it.

### Platform mapping (Copilot)

Espalier's skill files use Claude Code vocabulary in places; on Copilot apply these mappings:

- `/espalier*` slash commands → the same-named Agent Skills (wired in
  `.github/skills/`; invoke via `/espalier…` in chat/CLI or let Copilot load
  them by description).
- `AskUserQuestion` → ask the user directly in chat and WAIT for the reply.
  Where a skill says "if you can call AskUserQuestion you are interactive",
  read it as: if you can ask the user in chat, you ARE interactive.
- "Spawn sub-agent harness-coder / harness-reviewer / harness-security with
  prompt X" → hand off to the matching custom agent (`@harness-coder`,
  `@harness-reviewer`, `@harness-security` — defined in `.github/agents/`)
  with the same prompt. If custom-agent handoff is unavailable in this
  surface, execute the roles inline in strict sequence and NEVER let the pass
  that wrote code also approve it: finish the coder role, then re-read
  `espalier/agents/harness-reviewer.md` and review the actual diff as if you
  had not written it.
- `.claude/settings.json` hooks → wired as Copilot hooks in
  `.github/hooks/espalier-gates.json` (Copilot CLI + cloud agent; VS Code
  chat does not run hooks — the pipeline's in-skill gates still apply).
- `$CLAUDE_PROJECT_DIR` in docs → the repo root (`git rev-parse --show-toplevel`).
COPILOTTMPL
}

# --- Stage 8d: .github/agents/*.agent.md sub-agents (copilot) -----------------

stage_copilot_agents() {
  if ! want_copilot; then
    return
  fi
  log "Stage 8d: .github/agents/harness-*.agent.md (write-if-absent)"
  if [ "$DRY_RUN" = "yes" ]; then
    echo "[dry-run] write .github/agents/harness-{coder,reviewer,security}.agent.md (if absent)"
    return
  fi
  mkdir -p .github/agents

  # Write-if-absent ONLY — user tuning (model, tools) survives re-bootstrap,
  # same policy as the codex .toml sub-agents.
  if [ ! -f .github/agents/harness-coder.agent.md ]; then
    cat > .github/agents/harness-coder.agent.md << 'CODERAGENTMD'
---
name: harness-coder
description: Espalier implementation sub-agent — writes code strictly inside espalier/ rules; never reviews its own work
---

You are the harness-coder. Read espalier/agents/harness-coder.md and follow it
exactly. Before writing any code, read every file in espalier/rules/ and the
skill file espalier/skills/espalier-coding/SKILL.md. You implement; you never
review or approve your own output.
CODERAGENTMD
    log "  wrote .github/agents/harness-coder.agent.md"
  else
    log "  .github/agents/harness-coder.agent.md exists — preserving"
  fi

  if [ ! -f .github/agents/harness-reviewer.agent.md ]; then
    cat > .github/agents/harness-reviewer.agent.md << 'REVIEWERAGENTMD'
---
name: harness-reviewer
description: Espalier review sub-agent — reviews diffs against espalier/ rules; writes ONLY its own review-record file
---

You are the harness-reviewer. Read espalier/agents/harness-reviewer.md and
follow it exactly. Your ONLY permitted write is your own review record file
(review-record.md in the active espalier/changes/ dir) — never source, tests,
or any other file. Review the diff as written by someone else.
REVIEWERAGENTMD
    log "  wrote .github/agents/harness-reviewer.agent.md"
  else
    log "  .github/agents/harness-reviewer.agent.md exists — preserving"
  fi

  if [ ! -f .github/agents/harness-security.agent.md ]; then
    cat > .github/agents/harness-security.agent.md << 'SECURITYAGENTMD'
---
name: harness-security
description: Espalier security sub-agent — trust-boundary review against espalier/rules/security-standards.md; writes ONLY its own security-record file
---

You are the harness-security agent. Read espalier/agents/harness-security.md
and follow it exactly. Your ONLY permitted write is your own security record
file (security-record.md in the active espalier/changes/ dir, or
espalier/wiki/security-audit.md in repo-audit mode) — never source, tests, or
any other file.
SECURITYAGENTMD
    log "  wrote .github/agents/harness-security.agent.md"
  else
    log "  .github/agents/harness-security.agent.md exists — preserving"
  fi
}

# --- Stage 8e: .github/hooks/espalier-gates.json (copilot) --------------------

stage_copilot_hooks() {
  if ! want_copilot; then
    return
  fi
  log "Stage 8e: .github/hooks/espalier-gates.json (write-if-absent)"
  if [ "$DRY_RUN" = "yes" ]; then
    echo "[dry-run] write .github/hooks/espalier-gates.json (if absent)"
    return
  fi
  mkdir -p .github/hooks
  # wire-only runs skip Stage 4 — make sure the adapter this json dispatches
  # to actually exists before referencing it.
  if [ ! -f espalier/hooks/copilot-hook-adapter.sh ] && [ -f "$PLUGIN_DIR/hook-templates/copilot-hook-adapter.sh" ]; then
    cp "$PLUGIN_DIR/hook-templates/copilot-hook-adapter.sh" espalier/hooks/copilot-hook-adapter.sh
    chmod +x espalier/hooks/copilot-hook-adapter.sh
    log "  copied espalier/hooks/copilot-hook-adapter.sh (wire-only run)"
  fi
  # Own file — Copilot loads every .github/hooks/*.json, so user hook files
  # are never touched. Write-if-absent: user edits (timeouts, matchers)
  # survive re-bootstrap.
  if [ -f .github/hooks/espalier-gates.json ]; then
    log "  .github/hooks/espalier-gates.json exists — preserving"
    return
  fi
  cat > .github/hooks/espalier-gates.json << 'COPILOTHOOKS'
{
  "version": 1,
  "hooks": {
    "preToolUse": [
      {
        "type": "command",
        "matcher": "bash|shell",
        "bash": "bash espalier/hooks/copilot-hook-adapter.sh pre-push-gate-wrapper.sh",
        "timeoutSec": 30
      },
      {
        "type": "command",
        "matcher": "edit|write|create|apply_patch|str_replace_editor",
        "bash": "bash espalier/hooks/copilot-hook-adapter.sh map-guard.sh",
        "timeoutSec": 5
      }
    ],
    "postToolUse": [
      {
        "type": "command",
        "matcher": "edit|write|create|apply_patch|str_replace_editor",
        "bash": "bash espalier/hooks/copilot-hook-adapter.sh post-edit-wrapper.sh",
        "timeoutSec": 10
      }
    ]
  }
}
COPILOTHOOKS
  log "  wrote .github/hooks/espalier-gates.json"
}

# --- Stage 9: Squash-merge decision + post-merge dispatcher -----------------

# Canonical integration ref (A3/R3): the remote+branch maintenance discipline
# targets. Detected once; values land in .espalier-config OUTSIDE the quoted
# ESPALIERCFG heredoc (no interpolation there — the v0.9 migration extracts its
# text literally).
detect_canonical_ref() {
  CANON_REMOTE=origin
  git remote 2>/dev/null | grep -qx upstream && CANON_REMOTE=upstream
  local ref
  ref=$(git symbolic-ref --short "refs/remotes/$CANON_REMOTE/HEAD" 2>/dev/null)
  # Strip exactly the remote prefix — a blanket 's|.*/||' would destroy a
  # branch like release/1.x.
  CANON_BRANCH=${ref#"$CANON_REMOTE"/}
  [ -n "$CANON_BRANCH" ] || CANON_BRANCH=main
}

_append_config_key() {   # KEY VALUE — newline-guarded append-if-missing
  grep -q "^$1:" espalier/.espalier-config 2>/dev/null && return 0
  if [ -s espalier/.espalier-config ] && [ -n "$(tail -c1 espalier/.espalier-config)" ]; then
    printf '\n' >> espalier/.espalier-config
  fi
  printf '%s: %s\n' "$1" "$2" >> espalier/.espalier-config
}

stage_merge_decision() {
  log "Stage 9: persist Phase 0 decisions + post-merge dispatcher"
  if [ "$DRY_RUN" = "yes" ]; then
    echo "[dry-run] write espalier/.merge-hook-decision = $MERGE_DECISION"
    echo "[dry-run] write espalier/.platforms = $PLATFORMS"
    echo "[dry-run] write espalier/.doctor-cadence = $DOCTOR_CADENCE (if absent)"
    echo "[dry-run] write espalier/.espalier-config = review-round caps (if absent)"
    echo "[dry-run] append canonical-remote/canonical-branch keys to espalier/.espalier-config (if missing)"
    echo "[dry-run] install post-merge dispatcher (drift-detect every merge; backlink if installed)"
    return
  fi

  echo "$MERGE_DECISION" > espalier/.merge-hook-decision

  # espalier/.platforms — tracked; which agent platforms this repo is wired for.
  # $PLATFORMS is already the union of the flag and any previous value (resolved
  # at preflight), so a later "add codex" wire-only run extends, never shrinks.
  echo "$PLATFORMS" > espalier/.platforms

  # espalier/.doctor-cadence — tracked, cadence-line only. Written ONCE; never
  # auto-rewritten, so a user's later edit to the cadence survives re-bootstrap.
  if [ -f espalier/.doctor-cadence ]; then
    log "  espalier/.doctor-cadence already exists — preserving"
  else
    echo "cadence: $DOCTOR_CADENCE" > espalier/.doctor-cadence
    log "  wrote espalier/.doctor-cadence = $DOCTOR_CADENCE"
  fi

  # espalier/.espalier-config — tracked, review-round escalation caps. Written
  # ONCE; never auto-rewritten, so a user's later tuning survives re-bootstrap.
  # Read at runtime by the orchestrator (grep + integer parse, like pre-push-gate).
  detect_canonical_ref
  if [ -f espalier/.espalier-config ]; then
    log "  espalier/.espalier-config already exists — preserving (appending missing keys only)"
    _append_config_key canonical-remote "$CANON_REMOTE"
    _append_config_key canonical-branch "$CANON_BRANCH"
    _append_config_key max-open-tickets 9
  else
    cat > espalier/.espalier-config << 'ESPALIERCFG'
# Espalier pipeline tuning. Key-value, one per line: `<key>: <integer>`.
# Read at runtime by the orchestrator; `#` comment lines and blanks are ignored.
# Edit a value to tune; it survives re-bootstrap (never auto-rewritten).
# On any missing file/key the orchestrator falls back to 3.

# Escalation caps: how many review rounds before the pipeline stops and asks a
# human, per review type. A round = one reviewer pass + (on P0) one coder re-spawn.
# Keep value lines digit-clean (the reader greps the first integer on the line).
# Stage 2 requirements review:
max-req-rounds: 3
# Stage 4 coder<->reviewer/security panel (shared correctness+security P0 counter):
max-code-rounds: 3
# Stage 6 test review:
max-test-rounds: 3

# Whole-pipeline safety: total cross-stage rollbacks allowed before human takeover.
# (Separate from the fixed "no more than 3 stages in a single rollback" span guard.)
max-rollbacks: 3

# /espalier-map anti-waterfall cap: max OPEN decision tickets per map before
# charting must narrow the destination, split the map, or raise this value.
max-open-tickets: 9
ESPALIERCFG
    # Canonical-ref keys are DYNAMIC (detected) — appended after the quoted
    # heredoc, never interpolated into it.
    printf '\n# Canonical integration ref for team maintenance discipline\n# (detected at init from the remote HEAD; string values — edit if wrong).\n' \
      >> espalier/.espalier-config
    _append_config_key canonical-remote "$CANON_REMOTE"
    _append_config_key canonical-branch "$CANON_BRANCH"
    log "  wrote espalier/.espalier-config (review-round + rollback caps, default 3; canonical ref $CANON_REMOTE/$CANON_BRANCH)"
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
      # Not hardcoded .git/hooks: in a LINKED WORKTREE `.git` is a pointer
      # file and hooks live in the shared common dir — --git-path resolves
      # both layouts (and returns .git/hooks in a normal checkout).
      HOOK_DST="$(git rev-parse --git-path hooks 2>/dev/null)/post-merge"
      [ "$HOOK_DST" = "/post-merge" ] && HOOK_DST=".git/hooks/post-merge"
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
    case "$HOOK_DST_PARENT" in
      .git/hooks|*/.git/hooks)
        # The resolved git hooks dir itself is missing — creating it inside
        # a broken/absent .git would mask the real problem.
        log "  ERROR: $HOOK_DST_PARENT does not exist (run 'git init' first?)"
        return
        ;;
    esac
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

# --- Stage 10: .gitignore/.gitattributes/CODEOWNERS append -------------------

stage_codeowners() {
  # A4/R4 — CODEOWNERS marker block routing rule/wiki edits to their owners.
  # Enforcement is ADVISORY until "Require review from Code Owners" branch
  # protection is on — not verified here.
  if [ -z "$CODEOWNERS_RULES" ] && [ -z "$CODEOWNERS_WIKI" ]; then
    log "  CODEOWNERS: no --codeowners-* handle given — skipping"
    return 0
  fi
  # Normalize handles: '@' prefixed if missing; no placeholders — an
  # unanswered handle's line is omitted entirely.
  case "$CODEOWNERS_RULES" in ""|@*) ;; *) CODEOWNERS_RULES="@$CODEOWNERS_RULES" ;; esac
  case "$CODEOWNERS_WIKI"  in ""|@*) ;; *) CODEOWNERS_WIKI="@$CODEOWNERS_WIKI" ;; esac
  # Target file: GitHub's own search order — first existing wins (root-first
  # would edit a file GitHub ignores whenever .github/CODEOWNERS exists).
  local co="" c
  for c in .github/CODEOWNERS CODEOWNERS docs/CODEOWNERS; do
    [ -f "$c" ] && { co="$c"; break; }
  done
  [ -z "$co" ] && co=".github/CODEOWNERS"
  if [ "$DRY_RUN" = "yes" ]; then
    echo "[dry-run] write ESPALIER OWNERS block to $co (rules=$CODEOWNERS_RULES wiki=$CODEOWNERS_WIKI)"
    return 0
  fi
  mkdir -p "$(dirname "$co")" 2>/dev/null || true
  local block tmp
  block=$(mktemp) || return 1
  {
    echo "# >>> ESPALIER OWNERS v1 >>> (managed by espalier bootstrap — do not edit between markers)"
    [ -n "$CODEOWNERS_RULES" ] && echo "espalier/rules/ $CODEOWNERS_RULES"
    [ -n "$CODEOWNERS_WIKI" ]  && echo "espalier/wiki/ $CODEOWNERS_WIKI"
    echo "# <<< ESPALIER OWNERS v1 <<<"
  } > "$block"
  if [ -f "$co" ] && grep -qF ">>> ESPALIER OWNERS v1 >>>" "$co"; then
    # Replace within markers; everything outside them is untouched.
    tmp=$(mktemp) || { rm -f "$block"; return 1; }
    awk -v bf="$block" '
      /^# >>> ESPALIER OWNERS v1 >>>/ { inb=1; while ((getline l < bf) > 0) print l; close(bf); next }
      /^# <<< ESPALIER OWNERS v1 <<</ { inb=0; next }
      !inb { print }
    ' "$co" > "$tmp" && mv "$tmp" "$co"
  else
    if [ -s "$co" ] && [ -n "$(tail -c1 "$co")" ]; then
      printf '\n' >> "$co"
    fi
    cat "$block" >> "$co"
  fi
  rm -f "$block"
  log "  CODEOWNERS block written to $co (advisory until branch protection requires code-owner review)"
}

stage_gitignore() {
  log "Stage 10: .gitignore/.gitattributes/CODEOWNERS append (idempotent + newline guard)"
  if [ "$DRY_RUN" = "yes" ]; then
    echo "[dry-run] append espalier cache + drift-sidecar entries to .gitignore"
    echo "[dry-run] append 'espalier/.ask-gaps.tsv merge=union' to .gitattributes"
    stage_codeowners
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
  # .gitattributes — the ONE union attribute in scope (A1): .ask-gaps.tsv is
  # genuinely append-only. Deliberately NOT here: .conventions.tsv (its status
  # writer edits rows in place — union would resurrect edited rows) and
  # .doctor-stamp (single-line last-writer-wins — union would corrupt it into
  # two lines). Never add attributes for either.
  entry="espalier/.ask-gaps.tsv merge=union"
  if ! grep -qxF "$entry" .gitattributes 2>/dev/null; then
    if [ -s .gitattributes ] && [ -n "$(tail -c1 .gitattributes)" ]; then
      printf '\n' >> .gitattributes
    fi
    echo "$entry" >> .gitattributes
  fi
  stage_codeowners
}

# --- Stage 11: Validation (parallel — R6) -----------------------------------

stage_validate() {
  # Check count is platform-dependent: 46 base (1-46) + 5 codex (47-51) +
  # 5 copilot (52-56) + 6 unconditional base (57-62 — appended AFTER the
  # platform blocks so shipped platform IDs stay stable; base numbering is
  # non-contiguous by design; 57-58 landed in v0.16, 59-60 in v0.18,
  # 61-62 in v0.19). Numbering is FIXED per platform; copilot without codex
  # still renders 47-51 as skip lines so the sequence stays contiguous. A
  # greenfield Pass 1 (espalier/.greenfield present) renders every
  # Phase-2-artifact check (5, 9, 15-16, 30-32, 34-36, 38-45) as a
  # pending-skip — count and numbering unchanged.
  local TOTAL_CHECKS=52
  if want_copilot; then
    TOTAL_CHECKS=62
  elif want_codex; then
    TOTAL_CHECKS=57
  fi
  log "Stage 11: validation ($TOTAL_CHECKS checks — R6; platforms: $PLATFORMS)"
  if [ "$DRY_RUN" = "yes" ]; then
    echo "[dry-run] would run $TOTAL_CHECKS validation checks (skipped — nothing to validate yet)"
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
      echo "[$n/$TOTAL_CHECKS] OK   $check_name" > "$tmpdir/$idx"
    else
      local err
      err=$( ( eval "$cmd" ) 2>&1 | head -1 )
      echo "[$n/$TOTAL_CHECKS] FAIL $check_name: $err" > "$tmpdir/$idx"
      echo "fail" > "$tmpdir/$idx.fail"
    fi
  }

  # For checks whose platform isn't targeted (e.g. .claude/ wiring on a
  # codex-only install): report OK with a skip note, keep numbering stable.
  skip_check() {
    local n=$1 check_name=$2 why=$3
    local idx
    idx=$(printf '%02d' "$n")
    echo "[$n/$TOTAL_CHECKS] OK   $check_name (skipped — $why)" > "$tmpdir/$idx"
  }

  # Greenfield Pass 1 (espalier/.greenfield present): every Phase-2-written
  # artifact (rules, agent.md, sub-agents, substituted skills, wiki) does not
  # exist yet — Pass 2 binds them from the decision map. Those checks render
  # as pending-skips; wiring/pure-copy checks stay live.
  gf() { [ -f espalier/.greenfield ]; }

  # Check #25 — invoked DIRECTLY (not via run_check): the run_check harness
  # discards stdout, which would swallow #25's per-tier table.
  run_check_25() {
    [ -f espalier/.drift-state.tsv ] || { echo "[25/$TOTAL_CHECKS] OK   stale-tiers: no drift"; return 0; }
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
    echo "[25/$TOTAL_CHECKS] stale-tiers: fresh=$fresh aging=$aging stale=$stale critical=$critical expired=$expired"
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

  if want_claude; then
    run_check  1 "rules-load"          'ls .claude/rules/espalier-*.md' &
    run_check  2 "skills-load"         'ls -d .claude/skills/espalier-coding .claude/skills/espalier-review .claude/skills/espalier-security .claude/skills/espalier-testing .claude/skills/espalier-requirements .claude/skills/espalier-grill .claude/skills/espalier .claude/skills/espalier-fix .claude/skills/espalier-prune .claude/skills/espalier-doctor .claude/skills/espalier-ask .claude/skills/espalier-audit .claude/skills/espalier-map .claude/skills/espalier-maprun' &
    run_check  3 "agents-load"         'ls .claude/agents/harness-coder.md .claude/agents/harness-reviewer.md .claude/agents/harness-security.md' &
    run_check  4 "hooks-configured"    'grep -q "espalier/hooks" .claude/settings.json' &
    if gf; then
      skip_check 5 "symlinks-valid" "pending greenfield Pass 2"
    else
      run_check  5 "symlinks-valid"      '[ -L .claude/rules/espalier-structure.md ] && [ -e .claude/rules/espalier-structure.md ]' &
    fi
  else
    skip_check 1 "rules-load"       "claude not targeted"
    skip_check 2 "skills-load"      "claude not targeted"
    skip_check 3 "agents-load"      "claude not targeted"
    skip_check 4 "hooks-configured" "claude not targeted"
    skip_check 5 "symlinks-valid"   "claude not targeted"
  fi
  run_check  6 "hooks-executable"    'test -x espalier/hooks/post-edit-wrapper.sh && test -x espalier/hooks/pre-push-gate.sh && test -x espalier/hooks/pre-push-gate-wrapper.sh' &
  run_check  7 "state-template"      'test -f espalier/changes/_template/pipeline-state.md' &
  if want_claude; then
    run_check  8 "claudemd-updated"    'grep -q "## Espalier" CLAUDE.md' &
  else
    skip_check 8 "claudemd-updated" "claude not targeted"
  fi
  if gf; then
    skip_check 9 "espalier-agent-md" "pending greenfield Pass 2"
  else
    run_check  9 "espalier-agent-md"   'test -f espalier/agent.md' &
  fi
  run_check 10 "espalier-pipeline-md" 'test -f espalier/pipeline.md' &
  run_check 11 "skill-name-parity"   'for f in espalier/skills/*/SKILL.md; do dir=$(basename $(dirname "$f")); name=$(grep "^name:" "$f" | awk "{print \$2}"); [ "$dir" = "$name" ] || exit 1; done' &
  run_check 12 "typed-changes-dirs"  '[ -d espalier/changes/feat ] && [ -d espalier/changes/fix ] && [ -d espalier/changes/refactor ]' &
  if want_claude; then
    run_check 13 "espalier-fix-skill"  'test -f .claude/skills/espalier-fix/SKILL.md' &
    run_check 14 "espalier-fix-name"   'grep -q "^name: espalier-fix" .claude/skills/espalier-fix/SKILL.md' &
  else
    run_check 13 "espalier-fix-skill"  'test -f espalier/skills/espalier-fix/SKILL.md' &
    run_check 14 "espalier-fix-name"   'grep -q "^name: espalier-fix" espalier/skills/espalier-fix/SKILL.md' &
  fi
  if gf; then
    skip_check 15 "rules-engineering" "pending greenfield Pass 2"
    skip_check 16 "rules-standards"   "pending greenfield Pass 2"
  else
    run_check 15 "rules-engineering"   'test -f espalier/rules/engineering-structure.md' &
    run_check 16 "rules-standards"     'test -f espalier/rules/coding-standards.md' &
  fi
  run_check 17 "merge-decision"      'grep -qE "^(not-needed|installed|fuzzy-allowed|skip-only|never-ask|ask-later)$" espalier/.merge-hook-decision' &
  run_check 18 "hook-template-copy"  'test -f espalier/hooks/post-merge-backlink.sh && test -x espalier/hooks/post-merge-backlink.sh' &
  run_check 19 "lookup-helpers"      'test -f espalier/hooks/lookup-helpers.sh' &
  run_check 20 "post-merge-dispatcher" '_hd=$(git rev-parse --git-path hooks 2>/dev/null); [ -n "$_hd" ] || _hd=.git/hooks; grep -qE "ESPALIER_POSTMERGE_DISPATCH" "$_hd/post-merge" 2>/dev/null || grep -qE "ESPALIER_POSTMERGE_DISPATCH" .husky/post-merge 2>/dev/null' &
  run_check 21 "rebuild-script"      'test -x espalier/hooks/rebuild-commit-index.sh' &
  run_check 22 "gitignore-cache"     'grep -qxF "espalier/.commit-index.tsv" .gitignore' &
  run_check 23 "rebuild-runs"        'bash espalier/hooks/rebuild-commit-index.sh && test -f espalier/.commit-index.tsv' &
  run_check 24 "cache-tsv-format"    '[ ! -s espalier/.commit-index.tsv ] || awk -F"\t" "NF != 4 { exit 1 }" espalier/.commit-index.tsv' &
  run_check 26 "drift-state-format"  '[ ! -s espalier/.drift-state.tsv ] || awk -F"\t" "NF != 4 { exit 1 }" espalier/.drift-state.tsv' &
  run_check 27 "conventions-format"  '{ [ ! -s espalier/.conventions.tsv ] || awk -F"\t" "NF != 5 && NF != 6 { exit 1 }" espalier/.conventions.tsv; } && { [ ! -d espalier/conventions ] || ! ls espalier/conventions/*.tsv >/dev/null 2>&1 || awk -F"\t" "NF != 5 && NF != 6 { exit 1 }" espalier/conventions/*.tsv; }' &
  run_check 28 "doctor-cadence"      '[ ! -f espalier/.doctor-cadence ] || grep -qE "^cadence: (every-change|weekly|monthly|manual)$" espalier/.doctor-cadence' &
  if gf; then
    # 29/33 stay live (pure-copy skills exist even in Pass 1); the security/
    # production artifacts are Phase 2 writes.
    skip_check 30 "security-rule"    "pending greenfield Pass 2"
    skip_check 31 "security-agent"   "pending greenfield Pass 2"
    skip_check 32 "security-skill"   "pending greenfield Pass 2"
    skip_check 34 "audit-mode"       "pending greenfield Pass 2"
    skip_check 35 "production-rule"  "pending greenfield Pass 2"
    skip_check 36 "production-file"  "pending greenfield Pass 2"
    if want_claude; then
      run_check 29 "espalier-ask-skill"  'test -f .claude/skills/espalier-ask/SKILL.md' &
      run_check 33 "audit-skill"         'test -f .claude/skills/espalier-audit/SKILL.md' &
    else
      run_check 29 "espalier-ask-skill"  'test -f espalier/skills/espalier-ask/SKILL.md' &
      run_check 33 "audit-skill"         'test -f espalier/skills/espalier-audit/SKILL.md' &
    fi
  elif want_claude; then
    run_check 29 "espalier-ask-skill"  'test -f .claude/skills/espalier-ask/SKILL.md' &
    run_check 30 "security-rule"       '[ -L .claude/rules/espalier-security.md ] && [ -e .claude/rules/espalier-security.md ]' &
    run_check 31 "security-agent"      'test -f .claude/agents/harness-security.md' &
    run_check 32 "security-skill"      'test -f .claude/skills/espalier-security/SKILL.md' &
    run_check 33 "audit-skill"         'test -f .claude/skills/espalier-audit/SKILL.md' &
    run_check 34 "audit-mode"          'grep -qF "## Repo-Audit Mode" espalier/agents/harness-security.md' &
    run_check 35 "production-rule"     '[ -L .claude/rules/espalier-production.md ] && [ -e .claude/rules/espalier-production.md ]' &
    run_check 36 "production-file"     'test -f espalier/rules/production-standards.md' &
  else
    run_check 29 "espalier-ask-skill"  'test -f espalier/skills/espalier-ask/SKILL.md' &
    run_check 30 "security-rule"       'test -f espalier/rules/security-standards.md' &
    run_check 31 "security-agent"      'test -f espalier/agents/harness-security.md' &
    run_check 32 "security-skill"      'test -f espalier/skills/espalier-security/SKILL.md' &
    run_check 33 "audit-skill"         'test -f espalier/skills/espalier-audit/SKILL.md' &
    run_check 34 "audit-mode"          'grep -qF "## Repo-Audit Mode" espalier/agents/harness-security.md' &
    run_check 35 "production-rule"     'test -f espalier/rules/production-standards.md' &
    run_check 36 "production-file"     'test -f espalier/rules/production-standards.md' &
  fi
  run_check 37 "scout-prompts"      'test -f espalier/.scout-prompts.md' &
  # 38-46: LLM-written artifacts (Phase 2) — existence checks with fix hints.
  # Greenfield Pass 1: Phase 2 has not run yet (it binds the decision map in
  # Pass 2), so 38-45 render as pending-skips instead of failures.
  if [ -f espalier/.greenfield ]; then
    skip_check 38 "phase2-coding-skill"       "pending greenfield Pass 2"
    skip_check 39 "phase2-review-skill"       "pending greenfield Pass 2"
    skip_check 40 "phase2-testing-skill"      "pending greenfield Pass 2"
    skip_check 41 "wiki-architecture"         "pending greenfield Pass 2"
    skip_check 42 "wiki-data-models"          "pending greenfield Pass 2"
    skip_check 43 "wiki-critical-paths"       "pending greenfield Pass 2"
    skip_check 44 "wiki-external-services"    "pending greenfield Pass 2"
    skip_check 45 "rules-development-process" "pending greenfield Pass 2"
  else
    run_check 38 "phase2-coding-skill (fix: re-run espalier-init Phase 2)"   'test -f espalier/skills/espalier-coding/SKILL.md' &
    run_check 39 "phase2-review-skill (fix: re-run espalier-init Phase 2)"   'test -f espalier/skills/espalier-review/SKILL.md' &
    run_check 40 "phase2-testing-skill (fix: re-run espalier-init Phase 2)"  'test -f espalier/skills/espalier-testing/SKILL.md' &
    run_check 41 "wiki-architecture (fix: re-run espalier-init Phase 2)"     'test -f espalier/wiki/architecture.md' &
    run_check 42 "wiki-data-models (fix: re-run espalier-init Phase 2)"      'test -f espalier/wiki/data-models.md' &
    run_check 43 "wiki-critical-paths (fix: re-run espalier-init Phase 2)"   'test -f espalier/wiki/critical-paths.md' &
    run_check 44 "wiki-external-services (fix: re-run espalier-init Phase 2)" 'test -f espalier/wiki/external-services.md' &
    run_check 45 "rules-development-process (fix: re-run espalier-init Phase 2)" 'test -f espalier/rules/development-process.md' &
  fi
  run_check 46 "layer-boundaries-hook (fix: Phase 2 writes it; --lang=unsupported writes a no-op)" 'test -f espalier/hooks/check-layer-boundaries.sh && test -x espalier/hooks/check-layer-boundaries.sh' &
  # 47-51: codex wiring (skip-rendered when copilot alone keeps numbering contiguous).
  if want_codex; then
    run_check 47 "codex-skills-load"   'ls -d .agents/skills/espalier-coding .agents/skills/espalier-review .agents/skills/espalier-security .agents/skills/espalier-testing .agents/skills/espalier-requirements .agents/skills/espalier-grill .agents/skills/espalier .agents/skills/espalier-fix .agents/skills/espalier-prune .agents/skills/espalier-doctor .agents/skills/espalier-ask .agents/skills/espalier-audit .agents/skills/espalier-map .agents/skills/espalier-maprun' &
    run_check 48 "codex-symlinks-valid" '[ -L .agents/skills/espalier ] && [ -e .agents/skills/espalier ]' &
    run_check 49 "codex-agents-toml"   'grep -q "^name = \"harness-coder\"" .codex/agents/harness-coder.toml && grep -q "^name = \"harness-reviewer\"" .codex/agents/harness-reviewer.toml && grep -q "^name = \"harness-security\"" .codex/agents/harness-security.toml' &
    run_check 50 "codex-hooks-configured" 'grep -q "espalier/hooks" .codex/config.toml' &
    run_check 51 "codex-agentsmd"      'grep -q "## Espalier" AGENTS.md' &
  elif want_copilot; then
    skip_check 47 "codex-skills-load"     "codex not targeted"
    skip_check 48 "codex-symlinks-valid"  "codex not targeted"
    skip_check 49 "codex-agents-toml"     "codex not targeted"
    skip_check 50 "codex-hooks-configured" "codex not targeted"
    skip_check 51 "codex-agentsmd"        "codex not targeted"
  fi
  # 52-56: copilot wiring (only when copilot is a target platform).
  if want_copilot; then
    run_check 52 "copilot-skills-load"  'ls -d .github/skills/espalier-coding .github/skills/espalier-review .github/skills/espalier-security .github/skills/espalier-testing .github/skills/espalier-requirements .github/skills/espalier-grill .github/skills/espalier .github/skills/espalier-fix .github/skills/espalier-prune .github/skills/espalier-doctor .github/skills/espalier-ask .github/skills/espalier-audit .github/skills/espalier-map .github/skills/espalier-maprun' &
    run_check 53 "copilot-symlinks-valid" '[ -L .github/skills/espalier ] && [ -e .github/skills/espalier ]' &
    run_check 54 "copilot-agents"       'grep -q "^name: harness-coder" .github/agents/harness-coder.agent.md && grep -q "^name: harness-reviewer" .github/agents/harness-reviewer.agent.md && grep -q "^name: harness-security" .github/agents/harness-security.agent.md' &
    run_check 55 "copilot-hooks-json"   'python3 -c "import json; json.load(open(\".github/hooks/espalier-gates.json\"))" && grep -q "copilot-hook-adapter" .github/hooks/espalier-gates.json && test -x espalier/hooks/copilot-hook-adapter.sh' &
    run_check 56 "copilot-instructions" 'grep -q "## Espalier" .github/copilot-instructions.md' &
  fi
  # 57-60: base checks (57-58 v0.16.0 multi-dev floor, 59-60 v0.18.0 map
  # lane) — run UNCONDITIONALLY, regardless of --platforms; appended after
  # the platform blocks so the shipped IDs 47-56 stay stable.
  run_check 57 "gitattributes-union"  'grep -qxF "espalier/.ask-gaps.tsv merge=union" .gitattributes' &
  run_check 58 "canonical-ref-keys"   'grep -qE "^canonical-remote: .+" espalier/.espalier-config && grep -qE "^canonical-branch: .+" espalier/.espalier-config' &
  if want_claude; then
    run_check 59 "map-skill"          'test -f .claude/skills/espalier-map/SKILL.md && grep -q "^name: espalier-map" .claude/skills/espalier-map/SKILL.md' &
    run_check 60 "map-guard"          'test -x espalier/hooks/map-guard.sh && grep -q "map-guard" .claude/settings.json' &
    run_check 61 "maprun-skill"       'test -f .claude/skills/espalier-maprun/SKILL.md && grep -q "^name: espalier-maprun" .claude/skills/espalier-maprun/SKILL.md' &
  else
    run_check 59 "map-skill"          'test -f espalier/skills/espalier-map/SKILL.md && grep -q "^name: espalier-map" espalier/skills/espalier-map/SKILL.md' &
    run_check 60 "map-guard"          'test -x espalier/hooks/map-guard.sh' &
    run_check 61 "maprun-skill"       'test -f espalier/skills/espalier-maprun/SKILL.md && grep -q "^name: espalier-maprun" espalier/skills/espalier-maprun/SKILL.md' &
  fi
  run_check 62 "maprun-engine"        'test -f espalier/hooks/maprun.py && test -x espalier/hooks/maprun-dispatch.sh && test -x espalier/hooks/maprun-merge.sh && test -x espalier/hooks/maprun-integration.sh && test -x espalier/hooks/maprun-verify.sh' &

  wait

  # Emit deterministic order: 1-24 (sorted), then #25 (serial — its tier table
  # must reach stdout, which the run_check harness discards), then 26-60.
  cat "$tmpdir"/0? "$tmpdir"/1? "$tmpdir"/2[0-4] 2>/dev/null
  run_check_25 || echo "fail" > "$tmpdir/25.fail"
  cat "$tmpdir"/2[6-9] "$tmpdir"/3? "$tmpdir"/4[0-9] "$tmpdir"/5[0-9] "$tmpdir"/6[0-2] 2>/dev/null

  failed=$(ls "$tmpdir"/*.fail 2>/dev/null | wc -l | tr -d ' ')
  rm -rf "$tmpdir"

  if [ "$failed" -gt 0 ]; then
    log "Validation: $failed/$TOTAL_CHECKS FAILED"
    return 1
  fi
  log "Validation: $TOTAL_CHECKS/$TOTAL_CHECKS passed"
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
    stage_agentsmd
    stage_copilot_instructions
    stage_settings_json
    stage_codex_config
    stage_codex_agents
    stage_copilot_agents
    stage_copilot_hooks
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
    stage_mkdirs
    stage_symlinks
    stage_state_template
    stage_claudemd
    stage_agentsmd
    stage_copilot_instructions
    stage_settings_json
    stage_codex_config
    stage_codex_agents
    stage_copilot_agents
    stage_copilot_hooks
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
