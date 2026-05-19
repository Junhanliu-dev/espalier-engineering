# Migrating from v0.3.x to v0.4.0 (The Rebrand)

If your project was bootstrapped with `harness-engineering` v0.1.x – v0.3.x and you have a `harness/` directory, this guide walks you through upgrading to Espalier v0.4.0. The rename is mechanical (one script does the work); this doc tells you what changes and what to verify.

## TL;DR

```text
# 1. Update plugin
/plugin marketplace add Junhanliu-dev/espalier-engineering
/plugin install espalier-engineering@espalier-engineering

# 2. From inside Claude Code, in your target project:
/espalier-migrate
```

`/espalier-migrate` auto-detects whether you're on v0.1.x (needs typed-changes migration first) or v0.2.x–v0.3.x (only needs the rename), shows a dry-run preview, asks before applying, then runs verification.

If both migrations apply (v0.1.x install), they run in order: v0.1→v0.2 first, then v0.3→v0.4.

## What renames

| Before | After |
|---|---|
| Plugin: `harness-engineering` | `espalier` |
| GitHub repo: `Junhanliu-dev/harness-engineering` | `Junhanliu-dev/espalier-engineering` (redirects active) |
| Target-project dir: `harness/` | `espalier/` |
| Slash command: `/harness-engineering` | `/espalier-init` |
| Slash command: `/harness-run <req>` | `/espalier <req>` (note: bare, no `-run` suffix) |
| Slash command: `/harness-fix <bug>` | `/espalier-fix <bug>` |
| Slash command: `/harness-migrate` | `/espalier-migrate` |
| Skill folder: `espalier/skills/harness-coding/` | `espalier/skills/espalier-coding/` |
| Skill folder: `espalier/skills/harness-review/` | `espalier/skills/espalier-review/` |
| Skill folder: `espalier/skills/harness-testing/` | `espalier/skills/espalier-testing/` |
| Skill folder: `espalier/skills/harness-requirements/` | `espalier/skills/espalier-requirements/` |
| Skill folder: `espalier/skills/harness-fix/` | `espalier/skills/espalier-fix/` |
| Skill folder: `espalier/skills/harness-run/` | `espalier/skills/espalier/` |
| Symlink: `.claude/skills/harness-*` | `.claude/skills/espalier-*` (or bare `espalier`) |
| Symlink: `.claude/rules/harness-structure.md` (and `-standards`, `-process`) | `.claude/rules/espalier-structure.md` (etc.) |
| `.claude/settings.json` hook path `harness/hooks/...` | `espalier/hooks/...` |
| `CLAUDE.md` section header `## Harness Engineering` | `## Espalier` |
| `.gitignore` entry `harness/.commit-index.tsv` | `espalier/.commit-index.tsv` |
| Reverse-lookup cache: `harness/.commit-index.tsv` | `espalier/.commit-index.tsv` |
| Bootstrap script: `bootstrap-harness.sh` | `bootstrap-espalier.sh` |

## What stays the same

| Component | Reason |
|---|---|
| Sub-agent identifier `harness-coder` | Renaming breaks any in-flight pipeline that references the agent by name. |
| Sub-agent identifier `harness-reviewer` | Same. |
| `.claude/agents/harness-coder.md` filename | Matches the agent identifier above. |
| `.claude/agents/harness-reviewer.md` filename | Same. |
| Pipeline semantics (10 stages, gates, escalation paths) | Pure rename. Zero workflow change. |
| Typed `changes/{type}/{slug}/` layout | Migrated in v0.2; preserved through rename. |
| Squash-merge decision file content (`installed`, `fuzzy-allowed`, etc.) | Pure rename of path; values unchanged. |
| Causal links, `Follow-up Fixes` tables, `Commits` tables in `pipeline-state.md` history | Frozen text; history rows reference old `harness/` paths but stay readable. Pass `--rewrite-history` if you want them updated too. |
| Post-merge hook marker `HARNESS_BACKLINK_HOOK` | New installs use `ESPALIER_BACKLINK_HOOK`; existing installs' legacy marker is recognized by detection grep — no double-install. |
| Environment variables | `ESPALIER_PLUGIN_DIR` and `ESPALIER_CACHE_THRESHOLD_MS` preferred; `HARNESS_PLUGIN_DIR` and `HARNESS_CACHE_THRESHOLD_MS` still honored as fallback. |

