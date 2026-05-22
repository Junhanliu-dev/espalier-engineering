#!/bin/bash
# Migrate a v0.3.x harness-engineering target repo to v0.4.0 Espalier layout.
#
# Run from the TARGET project root. Idempotent. Safe to re-run.
# Use --dry-run to preview every change before applying.
#
# What this script does:
#   1. git mv harness/ → espalier/
#   2. Rename child skills: harness-{coding,review,testing,requirements,fix} → espalier-*
#                           harness-run → espalier  (bare slash command /espalier)
#   3. Rewrite path refs (harness/ → espalier/) inside:
#        - espalier/agent.md
#        - espalier/pipeline.md
#        - espalier/agents/harness-{coder,reviewer}.md  (paths only; agent names KEPT)
#        - espalier/skills/*/SKILL.md  (cross-refs)
#        - espalier/hooks/*.sh
#        - CLAUDE.md  (## Harness Engineering → ## Espalier)
#        - .gitignore
#        - .git/hooks/post-merge or .husky/post-merge  (if present)
#   4. Rewrite skill-name refs (per-term, ordered to avoid harness-coder collision):
#        harness-run → espalier
#        harness-{coding,review,testing,requirements,fix} → espalier-*
#        (harness-coder, harness-reviewer untouched)
#   5. Rebuild .claude/{rules,skills,agents}/* symlinks pointing at espalier/
#   6. Patch .claude/settings.json hook command paths (harness/hooks/ → espalier/hooks/)
#   7. Refresh espalier/.commit-index.tsv (delete + regen from pipeline-state.md)
#   8. Verify (10 checks) — idempotency-safe to re-run.
#
# What this script does NOT do:
#   - Rewrite history inside espalier/changes/*/pipeline-state.md (frozen text).
#     Pass --rewrite-history to opt in.
#   - Rename `harness-coder` / `harness-reviewer` agents (kept for stability).
#
# Usage:
#   bash migrate-v0.3-to-v0.4.sh [--dry-run] [--yes] [--rewrite-history] [--plugin-dir=<path>]

set -u

DRY_RUN=no
SKIP_PROMPT=no
REWRITE_HISTORY=no
PLUGIN_DIR="${ESPALIER_PLUGIN_DIR:-${HARNESS_PLUGIN_DIR:-}}"

for arg in "$@"; do
  case "$arg" in
    --dry-run)         DRY_RUN=yes ;;
    --yes)             SKIP_PROMPT=yes ;;
    --rewrite-history) REWRITE_HISTORY=yes ;;
    --plugin-dir=*)    PLUGIN_DIR="${arg#--plugin-dir=}" ;;
    -h|--help)
      sed -n '2,38p' "$0"
      exit 0
      ;;
    *)
      echo "ERROR: unknown flag: $arg (use --help)" >&2
      exit 2
      ;;
  esac
done

run() {
  if [ "$DRY_RUN" = "yes" ]; then
    echo "[dry-run] $*"
  else
    echo "+ $*"
    eval "$@"
  fi
}

log() { echo "[migrate v0.3→v0.4] $*"; }

# sed -i differs between BSD (macOS, needs '' arg) and GNU (Linux, no arg)
if [ "$(uname)" = "Darwin" ]; then
  SED_INPLACE=(sed -i '')
else
  SED_INPLACE=(sed -i)
fi

# Per-term skill rename map (ORDER MATTERS: harness-run before harness- prefix)
SKILL_RENAMES=(
  's|harness-run|espalier|g'
  's|harness-coding|espalier-coding|g'
  's|harness-review|espalier-review|g'
  's|harness-testing|espalier-testing|g'
  's|harness-requirements|espalier-requirements|g'
  's|harness-fix|espalier-fix|g'
  's|harness-engineering|espalier-init|g'
  's|harness-migrate|espalier-migrate|g'
)

# Apply per-term skill renames (NOT agent names) + dir path rename to a file.
# Order critical:
#   1. Skill name renames (multi-char prefix-disambiguation guards harness-coder)
#   2. Dir path rename (harness/ → espalier/) — separate step so it doesn't
#      touch harness-coder / harness-reviewer identifiers.
_rewrite_file() {
  local f="$1"
  [ -f "$f" ] || return 0

  if [ "$DRY_RUN" = "yes" ]; then
    echo "[dry-run] rewrite $f"
    return 0
  fi

  for expr in "${SKILL_RENAMES[@]}"; do
    "${SED_INPLACE[@]}" -E "$expr" "$f"
  done
  # Now rewrite dir prefix. Only `harness/` (word-boundary before, slash after).
  # Don't touch `harness-coder`, `harness-reviewer`, `harness-engineering` etc.
  "${SED_INPLACE[@]}" -E -e 's|^harness/|espalier/|' -e 's|([^a-zA-Z0-9_-])harness/|\1espalier/|g' "$f"
}

