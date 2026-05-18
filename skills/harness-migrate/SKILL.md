---
name: harness-migrate
description: Migrate an existing harness from v0.1.0 to v0.2.0 layout (typed changes, harness-fix lane, squash resilience, reverse-lookup cache). Wraps the migration script with auto-locate + dry-run preview.
---

# Harness Migration Runner

## When to Use
- "Migrate my harness to v0.2.0"
- "Upgrade harness layout"
- "/harness-migrate"

## When NOT to Use
- Fresh project with no existing `harness/` dir → use `/harness-engineering` instead.
- Already on v0.2.0+ (decision file `harness/.merge-hook-decision` exists) → no migration needed.

## Instructions

You are running a one-shot migration of an existing v0.1.0 harness install
to v0.2.0. The mechanical work is done by
`scripts/migrate-v0.1-to-v0.2.sh` shipped inside the harness-engineering
plugin. Your job: locate it, preview the changes, get confirmation, apply.

### Step 1: Preflight checks

Run from current working directory (must be target project root):

```bash
# Confirm we're in a v0.1.0-or-newer target repo
if [ ! -d "harness" ] || [ ! -d ".claude" ]; then
  echo "ERROR: must run from target project root (harness/ + .claude/ required)" >&2
  exit 1
fi

# Check if migration is even needed
if [ -f "harness/.merge-hook-decision" ]; then
  echo "Already migrated (harness/.merge-hook-decision present). Nothing to do."
  exit 0
fi
```

If preflight fails, report to user and stop.

### Step 2: Locate the migration script

Search common plugin install paths in this order:

```bash
SCRIPT=""
for candidate in \
  "$HOME/.claude/plugins/harness-engineering/scripts/migrate-v0.1-to-v0.2.sh" \
  "$HOME/repos/harness-engineering/scripts/migrate-v0.1-to-v0.2.sh" \
  "$HOME/SBM_Projects/harness-engineering/scripts/migrate-v0.1-to-v0.2.sh"; do
  if [ -f "$candidate" ]; then
    SCRIPT="$candidate"
    break
  fi
done

if [ -z "$SCRIPT" ]; then
  echo "ERROR: couldn't find migrate-v0.1-to-v0.2.sh in standard locations." >&2
  echo "Set HARNESS_PLUGIN_DIR or download via:" >&2
  echo "  curl -L -o /tmp/migrate.sh https://raw.githubusercontent.com/Junhanliu-dev/harness-engineering/v0.2.1/scripts/migrate-v0.1-to-v0.2.sh" >&2
  echo "  chmod +x /tmp/migrate.sh && /tmp/migrate.sh" >&2
  exit 1
fi
```

### Step 3: Show dry-run preview

```bash
bash "$SCRIPT" --dry-run
```

Surface the output to the user verbatim. This shows what will be moved,
copied, prompted for, etc. without making any changes.

### Step 4: Confirm with user

Use `AskUserQuestion`:

```
The dry-run preview is above. Proceed with migration?

Options:
  1. Apply (interactive — script will prompt for merge strategy)
  2. Apply with --yes (defaults merge strategy to ask-later)
  3. Apply with best-effort SHA backfill (--backfill=best-effort)
  4. Cancel — don't apply anything
```

### Step 5: Apply migration

Based on user's choice:

| Choice | Command |
|--------|---------|
| 1 | `bash "$SCRIPT"` |
| 2 | `bash "$SCRIPT" --yes` |
| 3 | `bash "$SCRIPT" --backfill=best-effort` (also interactive) |
| 4 | Stop — no commands run |

For option 1, the script will prompt interactively for merge strategy
(1-6). Surface the prompt to the user via AskUserQuestion if running
non-interactively, or pass through if user is at a TTY.

### Step 6: Report verification results

Script's built-in verification (Step 9 in the script body) prints
"X passed, Y failed". Surface that to the user. If any failed, suggest
inspecting `harness/changes/` + re-running.

### Step 7: Suggest next steps

```
Migration applied. Recommended next steps:

  1. Review changes:
       git diff --stat
       git status

  2. If agent templates were updated, compare with .v0.1.bak backups:
       vimdiff harness/agents/harness-reviewer.md{,.v0.1.bak}
       vimdiff harness/agents/harness-coder.md{,.v0.1.bak}

  3. Commit:
       git add -A
       git commit -m "chore: migrate harness v0.1 -> v0.2"

  4. Try the new bug-fix lane on a real bug:
       /harness-fix <bug at file:line>
```

## Flags (forwarded to migration script)

| Flag | Effect |
|------|--------|
| `--dry-run` | Show actions only (Step 3 always runs dry-run first regardless) |
| `--yes` | Skip interactive prompt; defaults merge-strategy to `ask-later` |
| `--backfill=best-effort` | Try to recover historic commit SHAs via `git log --grep <slug>` |
| `--plugin-dir=<path>` | Override auto-detected plugin location |

## Anti-Patterns

- NEVER skip the dry-run preview — users should see what will change before applying.
- NEVER pass `--yes` automatically; always ask the user first.
- NEVER run migration twice without checking idempotency markers (the script handles this, but surface warnings).
- NEVER modify the migration script itself from this skill — if a bug surfaces, file an issue against the plugin.