## What the migration script does

`scripts/migrate-v0.3-to-v0.4.sh` (invoked by `/espalier-migrate`) runs these steps in order:

1. `git mv harness/ → espalier/`
2. Rename child skill directories: `espalier/skills/harness-{coding,review,testing,requirements,fix}/` → `espalier-*/`, and `harness-run/` → `espalier/`.
3. Rewrite SKILL.md `name:` frontmatter to match new folder names.
4. Rewrite path refs (`harness/` → `espalier/`) and skill name refs (`harness-coding` → `espalier-coding`, etc.) inside:
   - `espalier/agent.md`, `espalier/pipeline.md`
   - `espalier/agents/harness-coder.md`, `espalier/agents/harness-reviewer.md` (paths only — agent identifiers kept)
   - `espalier/skills/*/SKILL.md` (cross-refs between skills)
   - `espalier/hooks/*.sh`
   - `espalier/wiki/*.md`
   - `espalier/rules/*.md`
5. Rebuild `.claude/{rules,skills,agents}/*` symlinks pointing at new targets.
6. Patch `.claude/settings.json` hook command paths (backup saved as `.claude/settings.json.v0.3.bak`).
7. Patch `CLAUDE.md` (section header + path refs + slash command mentions).
8. Patch `.gitignore` cache entry.
9. Patch `.git/hooks/post-merge` and/or `.husky/post-merge` if present.
10. Regenerate `espalier/.commit-index.tsv` from current `pipeline-state.md` files.
11. Run 12 verification checks; report `X passed, Y failed`.

## What the script does NOT do (by default)

- **Does not rewrite text inside `espalier/changes/*/pipeline-state.md` body history.** Stage History rows, Commits rows, Follow-up Fixes rows reference the old `harness/` paths in their note columns. They're historical text and still readable. Pass `--rewrite-history` to opt in.
- **Does not rename `harness-coder` / `harness-reviewer` agent identifiers.** These are internal sub-agent names baked into the orchestrator. Renaming would break any in-flight pipeline mid-stage.
- **Does not rename the github repo.** That's a manual GitHub setting change. Once renamed, github maintains redirects for ~1 year — old plugin install URLs keep working.

## Decisions you'll make

### 1. History rewrite (`--rewrite-history`)

Default: history text in `espalier/changes/*/pipeline-state.md` bodies stays as-is. Old fixes' notes will say things like `Auto-linked to harness/changes/feat/...` (readable, but technically stale).

Pass `--rewrite-history` to rewrite all that text to `espalier/...` instead. Recommended only if you (a) actively read old fix histories and find the old paths confusing, or (b) you're about to grep through history files programmatically.

### 2. When to commit

Single commit (`chore: migrate to Espalier v0.4.0`) keeps the diff atomic. Reviewers can see the whole rename in one place. Recommended.

If you want to split: directory rename (Step 1) as its own commit, then everything else as a second. Helps `git log --follow` track file history more cleanly, but most modern git versions handle rename detection across paths even in a single commit via `git diff -M`.

## Pre-migration checklist

- [ ] Commit (or stash) any uncommitted work in the target repo.
- [ ] Tests pass on `main` before migrating (the script touches hook scripts that affect pre-push gates).
- [ ] Update the plugin first (`/plugin install espalier-engineering@espalier-engineering`) so the new migration script is on disk.
- [ ] Run with `--dry-run` to preview (the `/espalier-migrate` skill does this automatically).
- [ ] No in-flight `/harness-run` or `/harness-fix` sessions mid-stage — finish them first, or abort and resume after migration.