# --- Preflight ---------------------------------------------------------------

if [ ! -d "harness" ]; then
  if [ -d "espalier" ]; then
    echo "Already migrated (espalier/ present, harness/ absent). Nothing to do."
    exit 0
  fi
  echo "ERROR: must run from target repo root (with harness/ directory)." >&2
  exit 1
fi

if [ -d "espalier" ]; then
  echo "ERROR: espalier/ already exists alongside harness/." >&2
  echo "Aborting to avoid clobbering. Resolve by hand, then re-run." >&2
  exit 1
fi

if [ ! -f "harness/.merge-hook-decision" ]; then
  echo "ERROR: harness/.merge-hook-decision missing." >&2
  echo "This script migrates v0.3.x → v0.4.0. For v0.1.x → v0.2.x, run migrate-v0.1-to-v0.2.sh first." >&2
  exit 1
fi

cat << 'EOF'

Espalier rename migration (v0.3.x → v0.4.0)

Plan:
  1. git mv harness/ → espalier/
  2. Rename child skills (harness-coding → espalier-coding, etc.)
  3. Rewrite path refs inside all skill/agent/hook files
  4. Patch CLAUDE.md, .gitignore, .git/hooks/post-merge
  5. Rebuild .claude/* symlinks
  6. Patch .claude/settings.json hook paths
  7. Regen espalier/.commit-index.tsv

Sub-agent names harness-coder / harness-reviewer are KEPT (internal identifiers).

EOF

if [ "$DRY_RUN" = "yes" ]; then
  echo "Mode: DRY RUN (no changes will be written)"
elif [ "$SKIP_PROMPT" != "yes" ]; then
  read -p "Apply migration? [y/N]: " confirm
  case "$confirm" in
    y|Y|yes) ;;
    *) echo "Cancelled."; exit 0 ;;
  esac
fi

# --- Step 1: git mv harness → espalier --------------------------------------

log "Step 1: rename harness/ → espalier/"
if [ "$DRY_RUN" = "yes" ]; then
  echo "[dry-run] git mv harness espalier"
else
  git mv harness espalier 2>/dev/null || mv harness espalier
fi

# --- Step 2: rename child skill directories ---------------------------------
#
# Parallel indexed arrays (bash 3.2 compatible — macOS default).
# Do NOT use `declare -A` (associative arrays = bash 4+ only); silently
# becomes a no-op on macOS, then `${!ARRAY[@]}` trips set -u.

log "Step 2: rename child skill directories"
SKILL_OLD=(harness-coding harness-review harness-testing harness-requirements harness-fix harness-run)
SKILL_NEW=(espalier-coding espalier-review espalier-testing espalier-requirements espalier-fix espalier)

for i in "${!SKILL_OLD[@]}"; do
  old="${SKILL_OLD[$i]}"
  new="${SKILL_NEW[$i]}"
  src="espalier/skills/$old"
  dst="espalier/skills/$new"
  if [ "$DRY_RUN" = "yes" ]; then
    [ -d "$src" ] && echo "[dry-run] git mv $src $dst"
    continue
  fi
  if [ -d "$src" ]; then
    git mv "$src" "$dst" 2>/dev/null || mv "$src" "$dst"
  fi
done

# --- Step 3: rewrite per-skill SKILL.md `name:` frontmatter + cross-refs ----

log "Step 3: rewrite SKILL.md frontmatter + cross-refs"
for skill_dir in espalier/skills/*/; do
  [ -d "$skill_dir" ] || continue
  skill_name=$(basename "$skill_dir")
  skill_md="$skill_dir/SKILL.md"
  [ -f "$skill_md" ] || continue

  if [ "$DRY_RUN" = "yes" ]; then
    echo "[dry-run] rewrite $skill_md (name → $skill_name, all path/skill refs)"
    continue
  fi

  # Rewrite name: frontmatter to match new folder
  "${SED_INPLACE[@]}" -E "s|^name: harness-(run\|coding\|review\|testing\|requirements\|fix)$|name: $skill_name|" "$skill_md"
  # Apply cross-ref rewrites
  for expr in "${SKILL_RENAMES[@]}"; do
    "${SED_INPLACE[@]}" -E "$expr" "$skill_md"
  done
  "${SED_INPLACE[@]}" -E -e 's|^harness/|espalier/|' -e 's|([^a-zA-Z0-9_-])harness/|\1espalier/|g' "$skill_md"
done

