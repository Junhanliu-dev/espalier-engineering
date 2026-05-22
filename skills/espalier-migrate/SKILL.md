---
name: espalier-migrate
description: Migrate an existing harness/espalier install to the current Espalier version — auto-detects which of v0.1→v0.2, v0.3→v0.4, v0.4→v0.5, and the v0.5.3 coder-agent patch you need and applies them in order.
---

# Espalier Migration Runner

## When to Use
- "Migrate to Espalier" / "Upgrade my Espalier install"
- "Upgrade my harness to the latest version"
- "Rename harness/ to espalier/"
- "/espalier-migrate"

## When NOT to Use
- Fresh project with no existing `harness/` or `espalier/` dir → use `/espalier-init` instead.
- Already fully up to date — `/espalier-migrate` detects this itself and exits cleanly with no changes.

## Instructions

You are running a migration of an existing install to the current Espalier
version. Up to FOUR migrations may apply, always in this order:

1. **v0.1.x → v0.2.x** — typed `harness/changes/{type}/{slug}/` layout,
   `/harness-fix` lane, squash-merge decision. Mechanical:
   `scripts/migrate-v0.1-to-v0.2.sh`.
2. **v0.3.x → v0.4.0** — `harness/` → `espalier/` directory + skill rename
   (`harness-run` → `espalier`, `harness-{coding,…}` → `espalier-*`).
   Mechanical: `scripts/migrate-v0.3-to-v0.4.sh`.
3. **v0.4.x → v0.5.0** — doc-drift detection: drift hooks, the
   `/espalier-prune` + `/espalier-doctor` skills, the post-merge dispatcher,
   `.doctor-cadence`. Mechanical: `scripts/migrate-v0.4-to-v0.5.sh`.
4. **v0.5.0–v0.5.2 → v0.5.3** — appends the `## Editing Discipline` section to
   the coder sub-agent (`espalier/agents/harness-coder.md`). Mechanical:
   `scripts/migrate-v0.5.2-to-v0.5.3.sh`.

Your job: detect which one(s) apply, locate the scripts, preview, get
confirmation, apply in order. A v0.1.x install needs ALL FOUR; a v0.3.x
install needs the last three; a v0.4.x install needs the last two; a
v0.5.0–v0.5.2 install needs only the v0.5.3 patch.

### Step 1: Preflight + detect install version

Run from the current working directory (must be the target project root):

```bash
NEEDS_V01_V02=no
NEEDS_V03_V04=no
NEEDS_V04_V05=no
NEEDS_V05_PATCH=no

if [ ! -d "harness" ] && [ ! -d "espalier" ]; then
  echo "ERROR: no harness/ or espalier/ dir found — not a target install."
  echo "Use /espalier-init to set up Espalier in a fresh project."
  exit 1
fi

if [ -d "harness" ]; then
  # Pre-rename install. v0.1.x has no .merge-hook-decision; v0.2/v0.3.x has one.
  if [ ! -f "harness/.merge-hook-decision" ]; then
    NEEDS_V01_V02=yes
  fi
  NEEDS_V03_V04=yes          # harness/ always needs the rename
  NEEDS_V04_V05=yes          # ...then the doc-drift upgrade
  NEEDS_V05_PATCH=yes        # ...then the v0.5.3 coder-agent patch
elif [ -d "espalier" ]; then
  # Already renamed. v0.4.x still needs the doc-drift upgrade.
  if [ ! -f "espalier/hooks/drift-detect.sh" ] || [ ! -f "espalier/.doctor-cadence" ]; then
    NEEDS_V04_V05=yes        # v0.4.x → doc-drift upgrade
  fi
  # v0.5.3: harness-coder.md gains an "## Editing Discipline" section. It is a
  # per-project file, so a plugin update never reaches an existing install.
  if ! grep -qF "## Editing Discipline" espalier/agents/harness-coder.md 2>/dev/null; then
    NEEDS_V05_PATCH=yes
  fi
fi

if [ "$NEEDS_V01_V02" = no ] && [ "$NEEDS_V03_V04" = no ] \
   && [ "$NEEDS_V04_V05" = no ] && [ "$NEEDS_V05_PATCH" = no ]; then
  echo "Already fully up to date. Nothing to do."
  exit 0
fi
```

Report the detected plan to the user (which migration(s) will run).

### Step 2: Locate migration scripts

The skill resolves its own plugin root — no path guessing. `${CLAUDE_SKILL_DIR}`
is set by Claude Code to the directory of the running skill
(`<plugin>/skills/espalier-migrate`); the plugin root, where `scripts/` lives,
is two levels up. This resolves the *installed* plugin in every layout —
marketplace cache (`~/.claude/plugins/cache/...`), dev checkout, or symlink —
never a stray `$HOME` checkout that merely shares the name.

```bash
PLUGIN_DIR=""
# Primary: derive the plugin root from the skill's own location.
if [ -n "${CLAUDE_SKILL_DIR:-}" ] \
   && [ -f "${CLAUDE_SKILL_DIR}/../../scripts/migrate-v0.5.2-to-v0.5.3.sh" ]; then
  PLUGIN_DIR="$(cd "${CLAUDE_SKILL_DIR}/../.." && pwd)"
fi

# Fallback (rare — e.g. CLAUDE_SKILL_DIR unset): explicit override, then a
# known dev-checkout location.
if [ -z "$PLUGIN_DIR" ]; then
  for candidate in "${ESPALIER_PLUGIN_DIR:-}" "$HOME/SBM_Projects/espalier-engineering"; do
    [ -n "$candidate" ] || continue
    if [ -f "$candidate/scripts/migrate-v0.5.2-to-v0.5.3.sh" ]; then
      PLUGIN_DIR="$candidate"
      break
    fi
  done
fi

if [ -z "$PLUGIN_DIR" ]; then
  echo "ERROR: couldn't locate the Espalier plugin." >&2
  echo "If it is installed, update it: /plugin update espalier-engineering" >&2
  echo "Or set ESPALIER_PLUGIN_DIR to your espalier-engineering checkout." >&2
  exit 1
fi
```

