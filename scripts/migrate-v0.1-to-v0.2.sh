#!/bin/bash
# Migrate a harness-engineering v0.1.0 target repo to v0.2.0 layout + features.
#
# Run from the TARGET project root (the repo where /harness-engineering was
# previously invoked — must contain harness/ and .claude/ dirs).
#
# Idempotent. Safe to re-run. Use --dry-run to preview changes.
#
# Usage:
#   bash migrate-v0.1-to-v0.2.sh [--dry-run] [--backfill=none|best-effort]
#                                [--plugin-dir=<path>] [--yes]
#
# Flags:
#   --dry-run                Print actions without executing.
#   --backfill=none          Skip historic SHA backfill (default).
#   --backfill=best-effort   Try to find historic SHAs via `git log --grep <slug>`.
#   --plugin-dir=<path>      Path to the harness-engineering plugin (where templates live).
#                            Defaults to: $HARNESS_PLUGIN_DIR, then common install locations.
#   --yes                    Skip the merge-strategy prompt; default decision = ask-later.

set -u

DRY_RUN=no
BACKFILL=none
PLUGIN_DIR="${HARNESS_PLUGIN_DIR:-}"
SKIP_PROMPT=no

for arg in "$@"; do
  case "$arg" in
    --dry-run)              DRY_RUN=yes ;;
    --backfill=none)        BACKFILL=none ;;
    --backfill=best-effort) BACKFILL=best-effort ;;
    --plugin-dir=*)         PLUGIN_DIR="${arg#--plugin-dir=}" ;;
    --yes)                  SKIP_PROMPT=yes ;;
    -h|--help)
      sed -n '2,25p' "$0"
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

# --- Preflight ---------------------------------------------------------------

if [ ! -d "harness" ] || [ ! -d ".claude" ]; then
  echo "ERROR: must run from target repo root (with harness/ and .claude/)." >&2
  exit 1
fi

if [ -z "$PLUGIN_DIR" ]; then
  # Try common locations.
  # New (v0.4+ rename): plugin name `espalier`, repo `espalier-engineering`, skill dir `espalier-init`.
  # Legacy: plugin name `harness-engineering`, repo `harness-engineering`, skill dir `harness-engineering`.
  for candidate in \
    "$HOME/.claude/plugins/espalier-engineering/skills/espalier-init" \
    "$HOME/.claude/plugins/espalier/skills/espalier-init" \
    "$HOME/.claude/plugins/harness-engineering/skills/espalier-init" \
    "$HOME/.claude/plugins/harness-engineering/skills/harness-engineering" \
    "$HOME/repos/espalier-engineering/skills/espalier-init" \
    "$HOME/repos/espalier-engineering/skills/harness-engineering" \
    "$HOME/repos/harness-engineering/skills/espalier-init" \
    "$HOME/repos/harness-engineering/skills/harness-engineering"; do
    if [ -d "$candidate/hook-templates" ]; then
      PLUGIN_DIR="$candidate"
      break
    fi
  done
fi

if [ -z "$PLUGIN_DIR" ] || [ ! -d "$PLUGIN_DIR/hook-templates" ]; then
  echo "ERROR: --plugin-dir not found. Set HARNESS_PLUGIN_DIR or pass --plugin-dir=<path>" >&2
  echo "Expected to find <path>/hook-templates/post-merge-backlink.sh" >&2
  exit 1
fi

echo "Plugin source: $PLUGIN_DIR"
echo "Backfill mode: $BACKFILL"
[ "$DRY_RUN" = "yes" ] && echo "Mode: DRY RUN (no changes will be written)"
echo ""

# --- Step 1: detect v0.1.0 state -------------------------------------------

NEEDS_LAYOUT_MIGRATION=no
NEEDS_FIX_SKILL=no
NEEDS_HOOKS=no
NEEDS_DECISION=no
NEEDS_GITIGNORE=no
NEEDS_AGENT_UPDATE=no