## Post-migration verification

The script's built-in checks cover the essentials. Manual smoke after:

```bash
# Quick checks
test -d espalier && [ ! -d harness ] && echo "rename ok"
cat espalier/.merge-hook-decision    # should match what you had before
grep -q '## Espalier' CLAUDE.md && echo "CLAUDE.md patched"
grep -q 'espalier/hooks' .claude/settings.json && echo "settings.json patched"

# Plugin-level: slash commands now available
# (Restart Claude Code if necessary — symlinks change discovery state)
# /espalier        — should be discoverable
# /espalier-fix    — should be discoverable
# /espalier-init   — should be discoverable
# /espalier-migrate — should be discoverable (just used it)
```

If anything misbehaves, run with `--dry-run` again to see the script's current view of state, or inspect:

- `.claude/settings.json.v0.3.bak` — automatic backup of pre-migration settings.json
- `git diff HEAD` — full set of changes the script applied

## Rollback

The script is idempotent but not self-reverting. To roll back:

```bash
# If you haven't committed yet
git restore .
git restore --staged .
git clean -fd                      # remove any untracked espalier-* artifacts

# If you committed
git revert <migration-commit-sha>
```

After rollback, `.claude/settings.json.v0.3.bak` remains on disk — delete it or use it as reference.

## Common issues

### "espalier/ already exists alongside harness/"

You've partially migrated already (or there's a stray `espalier/` from a previous test). The script refuses to clobber. Resolve by hand: pick which one is the source of truth, delete the other, re-run.

### "Plugin dir not found"

`/espalier-migrate` searches both the new (`espalier-engineering`) and legacy (`harness-engineering`) install paths. If yours is elsewhere:

```bash
ESPALIER_PLUGIN_DIR=/path/to/espalier-engineering \
  bash /path/to/scripts/migrate-v0.3-to-v0.4.sh --dry-run
```

### Slash commands still showing old names

Restart Claude Code. Skill discovery caches symlink state at session start; re-launching picks up the renamed symlinks.

### `harness-coder` / `harness-reviewer` agents stopped working after migration

The agents themselves are unchanged — only the file paths they reference inside their bodies moved. If they're broken, check:

```bash
test -L .claude/agents/harness-coder.md && readlink .claude/agents/harness-coder.md
# Should point to .../espalier/agents/harness-coder.md
```

If the symlink target is still `harness/agents/...`, the symlink step (Step 5) didn't run cleanly. Manually re-run:

```bash
rm .claude/agents/harness-coder.md .claude/agents/harness-reviewer.md
ln -sf "$(pwd)/espalier/agents/harness-coder.md"    .claude/agents/harness-coder.md
ln -sf "$(pwd)/espalier/agents/harness-reviewer.md" .claude/agents/harness-reviewer.md
```

### `/harness-run` muscle memory

Slash command renames don't have aliases. There's no `/harness-run` redirect to `/espalier`. Existing users will discover this the first time they type the old command — Claude Code reports the skill as missing. That's the rebrand cost.

## Verifying the upgrade landed

After migration, try a real flow:

```bash
/espalier feat: <some small feature>
```

Expected:
- Stage 1 produces `espalier/changes/feat/<slug>/requirements.md`
- Sub-agents `harness-coder` / `harness-reviewer` spawn
- Stage 7 push records SHA in `espalier/changes/feat/<slug>/pipeline-state.md`'s Commits table

For bug-fix lane:

```bash
/espalier-fix <bug at file:line>
```

Expected:
- Slug auto-derived to `espalier/changes/fix/<slug>/`
- Stage 0 auto-link runs (reads `espalier/.commit-index.tsv` cache)
- If `caused_by` populated, row appended to causing feat's `## Follow-up Fixes` table after Stage 7

If anything misbehaves, check `espalier/changes/{type}/<slug>/pipeline-state.md` for the Stage History trail.