# Also rewrite per-layer specs inside espalier-coding/specs/
for spec in espalier/skills/espalier-coding/specs/*.md; do
  [ -f "$spec" ] || continue
  _rewrite_file "$spec"
done

# --- Step 4: rewrite agent + pipeline + hooks + wiki ------------------------

log "Step 4: rewrite agent.md, pipeline.md, agents/*, hooks/*, wiki/*"
_rewrite_file "espalier/agent.md"
_rewrite_file "espalier/pipeline.md"
_rewrite_file "espalier/agents/harness-coder.md"
_rewrite_file "espalier/agents/harness-reviewer.md"
for w in espalier/wiki/*.md; do
  [ -f "$w" ] || continue
  _rewrite_file "$w"
done
for h in espalier/hooks/*.sh; do
  [ -f "$h" ] || continue
  _rewrite_file "$h"
done
# Rules — paths only, no skill name refs expected, but cheap to apply both passes
for r in espalier/rules/*.md; do
  [ -f "$r" ] || continue
  _rewrite_file "$r"
done

# --- Step 5: rebuild .claude/ symlinks --------------------------------------

log "Step 5: rebuild .claude/{rules,skills,agents} symlinks"
abspath() {
  if [ -d "$1" ]; then
    ( cd "$1" && pwd )
  else
    ( cd "$(dirname "$1")" 2>/dev/null && echo "$(pwd)/$(basename "$1")" )
  fi
}

if [ "$DRY_RUN" = "yes" ]; then
  echo "[dry-run] remove old harness-* symlinks under .claude/{rules,skills,agents}"
  echo "[dry-run] create espalier-* symlinks pointing at espalier/..."
else
  # Remove only old harness-* symlinks (preserve any user files)
  for link in .claude/rules/harness-structure.md \
              .claude/rules/harness-standards.md \
              .claude/rules/harness-process.md; do
    [ -L "$link" ] && rm -f "$link"
  done
  for skill in harness-coding harness-review harness-testing harness-requirements harness-run harness-fix; do
    [ -L ".claude/skills/$skill" ] && rm -f ".claude/skills/$skill"
  done
  # Agent symlinks keep their names — but their targets moved; refresh anyway
  [ -L ".claude/agents/harness-coder.md" ] && rm -f ".claude/agents/harness-coder.md"
  [ -L ".claude/agents/harness-reviewer.md" ] && rm -f ".claude/agents/harness-reviewer.md"

  mkdir -p .claude/rules .claude/skills .claude/agents

  ln -sf "$(abspath espalier/rules/engineering-structure.md)" .claude/rules/espalier-structure.md
  ln -sf "$(abspath espalier/rules/coding-standards.md)"      .claude/rules/espalier-standards.md
  ln -sf "$(abspath espalier/rules/development-process.md)"   .claude/rules/espalier-process.md
  for s in espalier-coding espalier-review espalier-testing espalier-requirements espalier espalier-fix; do
    [ -d "espalier/skills/$s" ] && ln -sf "$(abspath "espalier/skills/$s")" ".claude/skills/$s"
  done
  ln -sf "$(abspath espalier/agents/harness-coder.md)"    .claude/agents/harness-coder.md
  ln -sf "$(abspath espalier/agents/harness-reviewer.md)" .claude/agents/harness-reviewer.md
fi

# --- Step 6: patch .claude/settings.json hook paths -------------------------

log "Step 6: patch .claude/settings.json"
if [ -f ".claude/settings.json" ]; then
  if [ "$DRY_RUN" = "yes" ]; then
    echo "[dry-run] sed harness/hooks/ → espalier/hooks/ in .claude/settings.json"
  else
    cp .claude/settings.json ".claude/settings.json.v0.3.bak"
    "${SED_INPLACE[@]}" -E 's|harness/hooks/|espalier/hooks/|g' .claude/settings.json
    # Validate
    python3 -c "import json; json.load(open('.claude/settings.json'))" 2>/dev/null || {
      echo "ERROR: .claude/settings.json failed JSON validation after patch — restoring backup" >&2
      cp ".claude/settings.json.v0.3.bak" .claude/settings.json
      exit 1
    }
  fi
fi

# --- Step 7: patch CLAUDE.md + .gitignore + post-merge hook -----------------

log "Step 7: patch CLAUDE.md, .gitignore, post-merge hook"
if [ -f "CLAUDE.md" ]; then
  if [ "$DRY_RUN" = "yes" ]; then
    echo "[dry-run] rewrite CLAUDE.md (Harness Engineering → Espalier; path refs)"
  else
    "${SED_INPLACE[@]}" -E 's|## Harness Engineering|## Espalier|g' CLAUDE.md
    "${SED_INPLACE[@]}" -E 's|harness/agent\.md|espalier/agent.md|g' CLAUDE.md
    "${SED_INPLACE[@]}" -E 's|\.claude/rules/harness-\*\.md|.claude/rules/espalier-*.md|g' CLAUDE.md
    "${SED_INPLACE[@]}" -E 's|/harness-run|/espalier|g' CLAUDE.md
    "${SED_INPLACE[@]}" -E 's|/harness-fix|/espalier-fix|g' CLAUDE.md
  fi
fi

if [ -f ".gitignore" ]; then
  if [ "$DRY_RUN" = "yes" ]; then
    echo "[dry-run] .gitignore: harness/.commit-index.tsv → espalier/.commit-index.tsv"
  else
    "${SED_INPLACE[@]}" -E 's|^harness/\.commit-index\.tsv$|espalier/.commit-index.tsv|' .gitignore
  fi
fi

# Honor core.hooksPath — the live post-merge hook may not be under .git/hooks.
HOOKS_DIR=$(git config core.hooksPath 2>/dev/null || echo .git/hooks)
for HOOK in "$HOOKS_DIR/post-merge" .husky/post-merge; do
  [ -f "$HOOK" ] || continue
  if [ "$DRY_RUN" = "yes" ]; then
    echo "[dry-run] rewrite $HOOK (harness/ paths → espalier/)"
  else
    "${SED_INPLACE[@]}" -E -e 's|^harness/|espalier/|' -e 's|([^a-zA-Z0-9_-])harness/|\1espalier/|g' "$HOOK"
  fi
done

# --- Step 8: optional history rewrite ---------------------------------------

if [ "$REWRITE_HISTORY" = "yes" ]; then
  log "Step 8: rewrite history (pipeline-state.md bodies)"
  for state in espalier/changes/*/*/pipeline-state.md; do
    [ -f "$state" ] || continue
    _rewrite_file "$state"
  done