for d in harness/changes/*/; do
  [ -d "$d" ] || continue
  base=$(basename "$d")
  case "$base" in
    _template|feat|fix|refactor|docs) ;;
    *) NEEDS_LAYOUT_MIGRATION=yes ;;
  esac
done

[ ! -e ".claude/skills/harness-fix" ]                       && NEEDS_FIX_SKILL=yes
[ ! -f "harness/hooks/post-merge-backlink.sh" ]             && NEEDS_HOOKS=yes
[ ! -f "harness/hooks/lookup-helpers.sh" ]                  && NEEDS_HOOKS=yes
[ ! -f "harness/hooks/rebuild-commit-index.sh" ]            && NEEDS_HOOKS=yes
[ ! -f "harness/.merge-hook-decision" ]                     && NEEDS_DECISION=yes
[ ! -f ".gitignore" ] || ! grep -qxF "harness/.commit-index.tsv" .gitignore && NEEDS_GITIGNORE=yes

# Agent template version check — v0.2 ones have ESCALATION_REQUIRED / TEST_SCOPE_INFLATION
if [ -f "harness/agents/harness-reviewer.md" ] && \
   ! grep -q "ESCALATION_REQUIRED" "harness/agents/harness-reviewer.md"; then
  NEEDS_AGENT_UPDATE=yes
fi

cat << EOF
Detected migration needs:
  - Typed change layout:    $NEEDS_LAYOUT_MIGRATION
  - harness-fix skill:      $NEEDS_FIX_SKILL
  - Hook templates:         $NEEDS_HOOKS
  - Merge-hook decision:    $NEEDS_DECISION
  - .gitignore cache entry: $NEEDS_GITIGNORE
  - Agent templates:        $NEEDS_AGENT_UPDATE

EOF

# --- Step 2: typed layout migration ----------------------------------------

if [ "$NEEDS_LAYOUT_MIGRATION" = "yes" ]; then
  echo "==> Migrating flat changes/ → typed feat/{slug}/"
  run mkdir -p harness/changes/feat harness/changes/fix harness/changes/refactor
  for d in harness/changes/*/; do
    base=$(basename "$d")
    case "$base" in
      _template|feat|fix|refactor|docs) continue ;;
    esac
    # Heuristic: if directory name starts with fix-/bug-/issue-, treat as fix
    case "$base" in
      fix-*|bug-*|issue-*) target="harness/changes/fix/$base" ;;
      refactor-*)           target="harness/changes/refactor/$base" ;;
      *)                    target="harness/changes/feat/$base" ;;
    esac
    if [ -e "$target" ]; then
      echo "  SKIP $d → $target (target exists)"
    else
      run git mv "$d" "$target" 2>/dev/null || run mv "$d" "$target"
    fi
  done
fi

# --- Step 3: copy new hook templates ---------------------------------------

if [ "$NEEDS_HOOKS" = "yes" ]; then
  echo "==> Copying v0.2 hook templates to harness/hooks/"
  for t in post-merge-backlink.sh lookup-helpers.sh rebuild-commit-index.sh; do
    src="$PLUGIN_DIR/hook-templates/$t"
    dst="harness/hooks/$t"
    if [ ! -f "$src" ]; then
      echo "  WARN: missing source $src — skipping $t" >&2
      continue
    fi
    run cp "$src" "$dst"
  done
  run chmod +x harness/hooks/post-merge-backlink.sh harness/hooks/rebuild-commit-index.sh
fi

# --- Step 4: harness-fix skill ---------------------------------------------

if [ "$NEEDS_FIX_SKILL" = "yes" ]; then
  echo "==> Installing harness-fix skill"
  run mkdir -p harness/skills/harness-fix
  run cp "$PLUGIN_DIR/templates/skills/harness-fix.md" harness/skills/harness-fix/SKILL.md
  run ln -sfn "\$(pwd)/harness/skills/harness-fix" .claude/skills/harness-fix
fi

# --- Step 5: agent template updates (back up first) -------------------------

if [ "$NEEDS_AGENT_UPDATE" = "yes" ]; then
  echo "==> Updating agent templates (backups saved as *.v0.1.bak)"
  for a in harness-reviewer harness-coder; do
    if [ -f "harness/agents/$a.md" ]; then
      run cp "harness/agents/$a.md" "harness/agents/$a.md.v0.1.bak"
    fi
    run cp "$PLUGIN_DIR/templates/agents/$a.md" "harness/agents/$a.md"
  done
  echo "  Review the diff: vimdiff harness/agents/harness-reviewer.md{,.v0.1.bak}"
fi

# --- Step 6: merge-hook decision prompt -------------------------------------

if [ "$NEEDS_DECISION" = "yes" ]; then
  echo "==> Setting merge-hook decision"
  if [ "$SKIP_PROMPT" = "yes" ]; then
    DECISION=ask-later
    echo "  (--yes set; defaulting to ask-later — will be prompted at first /harness-fix)"
  else
    cat << 'PROMPT'

Pick how /harness-fix should handle squash-merge SHA drift.
(See docs/plan.md §6.5 for full rationale.)

  1) not-needed    — Repo uses rebase or merge-commit; SHAs preserved on main
  2) installed     — Install post-merge git hook to record squash mappings (recommended for squash repos)
  3) fuzzy-allowed — No hook; allow fuzzy file-overlap match at fix-time
  4) skip-only     — No hook, no fuzzy; mark unknown_squash and continue
  5) never-ask     — Same as skip-only, silent forever
  6) ask-later     — Defer; prompt at first /harness-fix