If the primary path misses and the fallback fires, the plugin install is
likely stale (no `migrate-v0.5.2-to-v0.5.3.sh`) — tell the user to
`/plugin update espalier-engineering` first.

### Step 3: Show dry-run preview for each applicable migration

Run the dry-run for each needed migration, in order, and surface the output
verbatim:

```bash
[ "$NEEDS_V01_V02" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.1-to-v0.2.sh" --dry-run --plugin-dir="$PLUGIN_DIR/skills/espalier-init"
[ "$NEEDS_V03_V04" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.3-to-v0.4.sh" --dry-run
[ "$NEEDS_V04_V05" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.4-to-v0.5.sh" --dry-run --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V05_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.5.2-to-v0.5.3.sh" --dry-run
```

### Step 4: If v0.4→v0.5 applies, pick the doctor cadence

The v0.4→v0.5 upgrade installs `/espalier-doctor`, a periodic drift scan. Ask
the user how often it should run (`AskUserQuestion`):

```
How often should /espalier-doctor re-scout the codebase for artifact drift?
A scan is activity-gated — an idle repo never triggers one.

  1. Every change   → every-change
  2. Weekly         → weekly   (recommended)
  3. Monthly        → monthly
  4. On-demand only → manual
```

Cache the answer as `$DOCTOR_CADENCE` (default `weekly`). It is editable later
in `espalier/.doctor-cadence`.

### Step 5: Confirm with the user

Use `AskUserQuestion`:

```
The dry-run preview above shows what will change. Proceed?

Options:
  1. Apply all needed migrations, in order
  2. Apply only the next one (stop after that)
  3. Cancel — don't apply anything
```

### Step 6: Apply migration(s) in order

Apply each needed migration IN ORDER. Never reorder — each assumes the prior
completed.

```bash
[ "$NEEDS_V01_V02" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.1-to-v0.2.sh" --yes
[ "$NEEDS_V03_V04" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.3-to-v0.4.sh" --yes
[ "$NEEDS_V04_V05" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.4-to-v0.5.sh" --yes --plugin-dir="$PLUGIN_DIR" --doctor-cadence="$DOCTOR_CADENCE"
[ "$NEEDS_V05_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.5.2-to-v0.5.3.sh" --yes
```

Each script's verification block prints `X passed, Y failed`. Surface every
script's output to the user.

### Step 7: Report verification + next steps

If anything failed:

```
1. Inspect the diff: git diff
2. Restore from backup: .claude/settings.json.v0.3.bak (v0.3→v0.4 only)
3. Re-run /espalier-migrate (every script is idempotent)
```

On success:

```
Migration applied. Recommended next steps:

  1. Review the diff:
       git diff --stat
       git status

  2. Commit:
       git add -A
       git commit -m "chore: migrate to Espalier v0.5.0"

  3. If you upgraded to v0.5.0, scan for drift that accrued before the upgrade:
       /espalier-doctor

  4. Try a real flow:
       /espalier feat: <some small feature>
```

## Flags (forwarded to scripts)

**v0.1→v0.2 (`migrate-v0.1-to-v0.2.sh`):**

| Flag | Effect |
|------|--------|
| `--dry-run` | Show actions only |
| `--yes` | Skip interactive prompt; defaults merge-strategy to `ask-later` |
| `--backfill=best-effort` | Try to recover historic commit SHAs via `git log --grep <slug>` |
| `--plugin-dir=<path>` | Override auto-detected plugin location |

**v0.3→v0.4 (`migrate-v0.3-to-v0.4.sh`):**

| Flag | Effect |
|------|--------|
| `--dry-run` | Show actions only |
| `--yes` | Skip apply confirmation prompt |
| `--rewrite-history` | Also rewrite text refs inside `espalier/changes/*/pipeline-state.md` bodies |

**v0.4→v0.5 (`migrate-v0.4-to-v0.5.sh`):**

| Flag | Effect |
|------|--------|
| `--dry-run` | Show actions only |
| `--yes` | Skip apply confirmation prompt |
| `--doctor-cadence=<val>` | `/espalier-doctor` cadence: `every-change\|weekly\|monthly\|manual` (default `weekly`) |
| `--plugin-dir=<path>` | Path to the espalier-engineering plugin checkout |

**v0.5.2→v0.5.3 (`migrate-v0.5.2-to-v0.5.3.sh`):**

| Flag | Effect |
|------|--------|
| `--dry-run` | Show the section that would be appended |
| `--yes` | Skip the apply confirmation prompt |

## Anti-Patterns

- NEVER skip the dry-run preview — users should see what will change before applying.
- NEVER pass `--yes` to any script without asking the user first.
- NEVER reorder: v0.1→v0.2 before v0.3→v0.4 before v0.4→v0.5. Each migration
  assumes the previous layout.
- NEVER modify a migration script from this skill — if a bug surfaces, file an
  issue against the plugin.
