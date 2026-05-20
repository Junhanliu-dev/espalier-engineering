# Migrating from v0.4.x to v0.5.0 (Doc-Drift Detection)

If your project has an `espalier/` directory bootstrapped with Espalier v0.4.x, this guide upgrades it to v0.5.0 — doc-drift detection. The upgrade is non-breaking and mostly mechanical (one script); this doc tells you what changes and what to verify.

## TL;DR

```text
# 1. Update the plugin
/plugin update espalier-engineering

# 2. From inside Claude Code, in your target project:
/espalier-migrate
```

`/espalier-migrate` auto-detects your install version. A v0.4.x install needs only the v0.4→v0.5 step. (A v0.1.x–v0.3.x install gets the full chain — v0.1→v0.2→v0.4→v0.5 — applied in order.) It shows a dry-run preview, asks before applying, and runs verification.

## What v0.5.0 adds

v0.5.0 keeps the generated `espalier/` artifacts in sync with the codebase as it evolves. Nothing existing changes behavior — it is all additive.

| New | What it is |
|---|---|
| `espalier/hooks/drift-detect.sh` | Post-merge detector — flags drifted docs into a gitignored sidecar on every merge/pull. |
| `espalier/hooks/drift-helpers.sh` | Shared pure-bash library sourced by the drift components. |
| `espalier/hooks/parse-drift-blocks.py` | Parses reviewer Convention Drift blocks at Stage 4. |
| `/espalier-prune` skill | Gated, per-file refresh of a stale artifact. The only component that edits a doc. |
| `/espalier-doctor` skill | Periodic re-scout for drift the file-diff detector misses. |
| Post-merge **dispatcher** | Replaces the inlined post-merge hook — runs `drift-detect.sh` every merge, `post-merge-backlink.sh` when the decision is `installed`. |
| `espalier/.doctor-cadence` | Tracked — your chosen doctor cadence (`every-change` / `weekly` / `monthly` / `manual`). |
| Validation checks 25–28 | Stale-artifact tiers (Policy 3) + structural checks for the new state files. |
| Stage 0 pre-flight, Stage 8.5 | Drift surfaced at pipeline start, and again between CI verify and deploy. |

## What the migration does

`scripts/migrate-v0.4-to-v0.5.sh` (invoked by `/espalier-migrate`) runs:

1. **`bootstrap-espalier.sh --force`** — copies the three drift hooks, installs the `espalier-prune` + `espalier-doctor` skills (and their `.claude/skills/` symlinks), swaps the post-merge hook for the dispatcher (stripping any legacy inlined backlink block), gitignores the five drift sidecars, writes `espalier/.doctor-cadence`, and refreshes the pure-copy skills (`pipeline.md`, `espalier`, `espalier-fix`).
2. **Anchor-patches the three LLM-substituted files** that bootstrap cannot regenerate without losing your project's substitutions:
   - `espalier/agents/harness-coder.md` — a stale-doc check.
   - `espalier/agents/harness-reviewer.md` — Convention Drift Reporting + Convention Observations + a pre-flight note.
   - `espalier/hooks/pre-push-gate.sh` — a non-blocking doctor-cadence reminder.
3. **Verification** — 13 checks; reports `X passed, Y failed`.

Idempotent: re-running detects an already-v0.5 install and no-ops.

## What the migration does NOT do

- **Does not touch `espalier/rules/`, `espalier/wiki/`, or `espalier/changes/`.** No drift change affects them.
- **Does not re-discover your codebase.** It installs the machinery; it does not scan for drift that already accrued. Run `/espalier-doctor` after upgrading to catch pre-existing drift.
- **Does not change pipeline semantics.** 10 stages, gates, escalation, rollback — unchanged. Stage 8.5 is a notify-only label, not a numeric stage; `Current Stage:` never holds `8.5`.

## Decisions you'll make

### Doctor cadence

`/espalier-doctor` is a periodic drift scan. `/espalier-migrate` asks how often it should run; the bash script defaults to `weekly`. The cadence is activity-gated — an idle repo never triggers a scan. It is stored in `espalier/.doctor-cadence` (tracked) and editable at any time:

| Cadence | Fires |
|---|---|
| `every-change` | every pipeline Stage 0 |
| `weekly` | first activity after 7 days (recommended) |
| `monthly` | first activity after 30 days |
| `manual` | never automatically — only an explicit `/espalier-doctor` |

### When to commit

A single commit (`chore: upgrade Espalier to v0.5.0`) keeps the diff atomic.

## Pre-migration checklist

- [ ] Commit (or stash) uncommitted work in the target repo.
- [ ] Update the plugin first (`/plugin update espalier-engineering`) so the new scripts are on disk.
- [ ] No in-flight `/espalier` or `/espalier-fix` sessions mid-stage — finish them first.
- [ ] `/espalier-migrate` runs a `--dry-run` preview automatically; review it before confirming.

## Post-migration verification

The script's 13 checks cover the essentials. Manual smoke after:

```bash
test -f espalier/hooks/drift-detect.sh && echo "drift hooks installed"
test -L .claude/skills/espalier-prune && test -L .claude/skills/espalier-doctor && echo "new skills wired"
grep -q ESPALIER_POSTMERGE_DISPATCH .git/hooks/post-merge 2>/dev/null && echo "dispatcher installed"
cat espalier/.doctor-cadence
```

Then catch any drift that accrued before the upgrade:

```text
/espalier-doctor
```

## Rollback

The script is idempotent but not self-reverting. To roll back:

```bash
# If you haven't committed yet
git restore .
git restore --staged .
git clean -fd               # removes the new untracked drift hooks/skills

# If you committed
git revert <upgrade-commit-sha>
```

## Common issues

### "couldn't find the Espalier plugin"

The plugin on disk is still v0.4.x (no `migrate-v0.4-to-v0.5.sh`). Run `/plugin update espalier-engineering`, or pass `--plugin-dir=<path to your espalier-engineering checkout>`.

### "WARN anchor not found — patch by hand"

One of the three substituted files was customized enough that the migration could not locate its insertion anchor. The mechanical upgrade still applied; the message names the file and the expected anchor line. Open the plugin's `skills/espalier-init/templates/agents/` (or `hook-templates/pre-push-gate.sh`) and copy the missing section across by hand.

### Convention drift not appearing in reviews

The reviewer only emits Convention Drift blocks if `harness-reviewer.md` was patched — check `grep -q "Convention Drift Reporting" espalier/agents/harness-reviewer.md`. If absent, see the anchor-not-found note above.

### `/espalier-prune` / `/espalier-doctor` not discoverable

Restart Claude Code. Skill discovery caches symlink state at session start; re-launching picks up the new symlinks.

## Verifying the upgrade landed

Run a real flow:

```text
/espalier feat: <some small feature>
```

Expected: a Stage 0 pre-flight runs first (silent when there is no drift), then the pipeline proceeds normally. After a few merges, `espalier/.drift-state.tsv` starts recording flagged docs; `/espalier-prune` refreshes them, `/espalier-doctor` scans for what no diff caught.