PROMPT
    read -p "Choice [1-6]: " choice
    case "$choice" in
      1) DECISION=not-needed ;;
      2) DECISION=installed ;;
      3) DECISION=fuzzy-allowed ;;
      4) DECISION=skip-only ;;
      5) DECISION=never-ask ;;
      *) DECISION=ask-later ;;
    esac
  fi
  if [ "$DRY_RUN" = "yes" ]; then
    echo "[dry-run] echo $DECISION > harness/.merge-hook-decision"
  else
    echo "$DECISION" > harness/.merge-hook-decision
    echo "  Wrote: $DECISION"
  fi

  if [ "$DECISION" = "installed" ]; then
    echo "==> Installing post-merge hook"
    # Honor core.hooksPath — git ignores .git/hooks entirely when it is set.
    if [ -d ".husky" ]; then
      HOOK_DST=".husky/post-merge"
    else
      HOOK_DST="$(git config core.hooksPath 2>/dev/null || echo .git/hooks)/post-merge"
    fi
    SRC="harness/hooks/post-merge-backlink.sh"
    run mkdir -p "$(dirname "$HOOK_DST")"
    if [ -f "$HOOK_DST" ] && ! grep -q "HARNESS_BACKLINK_HOOK" "$HOOK_DST"; then
      run "cat \"$SRC\" >> \"$HOOK_DST\""
    elif [ ! -f "$HOOK_DST" ]; then
      run cp "$SRC" "$HOOK_DST"
    fi
    run chmod +x "$HOOK_DST"
  fi
fi

# --- Step 7: .gitignore -----------------------------------------------------

if [ "$NEEDS_GITIGNORE" = "yes" ]; then
  echo "==> Adding cache to .gitignore"
  if [ "$DRY_RUN" = "yes" ]; then
    echo "[dry-run] append 'harness/.commit-index.tsv' to .gitignore (with newline guard)"
  else
    [ -f .gitignore ] || touch .gitignore
    if ! grep -qxF "harness/.commit-index.tsv" .gitignore; then
      # Ensure file ends with a newline before appending; otherwise the new
      # line glues to the previous (e.g., existing "harness" + appended
      # "harness/.commit-index.tsv" -> "harnessharness/.commit-index.tsv").
      if [ -s .gitignore ] && [ -n "$(tail -c1 .gitignore)" ]; then
        printf '\n' >> .gitignore
      fi
      echo "harness/.commit-index.tsv" >> .gitignore
    fi
  fi
fi

# --- Step 8: optional backfill of historic SHAs ----------------------------

if [ "$BACKFILL" = "best-effort" ]; then
  echo "==> Best-effort backfill of historic SHAs into pipeline-state.md Commits tables"
  find harness/changes -mindepth 3 -maxdepth 3 -name pipeline-state.md | while read -r f; do
    if grep -q "^## Commits" "$f"; then
      continue   # already has commits table
    fi
    slug=$(echo "$f" | sed 's|harness/changes/[^/]*/||; s|/pipeline-state.md||')
    # Try to find a commit whose message mentions the slug (kebab-case → spaces)
    needle=$(echo "$slug" | tr - ' ')
    sha=$(git log --all --grep "$needle" -1 --format=%H 2>/dev/null)
    if [ -n "$sha" ]; then
      files=$(git diff-tree --no-commit-id --name-only -r "$sha" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
      if [ "$DRY_RUN" = "yes" ]; then
        echo "[dry-run] backfill $f with SHA $sha"
      else
        cat >> "$f" << EOF

## Commits
| Stage | SHA | Files |
|-------|-----|-------|
| 7 | $sha | $files |
EOF
        echo "  backfilled $f → $sha"
      fi
    else
      echo "  no match for $slug — leaving Commits empty"
    fi
  done
fi

# --- Step 9: verification ---------------------------------------------------

echo ""
echo "==> Verification"
if [ "$DRY_RUN" = "yes" ]; then
  echo "(dry run — skipping verification)"
else
  pass=0; fail=0
  check() {
    if eval "$2"; then pass=$((pass+1)); echo "  ✓ $1"
    else fail=$((fail+1)); echo "  ✗ $1"; fi
  }
  check "harness-fix skill present"        "test -e .claude/skills/harness-fix/SKILL.md"
  check "lookup-helpers.sh installed"      "test -f harness/hooks/lookup-helpers.sh"
  check "rebuild-commit-index.sh exec"     "test -x harness/hooks/rebuild-commit-index.sh"
  check "post-merge-backlink.sh exec"      "test -x harness/hooks/post-merge-backlink.sh"
  check ".merge-hook-decision written"     "test -f harness/.merge-hook-decision"
  check "cache in .gitignore"              "grep -qxF 'harness/.commit-index.tsv' .gitignore"
  check "typed layout (no legacy flat)"    "! find harness/changes -mindepth 1 -maxdepth 1 -type d ! -name _template ! -name feat ! -name fix ! -name refactor ! -name docs | grep -q ."
  echo ""
  echo "  Verification: $pass passed, $fail failed"
fi

echo ""
echo "Migration complete. Next steps:"
echo "  1. Review the diff: git diff && git status"
echo "  2. If agent templates were updated, compare with .v0.1.bak files"
echo "  3. Commit: git add -A && git commit -m 'chore: migrate harness v0.1 → v0.2'"
echo "  4. Try /harness-fix on a real bug to exercise the new lane"
