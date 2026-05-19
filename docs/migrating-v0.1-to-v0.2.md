# Migrating from v0.1.0 to v0.2.0

> **Note for v0.4.0+ users:** This is the legacy migration guide for projects on v0.1.0. If you're on v0.2.x or v0.3.x and want to upgrade to v0.4.0 (the Espalier rebrand), see [`migrating-v0.3-to-v0.4.md`](./migrating-v0.3-to-v0.4.md) instead. If you're on v0.1.0, you need BOTH migrations — run `/espalier-migrate` and it will detect this and apply v0.1→v0.2 first, then v0.3→v0.4 automatically.

If you ran `/harness-engineering` on a project under v0.1.0 and have a `harness/` directory already, this guide walks you through upgrading to v0.2.0 (typed change layout + `/harness-fix` bug-fix lane + squash-merge resilience + reverse-lookup cache).

**You do not need to regenerate the harness.** A migration script handles the mechanical changes; this doc covers the decisions you'll make.

## TL;DR

Pick the path that matches your install:

### Marketplace install (most users) — easiest: use `/espalier-migrate` skill

```text
# 1. Update plugin (v0.4.0+ ships as 'espalier'; old 'harness-engineering' plugin slug is frozen)
/plugin install espalier-engineering@espalier-engineering

# 2. From inside Claude Code, in your target project:
/espalier-migrate
```

The `/espalier-migrate` skill (v0.4.0+) auto-detects whether your install needs
v0.1→v0.2 (typed changes) or v0.3→v0.4 (rename) or both, locates the right
script(s) in the plugin install, runs `--dry-run` first, shows the preview,
then asks before applying. Older `/harness-migrate` invocation (v0.2.1–v0.3.x)
still works on installs that have the old plugin and only need v0.1→v0.2.

### Marketplace install — direct script invocation

```bash
# 1. Update plugin
/plugin install espalier-engineering@espalier-engineering

# 2. From target project root:
cd ~/path/to/your-project

# 3. Run from plugin install (typical path — both new and legacy plugin dirs supported)
bash ~/.claude/plugins/espalier-engineering/scripts/migrate-v0.1-to-v0.2.sh --dry-run
bash ~/.claude/plugins/espalier-engineering/scripts/migrate-v0.1-to-v0.2.sh
```

### Manual clone install

```bash
# 1. Update local clone (repo renamed in v0.4.0; github maintains redirects)
cd ~/repos/espalier-engineering && git pull
# or for legacy clones: cd ~/repos/harness-engineering && git pull

# 2. From target project root:
cd ~/path/to/your-project
bash ~/repos/espalier-engineering/scripts/migrate-v0.1-to-v0.2.sh --dry-run
bash ~/repos/espalier-engineering/scripts/migrate-v0.1-to-v0.2.sh
```

### No-install / one-shot (e.g., CI)

```bash
cd ~/path/to/your-project
curl -L -o /tmp/migrate.sh https://raw.githubusercontent.com/Junhanliu-dev/espalier-engineering/v0.4.0/scripts/migrate-v0.1-to-v0.2.sh
chmod +x /tmp/migrate.sh
/tmp/migrate.sh --dry-run --plugin-dir=$HOME/.claude/plugins/espalier-engineering/skills/espalier-init
/tmp/migrate.sh             --plugin-dir=$HOME/.claude/plugins/espalier-engineering/skills/espalier-init
```

Then commit the result. Done.

### Where is the plugin installed?

| Install method | Typical path |
|----------------|--------------|
| Marketplace v0.4.0+ (`/plugin install espalier-engineering@espalier-engineering`) | `~/.claude/plugins/espalier-engineering/` |
| Marketplace legacy (`/plugin install harness-engineering`) | `~/.claude/plugins/harness-engineering/` |
| Manual clone + symlink (current) | `~/repos/espalier-engineering/` |
| Manual clone + symlink (legacy) | `~/repos/harness-engineering/` (or wherever you cloned) |
| Project-scoped | `<project>/.claude/skills/espalier-init/` (symlink target) |

If the script can't find templates automatically, pass `--plugin-dir=<path>` pointing at the `skills/espalier-init/` subdir of your install (the one containing `hook-templates/`). The legacy `skills/harness-engineering/` subdir is also recognized for backward compat.

## What the migration changes

| Component | v0.1.0 | v0.2.0 | Migration action |
|-----------|--------|--------|------------------|
| Change tracking | `harness/changes/{slug}/` (flat) | `harness/changes/{type}/{slug}/` | `git mv` each dir under `feat/` (or `fix/` / `refactor/` if name pattern matches) |
| pipeline-state.md | no `## Commits` table | gains `## Commits` table on Stage 7 push | New entries gain it automatically; historic ones empty (or backfilled via `--backfill=best-effort`) |
| Skills | 5 (`harness-{coding,review,testing,requirements,run}`) | 6 (adds `harness-fix`) | Copy template + add symlink |
| Hook templates | `pre-push-gate.sh`, `check-layer-boundaries.sh`, `post-edit-wrapper.sh` | + `post-merge-backlink.sh`, `lookup-helpers.sh`, `rebuild-commit-index.sh` | Copy 3 new templates to `harness/hooks/` |
| Merge strategy | implicit | explicit decision cached in `harness/.merge-hook-decision` | Script prompts; choice persists |
| Optional `.git/hooks/post-merge` | n/a | Installed if decision = `installed` | Script installs (husky-aware) |
| Reverse-lookup cache | n/a | `harness/.commit-index.tsv` (gitignored, lazy-built) | Script adds `.gitignore` line |
| Agent templates | v0.1.0 | New verdict (`ESCALATION_REQUIRED`) + new signal (`TEST_SCOPE_INFLATION`) | Script copies new versions; backs up old as `*.v0.1.bak` |