fi

# --- Step 9: regen reverse-lookup cache --------------------------------------

log "Step 9: regenerate espalier/.commit-index.tsv"
if [ "$DRY_RUN" = "yes" ]; then
  echo "[dry-run] rm -f espalier/.commit-index.tsv && bash espalier/hooks/rebuild-commit-index.sh"
else
  rm -f espalier/.commit-index.tsv
  if [ -x "espalier/hooks/rebuild-commit-index.sh" ]; then
    bash espalier/hooks/rebuild-commit-index.sh >/dev/null 2>&1 || true
  fi
fi

# --- Step 10: verification ---------------------------------------------------

log "Step 10: verification"
if [ "$DRY_RUN" = "yes" ]; then
  echo "(dry run — skipping verification)"
else
  pass=0; fail=0
  check() {
    if eval "$2" >/dev/null 2>&1; then pass=$((pass+1)); echo "  ✓ $1"
    else fail=$((fail+1)); echo "  ✗ $1"; fi
  }
  check "espalier/ exists, harness/ gone"        "[ -d espalier ] && [ ! -d harness ]"
  check "espalier/.merge-hook-decision present"  "test -f espalier/.merge-hook-decision"
  check "espalier/skills/espalier/SKILL.md"      "test -f espalier/skills/espalier/SKILL.md"
  check "espalier/skills/espalier-fix/SKILL.md"  "test -f espalier/skills/espalier-fix/SKILL.md"
  check "name: espalier in main SKILL"           "grep -q '^name: espalier$' espalier/skills/espalier/SKILL.md"
  check "name: espalier-fix"                     "grep -q '^name: espalier-fix$' espalier/skills/espalier-fix/SKILL.md"
  check ".claude/skills/espalier link"           "test -L .claude/skills/espalier"
  check ".claude/skills/espalier-fix link"       "test -L .claude/skills/espalier-fix"
  check ".claude/rules/espalier-structure.md"    "test -L .claude/rules/espalier-structure.md"
  check ".claude/agents/harness-coder.md"        "test -L .claude/agents/harness-coder.md"
  if [ -f .claude/settings.json ]; then
    check "settings.json hooks point to espalier/" "grep -q 'espalier/hooks' .claude/settings.json"
    check "no leftover harness/ in settings.json"  "! grep -q 'harness/hooks' .claude/settings.json"
  fi
  if [ -f CLAUDE.md ]; then
    check "CLAUDE.md mentions Espalier"          "grep -q '## Espalier' CLAUDE.md"
  fi
  if [ -f .gitignore ]; then
    check ".gitignore points to espalier/.cache" "grep -qxF 'espalier/.commit-index.tsv' .gitignore"
  fi
  echo ""
  echo "  Verification: $pass passed, $fail failed"
fi

echo ""
echo "Migration complete. Next steps:"
echo "  1. Review the diff: git diff && git status"
echo "  2. Commit:"
echo "       git add -A"
echo "       git commit -m 'chore: migrate harness/ → espalier/ (v0.3 → v0.4)'"
echo "  3. If you skipped --rewrite-history, espalier/changes/*/pipeline-state.md"
echo "     bodies still reference the old harness/ paths in their text. Re-run with"
echo "     --rewrite-history to update those too (history rows themselves stay)."
