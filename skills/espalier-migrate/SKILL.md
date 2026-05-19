---
name: espalier-migrate
description: Migrate an existing harness install to Espalier — auto-detects whether you need v0.1→v0.2 (legacy typed-changes) or v0.3→v0.4 (harness/ → espalier/ rename) and dispatches to the right script.
---

# Espalier Migration Runner

## When to Use
- "Migrate to Espalier"
- "Upgrade my harness to v0.4"
- "Rename harness/ to espalier/"
- "/espalier-migrate"

## When NOT to Use
- Fresh project with no existing `harness/` or `espalier/` dir → use `/espalier-init` instead.
- Already on v0.4.0+ (`espalier/.merge-hook-decision` exists, no `harness/` dir) → no migration needed.

## Instructions

You are running a migration of an existing harness install to the current
Espalier layout. Two migrations may apply, in order:

1. **v0.1.x → v0.2.x** — typed `harness/changes/{type}/{slug}/` layout,
   `/harness-fix` lane, squash-merge decision. Mechanical: `scripts/migrate-v0.1-to-v0.2.sh`.
2. **v0.3.x → v0.4.0** — `harness/` → `espalier/` directory rename + skill
   rename (`harness-run` → `espalier`, `harness-{coding,…}` → `espalier-*`).
   Mechanical: `scripts/migrate-v0.3-to-v0.4.sh`.

Your job: detect which one(s) apply, locate the scripts, preview, get
confirmation, apply in order.

### Step 1: Preflight + detect install version

Run from current working directory (must be target project root):

```bash
NEEDS_V01_V02=no
NEEDS_V03_V04=no

if [ -d "espalier" ] && [ ! -d "harness" ]; then
  echo "Already on v0.4.0+. Nothing to do."
  exit 0
fi

if [ ! -d "harness" ] && [ ! -d "espalier" ]; then
  echo "ERROR: no harness/ or espalier/ dir found — not a target install."
  echo "Use /espalier-init to set up Espalier in a fresh project."
  exit 1
fi

# v0.1.x detector: harness/ present, no .merge-hook-decision
if [ -d "harness" ] && [ ! -f "harness/.merge-hook-decision" ]; then
  NEEDS_V01_V02=yes
fi

# v0.2/v0.3.x detector: harness/ present WITH .merge-hook-decision
if [ -d "harness" ] && [ -f "harness/.merge-hook-decision" ]; then
  NEEDS_V03_V04=yes
fi
```

If neither flag set, report to user and stop.

### Step 2: Locate migration scripts

Search common plugin install paths in this order:

```bash
PLUGIN_DIR=""
for candidate in \
  "$HOME/.claude/plugins/espalier-engineering" \
  "$HOME/.claude/plugins/espalier" \
  "$HOME/.claude/plugins/harness-engineering" \
  "$HOME/repos/espalier-engineering" \
  "$HOME/repos/harness-engineering" \
  "$HOME/SBM_Projects/espalier-engineering" \
  "$HOME/SBM_Projects/harness-engineering"; do
  if [ -f "$candidate/scripts/migrate-v0.3-to-v0.4.sh" ]; then
    PLUGIN_DIR="$candidate"
    break
  fi
done

if [ -z "$PLUGIN_DIR" ]; then
  echo "ERROR: couldn't find Espalier plugin scripts in standard locations." >&2
  echo "Set ESPALIER_PLUGIN_DIR or download via:" >&2
  echo "  curl -L -o /tmp/migrate-v03.sh https://raw.githubusercontent.com/Junhanliu-dev/espalier-engineering/v0.4.0/scripts/migrate-v0.3-to-v0.4.sh" >&2
  echo "  chmod +x /tmp/migrate-v03.sh && /tmp/migrate-v03.sh" >&2
  exit 1
fi
```

### Step 3: Show dry-run preview for each applicable migration

If `NEEDS_V01_V02=yes`:
```bash
bash "$PLUGIN_DIR/scripts/migrate-v0.1-to-v0.2.sh" --dry-run --plugin-dir="$PLUGIN_DIR/skills/espalier-init"
```

Then (after that completes) if `NEEDS_V03_V04=yes`:
```bash
bash "$PLUGIN_DIR/scripts/migrate-v0.3-to-v0.4.sh" --dry-run
```

Surface both outputs to the user verbatim.

### Step 4: Confirm with user

Use `AskUserQuestion`:

```
The dry-run preview above shows what will change. Proceed with migration?

Options:
  1. Apply both (if both are needed) — v0.1→v0.2 first, then v0.3→v0.4
  2. Apply v0.1→v0.2 only (skip rename)
  3. Apply v0.3→v0.4 only (rename, assumes already on v0.2+)
  4. Cancel — don't apply anything
```

### Step 5: Apply migration(s)

| Choice | Commands |
|--------|----------|
| 1 | `bash "$PLUGIN_DIR/scripts/migrate-v0.1-to-v0.2.sh" --yes` (interactive merge-strategy prompt may still fire) → `bash "$PLUGIN_DIR/scripts/migrate-v0.3-to-v0.4.sh" --yes` |
| 2 | `bash "$PLUGIN_DIR/scripts/migrate-v0.1-to-v0.2.sh"` |
| 3 | `bash "$PLUGIN_DIR/scripts/migrate-v0.3-to-v0.4.sh"` |
| 4 | Stop — no commands run |

### Step 6: Report verification results

Each script's built-in verification block prints `X passed, Y failed`.
Surface to user. If anything failed, suggest:

```
1. Inspect the diff: git diff
2. Restore from backup: .claude/settings.json.v0.3.bak (v0.3→v0.4 only)
3. Re-run /espalier-migrate (idempotent)
```

### Step 7: Suggest next steps

```
Migration applied. Recommended next steps:

  1. Review the diff:
       git diff --stat
       git status

  2. Commit:
       git add -A
       git commit -m "chore: migrate to Espalier v0.4.0"

  3. Try a real flow:
       /espalier feat: <some small feature>
       /espalier-fix <some known bug at file:line>
```

## Flags (forwarded to scripts)

**v0.1→v0.2 script (`migrate-v0.1-to-v0.2.sh`):**

| Flag | Effect |
|------|--------|
| `--dry-run` | Show actions only |
| `--yes` | Skip interactive prompt; defaults merge-strategy to `ask-later` |
| `--backfill=best-effort` | Try to recover historic commit SHAs via `git log --grep <slug>` |
| `--plugin-dir=<path>` | Override auto-detected plugin location |

**v0.3→v0.4 script (`migrate-v0.3-to-v0.4.sh`):**

| Flag | Effect |
|------|--------|
| `--dry-run` | Show actions only |
| `--yes` | Skip apply confirmation prompt |
| `--rewrite-history` | Also rewrite text refs inside `espalier/changes/*/pipeline-state.md` bodies |
| `--plugin-dir=<path>` | (Unused by v0.3→v0.4 — kept for parity) |

## Anti-Patterns

- NEVER skip the dry-run preview — users should see what will change before applying.
- NEVER pass `--yes` to either script without asking the user first.
- NEVER reorder: v0.1→v0.2 MUST run before v0.3→v0.4 if both are needed (the rename script assumes typed-changes layout).
- NEVER modify either script from this skill — if a bug surfaces, file an issue against the plugin.