## Decisions you'll make

### 1. Merge strategy (prompted by the script)

```
1) not-needed    — rebase or merge-commit; SHAs preserved on main
2) installed     — install post-merge hook for squash-merge mapping (recommended for GitHub squash-merge default)
3) fuzzy-allowed — no hook; fuzzy file-overlap match at fix-time
4) skip-only     — no hook, no fuzzy; mark unknown_squash
5) never-ask     — same as skip-only, silent
6) ask-later     — defer; prompt at first `/harness-fix`
```

If unsure, pick **`ask-later`**. `/harness-fix` will prompt on the first invocation and cache the choice.

Full rationale: [`docs/plan.md` §6.5](./plan.md).

### 2. Historic SHA backfill (script flag)

`--backfill=none` (default): historic changes get no `## Commits` row. Fixes against old features will mark `caused_by: [unknown]`. Honest, zero work.

`--backfill=best-effort`: script greps `git log --all --grep "<slug-as-spaces>"` per change, writes the first match. False positives possible (matches a commit that *mentions* the slug but isn't the implementing commit).

`--backfill=interactive` (future): not in v0.2.0 — would prompt per change.

Recommended: **`none`** unless you actively track bugs against your older features. You can always backfill later by hand.

### 3. Agent template diffs

The script backs up your v0.1.0 `harness/agents/harness-{coder,reviewer}.md` as `*.v0.1.bak` and installs v0.2.0 versions. If you hand-customized those agents, diff and re-apply your edits:

```bash
vimdiff harness/agents/harness-reviewer.md{,.v0.1.bak}
vimdiff harness/agents/harness-coder.md{,.v0.1.bak}
```

The v0.2.0 changes are additive (new verdict / new signal block), so most customizations should merge cleanly.

## Pre-migration checklist

- [ ] Commit (or stash) any uncommitted work in the target repo.
- [ ] Make sure tests pass on `main` before migrating (the script touches hook scripts that affect pre-push gates).
- [ ] Update the plugin first (so the script + templates are v0.2.0).
- [ ] Run the script with `--dry-run` to preview.

## Post-migration verification

```bash
# Quick smoke
find harness/changes -mindepth 3 -maxdepth 3 -name pipeline-state.md | wc -l    # should be > 0 if you had any changes
test -e .claude/skills/harness-fix/SKILL.md && echo "fix skill linked"
test -f harness/.merge-hook-decision && cat harness/.merge-hook-decision
grep -qxF "harness/.commit-index.tsv" .gitignore && echo "cache ignored"

# Full validation (matches the checklist in skills/.../references/validation.md)
# Rows 12-24 cover v0.2 additions
```

If the script's built-in verification fails, fix the failing item by hand and re-run the script (it's idempotent — safe to run multiple times).

## Rollback

If something goes wrong:

```bash
git restore .         # restore working tree
git restore --staged . # un-stage anything added by the script
# Agent template backups (.v0.1.bak) remain on disk — delete or restore as needed
```

If you'd already committed and need to undo:

```bash
git revert <migration-commit-sha>
```

## Common issues

### "Plugin dir not found"

The script auto-searches common install locations (both new `espalier-engineering` and legacy `harness-engineering` paths). If yours is elsewhere:

```bash
ESPALIER_PLUGIN_DIR=/path/to/espalier-engineering/skills/espalier-init \
  bash scripts/migrate-v0.1-to-v0.2.sh
# Legacy env var HARNESS_PLUGIN_DIR also still honored.
```

Or pass `--plugin-dir=<path>`.

### "Target exists" warnings during typed-layout migration

If you already have a `harness/changes/feat/<name>/` dir AND a flat `harness/changes/<name>/` with the same basename, the script skips the move and warns. Resolve by hand: pick which one to keep, delete the other, re-run.

### Customized agent templates lost

The script saves `.v0.1.bak` backups. If you skipped reviewing them and want to recover your customizations, the backup files are still on disk until you delete them. Re-apply your edits to the v0.2.0 versions.

### Existing post-merge hook from another tool

If `.git/hooks/post-merge` exists from another tool (e.g., your CI bootstrap), the script appends the harness section instead of overwriting. Both run on each merge. If you don't want that, delete the harness section from the hook after migration.

## Verifying the upgrade landed

After migration, try a real bug fix. **If you ran only v0.1→v0.2** (not the v0.3→v0.4 rename), use the legacy command:

```bash
/harness-fix <bug at file:line>
```

If you ALSO ran `/espalier-migrate` (which applies v0.3→v0.4 after v0.1→v0.2), use:

```bash
/espalier-fix <bug at file:line>
```

Expected:
- Slug auto-derived to `harness/changes/fix/<slug>/` (legacy) or `espalier/changes/fix/<slug>/` (v0.4)
- Stage 0 auto-link runs (may print warning if you didn't backfill)
- Sub-agents `harness-coder` / `harness-reviewer` spawned (agent names kept across rename)
- Stage 7 pushes + records SHA in `## Commits` table
- (If `caused_by` populated) row appended to causing feat's `## Follow-up Fixes` table

If anything misbehaves, check `<dir>/changes/fix/<slug>/pipeline-state.md` for the Stage History trail.
