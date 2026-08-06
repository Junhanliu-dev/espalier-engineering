# Migrating v0.15.0 → v0.16.0

v0.16.0 is **Release A of the multi-dev maintenance plan** (`docs/multi-dev-maintenance-implementation-plan.md`): the discipline, guards, and compatibility floor. No new state files are created in your repo — the per-key conventions dir and the shared doctor stamp arrive in v0.17.0; this release ships the reader and the rules first.

## What the migration does

Run `/espalier-migrate` (recommended) or the script directly:

```bash
bash <plugin>/scripts/migrate-v0.15.0-to-v0.16.0.sh --dry-run   # preview
bash <plugin>/scripts/migrate-v0.15.0-to-v0.16.0.sh --yes       # apply
# optional ownership routing:
#   --codeowners-rules=@rules-owner --codeowners-wiki=@wiki-owner
```

1. **Pure-copy refresh** (backup-on-diff → `<file>.pre-v0.16.bak`): `espalier/pipeline.md`, the `espalier` / `espalier-fix` / `espalier-prune` / `espalier-doctor` SKILL files, and `espalier/hooks/drift-helpers.sh` — which gains `conv_fold`/`conv_observations`, the single executable reader of convention state.
2. **Surgical append**: the `## Maintenance Commits` section (anchor `ESPALIER MAINTENANCE COMMITS v1`) onto your project's `espalier/rules/development-process.md` — lanes, the code-owner review expectation, the union web-UI caveat.
3. **Re-wire** (`bootstrap --wire-only`): appends `espalier/.ask-gaps.tsv merge=union` to `.gitattributes` (the only union attribute — deliberately not `.conventions.tsv`), the `canonical-remote`/`canonical-branch` keys to `.espalier-config`, the optional CODEOWNERS marker block, and runs the 48/53/58-check validation. Side-effect: `.claude/settings.json` is backed up before its hook merge.

The migration runs behind the new **Step 0 barrier**: clean tree, no in-flight pipeline change, and current branch = canonical branch (explicitly acknowledgeable).

## What changes day-to-day

- **Maintenance lanes.** Doctor scans and routine prune refreshes belong in one weekly maintenance PR on the canonical branch (the temporary-worktree flow in `/espalier-prune` does the mechanics for you). A prune for your *own* critical/expired flag may ride your feature branch as its own isolated `docs:` commit. Convention promotions may ride the deciding feature branch — own isolated commit; CODEOWNERS routes the rules PR to the owner at merge (advisory until "Require review from Code Owners" branch protection is on — turn it on).
- **Race guard.** Before prompting a promotion, the orchestrator fetches the canonical branch and surfaces an existing decision instead of asking again.
- **Unattended runs** write the pre-flight summary to `espalier/.drift-report.md` and continue — they never prune or promote.
- **Conflict recipes.** Prune-vs-prune: take the newer refresh wholesale (`git checkout --theirs`), then re-run `/espalier-prune` on the merged tree. Cross-branch slug collisions: rename one change dir, rebuild the commit index, rewrite that slug's `## Follow-up Fixes` rows — all in one commit (`espalier/pipeline.md` → Multi-Developer Maintenance).

## Compatibility

- Old-plugin branches keep appending/flipping the legacy `.conventions.tsv` and stay readable forever — `conv_fold` folds legacy rows with the same weight; v0.17+ writers will never rewrite that file.
- Claude-only, codex, and copilot installs are all covered; checks 57-58 run on every platform set (totals 48/53/58).
