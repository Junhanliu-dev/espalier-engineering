---
name: espalier-migrate
description: Migrate an existing harness/espalier install to the current Espalier version — auto-detects which of v0.1→v0.2, v0.3→v0.4, v0.4→v0.5, the v0.5.3 coder-agent patch, v0.5→v0.6 (Stage 1 grill), v0.6→v0.7 (read-only /espalier-ask lane), v0.7→v0.8 (requirements approval gate), the v0.8.1 impact-analysis agent patch, the v0.8.2 re-review fixpoint loop, and the v0.9.0 security audit you need and applies them in order.
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
version. Up to TEN migrations may apply, always in this order:

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
5. **v0.5.x → v0.6.0** — Stage 1 grilling: installs the `espalier-grill` skill,
   refreshes the four changed pipeline templates (which also date-prefix change
   folders). Mechanical: `scripts/migrate-v0.5-to-v0.6.sh`.
6. **v0.6.x → v0.7.0** — read-only ask lane: installs the `espalier-ask` skill,
   patches CLAUDE.md + `espalier/agent.md` to mention `/espalier-ask`. Purely
   additive — no pipeline change. Mechanical: `scripts/migrate-v0.6-to-v0.7.sh`.
7. **v0.7.x → v0.8.0** — requirements approval gate: refreshes the three changed
   pipeline templates (`pipeline.md`, `espalier`, `espalier-fix`) so both
   pipelines STOP for explicit user sign-off after the requirement is written +
   reviewed, before any code is written (no-TTY runs auto-approve). Mechanical:
   `scripts/migrate-v0.7-to-v0.8.sh`.
8. **v0.8.0 → v0.8.1** — impact-analysis agent patch: appends a
   `## Change Impact Analysis` section to the coder sub-agent
   (`espalier/agents/harness-coder.md`) and a `## Runtime-Surface Review` section
   to the reviewer sub-agent (`espalier/agents/harness-reviewer.md`). Both make
   the agents reason about every surface a change touches (admin UIs, API
   validation, client forms, persisted data, other callers) — not just the
   programmatic happy path — so a now-derived value left user-required on a UI is
   caught at coding/review instead of returning as a fix round. Mechanical:
   `scripts/migrate-v0.8-to-v0.8.1.sh`.
9. **v0.8.1 → v0.8.2** — re-review fixpoint loop + push-gate certificate: code
   review becomes a loop — every coder fix is re-reviewed until a fresh review of
   the current code returns zero P0 — and the push gate blocks unless the pushed
   code matches the fingerprint the last review saw. Refreshes the two pure-copy
   pipeline files (`pipeline.md`, `espalier-fix`), appends a `## Re-review Rounds`
   section to `harness-reviewer.md`, and inserts the certificate check into
   `pre-push-gate.sh`. Mechanical: `scripts/migrate-v0.8.1-to-v0.8.2.sh`.
10. **v0.8.2 → v0.9.0** — security audit: a new `harness-security` agent joins
   Stage 4 as a review panel; a `security-standards` rule + `espalier-security`
   skill are added, and the coder/reviewer/testing/push-gate gain security
   sections. Creates the three new files, `bootstrap --force` refreshes the
   pure-copy pipeline + symlinks + runs the 32-check validation, and surgical
   appends patch the per-project files. Mechanical:
   `scripts/migrate-v0.8.2-to-v0.9.0.sh`.

Your job: detect which one(s) apply, locate the scripts, preview, get
confirmation, apply in order. A v0.1.x install needs ALL TEN; a v0.3.x
install needs the last nine; a v0.4.x install needs the last eight; a
v0.5.0–v0.5.2 install needs the v0.5.3 patch then v0.6 … v0.9.0; a v0.5.3–v0.5.x
install needs v0.6 … v0.9.0; a v0.6.x install needs v0.7 … v0.9.0; a v0.7.x
install needs v0.8 … v0.9.0; a v0.8.0 install needs v0.8.1 … v0.9.0; a v0.8.1
install needs v0.8.2 then v0.9.0; a v0.8.2 install needs only v0.9.0.

### Step 1: Preflight + detect install version

Run from the current working directory (must be the target project root):

```bash
NEEDS_V01_V02=no
NEEDS_V03_V04=no
NEEDS_V04_V05=no
NEEDS_V05_PATCH=no
NEEDS_V05_V06=no
NEEDS_V06_V07=no
NEEDS_V07_V08=no
NEEDS_V08_PATCH=no
NEEDS_V082_PATCH=no
NEEDS_V09_MINOR=no

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
  NEEDS_V05_V06=yes          # ...then the v0.6 Stage 1 grill
  NEEDS_V06_V07=yes          # ...then the v0.7 ask lane
  NEEDS_V07_V08=yes          # ...then the v0.8 approval gate
  NEEDS_V08_PATCH=yes        # ...then the v0.8.1 impact-analysis agent patch
  NEEDS_V082_PATCH=yes       # ...then the v0.8.2 re-review fixpoint loop
  NEEDS_V09_MINOR=yes        # ...then the v0.9.0 security audit
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
  # v0.6.0: the espalier-grill skill is new AND must be wired into Stage 1 of
  # espalier-requirements. Absence of either signals a pre-v0.6 install.
  if [ ! -f "espalier/skills/espalier-grill/SKILL.md" ] \
     || ! grep -q "Grill the requirement" espalier/skills/espalier-requirements/SKILL.md 2>/dev/null; then
    NEEDS_V05_V06=yes
  fi
  # v0.7.0: the espalier-ask skill is new. Its absence signals a pre-v0.7
  # install (independent of grill — migrations run in order, so v0.6 installs
  # grill before v0.7 installs ask).
  if [ ! -f "espalier/skills/espalier-ask/SKILL.md" ]; then
    NEEDS_V06_V07=yes
  fi
  # v0.8.0: both pipelines gain a requirements approval gate. It is wired into
  # the pure-copy espalier skill; absence of the gate text signals pre-v0.8.
  if ! grep -q "Requirements Approval Gate" espalier/skills/espalier/SKILL.md 2>/dev/null; then
    NEEDS_V07_V08=yes
  fi
  # v0.8.1: the two sub-agents gain change-impact / runtime-surface guidance.
  # Per-project files, so a plugin update never reaches an existing install.
  # Either section missing signals a pre-v0.8.1 install.
  if ! grep -qF "## Change Impact Analysis" espalier/agents/harness-coder.md 2>/dev/null \
     || ! grep -qF "## Runtime-Surface Review" espalier/agents/harness-reviewer.md 2>/dev/null; then
    NEEDS_V08_PATCH=yes
  fi
  # v0.8.2: code review becomes a fixpoint loop + push-gate certificate. The loop
  # rides the pure-copy pipeline files; the reviewer gains a Re-review Rounds
  # section and the push gate gains a Reviewed-Diff certificate (both per-project
  # files a plugin update cannot reach). Any of the three missing ⇒ pre-v0.8.2.
  if ! grep -qF "fixpoint loop" espalier/pipeline.md 2>/dev/null \
     || ! grep -qF "## Re-review Rounds" espalier/agents/harness-reviewer.md 2>/dev/null \
     || ! grep -qF "Reviewed-Diff:" espalier/hooks/pre-push-gate.sh 2>/dev/null; then
    NEEDS_V082_PATCH=yes
  fi
  # v0.9.0: the security audit. A new harness-security agent joins Stage 4 as a
  # review panel; a security-standards rule + espalier-security skill are added and
  # the coder/reviewer/gate gain security sections. The "review panel" text rides
  # the pure-copy pipeline; harness-security.md is a new per-project file a plugin
  # update cannot reach — either absent ⇒ pre-v0.9.0.
  if ! grep -qF "review panel" espalier/pipeline.md 2>/dev/null \
     || [ ! -f espalier/agents/harness-security.md ]; then
    NEEDS_V09_MINOR=yes
  fi
fi

if [ "$NEEDS_V01_V02" = no ] && [ "$NEEDS_V03_V04" = no ] \
   && [ "$NEEDS_V04_V05" = no ] && [ "$NEEDS_V05_PATCH" = no ] \
   && [ "$NEEDS_V05_V06" = no ] && [ "$NEEDS_V06_V07" = no ] \
   && [ "$NEEDS_V07_V08" = no ] && [ "$NEEDS_V08_PATCH" = no ] \
   && [ "$NEEDS_V082_PATCH" = no ] && [ "$NEEDS_V09_MINOR" = no ]; then
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
   && [ -f "${CLAUDE_SKILL_DIR}/../../scripts/migrate-v0.7-to-v0.8.sh" ]; then
  PLUGIN_DIR="$(cd "${CLAUDE_SKILL_DIR}/../.." && pwd)"
fi

# Fallback (rare — e.g. CLAUDE_SKILL_DIR unset): explicit override, then a
# known dev-checkout location.
if [ -z "$PLUGIN_DIR" ]; then
  for candidate in "${ESPALIER_PLUGIN_DIR:-}" "$HOME/SBM_Projects/espalier-engineering"; do
    [ -n "$candidate" ] || continue
    if [ -f "$candidate/scripts/migrate-v0.7-to-v0.8.sh" ]; then
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
likely stale (no `migrate-v0.7-to-v0.8.sh`) — tell the user to
`/plugin update espalier-engineering` first.

### Step 3: Show dry-run preview for each applicable migration

Run the dry-run for each needed migration, in order, and surface the output
verbatim:

```bash
[ "$NEEDS_V01_V02" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.1-to-v0.2.sh" --dry-run --plugin-dir="$PLUGIN_DIR/skills/espalier-init"
[ "$NEEDS_V03_V04" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.3-to-v0.4.sh" --dry-run
[ "$NEEDS_V04_V05" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.4-to-v0.5.sh" --dry-run --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V05_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.5.2-to-v0.5.3.sh" --dry-run
[ "$NEEDS_V05_V06" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.5-to-v0.6.sh" --dry-run --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V06_V07" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.6-to-v0.7.sh" --dry-run --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V07_V08" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.7-to-v0.8.sh" --dry-run --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V08_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.8-to-v0.8.1.sh" --dry-run
[ "$NEEDS_V082_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.8.1-to-v0.8.2.sh" --dry-run --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V09_MINOR" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.8.2-to-v0.9.0.sh" --dry-run --plugin-dir="$PLUGIN_DIR"
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
[ "$NEEDS_V05_V06" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.5-to-v0.6.sh" --yes --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V06_V07" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.6-to-v0.7.sh" --yes --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V07_V08" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.7-to-v0.8.sh" --yes --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V08_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.8-to-v0.8.1.sh" --yes
[ "$NEEDS_V082_PATCH" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.8.1-to-v0.8.2.sh" --yes --plugin-dir="$PLUGIN_DIR"
[ "$NEEDS_V09_MINOR" = yes ] && bash "$PLUGIN_DIR/scripts/migrate-v0.8.2-to-v0.9.0.sh" --yes --plugin-dir="$PLUGIN_DIR"
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

**v0.5→v0.6 (`migrate-v0.5-to-v0.6.sh`):**

| Flag | Effect |
|------|--------|
| `--dry-run` | Show actions only |
| `--yes` | Skip the apply confirmation prompt |
| `--plugin-dir=<path>` | Path to the espalier-engineering plugin checkout |

Backs up any customised pipeline skill on diff (`<file>.pre-v0.6.bak`), then
`bootstrap --force` installs the `espalier-grill` skill and refreshes the four
changed pipeline templates (which also date-prefix new change folders).
Idempotent — re-running detects an already-v0.6 install and no-ops.

**v0.6→v0.7 (`migrate-v0.6-to-v0.7.sh`):**

| Flag | Effect |
|------|--------|
| `--dry-run` | Show actions only |
| `--yes` | Skip the apply confirmation prompt |
| `--plugin-dir=<path>` | Path to the espalier-engineering plugin checkout |

Backs up any customised pure-copy pipeline file on diff (`<file>.pre-v0.7.bak`),
then `bootstrap --force` installs the `espalier-ask` skill and symlinks it.
Also patches CLAUDE.md + `espalier/agent.md` to mention `/espalier-ask` (the
bootstrap CLAUDE.md writer is append-once and never touches agent.md).
Purely additive — no pipeline change. Idempotent — re-running detects an
already-v0.7 install and no-ops.

**v0.7→v0.8 (`migrate-v0.7-to-v0.8.sh`):**

| Flag | Effect |
|------|--------|
| `--dry-run` | Show actions only |
| `--yes` | Skip the apply confirmation prompt |
| `--plugin-dir=<path>` | Path to the espalier-engineering plugin checkout |

Backs up any customised pure-copy pipeline file on diff (`<file>.pre-v0.8.bak`),
then `bootstrap --force` refreshes the three changed pipeline templates
(`pipeline.md`, `espalier`, `espalier-fix`) — adding the requirements approval
gate that stops both pipelines for explicit user sign-off before any code is
written (no-TTY runs auto-approve). No new skill, no pipeline stage added.
Idempotent — re-running detects an already-v0.8 install and no-ops.

**v0.8→v0.8.1 (`migrate-v0.8-to-v0.8.1.sh`):**

| Flag | Effect |
|------|--------|
| `--dry-run` | Show the sections that would be appended |
| `--yes` | Skip the apply confirmation prompt |

Appends a `## Change Impact Analysis` section to `harness-coder.md` and a
`## Runtime-Surface Review` section to `harness-reviewer.md` (both per-project
files a plugin update cannot reach). Patches each file independently and is
idempotent per file — re-running detects already-patched agents and no-ops. No
`--plugin-dir` needed (the patch appends inline text; the flag is accepted and
ignored for a uniform call signature).

**v0.8.1→v0.8.2 (`migrate-v0.8.1-to-v0.8.2.sh`):**

| Flag | Effect |
|------|--------|
| `--dry-run` | Show actions only |
| `--yes` | Skip the apply confirmation prompt |
| `--plugin-dir=<path>` | Path to the espalier-engineering plugin checkout |

Backs up any customised pure-copy pipeline file on diff (`<file>.pre-v0.8.2.bak`),
then `bootstrap --force` refreshes the two changed pure-copy files (`pipeline.md`,
`espalier-fix`) with the re-review fixpoint loop + `Reviewed-Diff` certificate
writes. Surgically appends a `## Re-review Rounds` section to the per-project
`harness-reviewer.md` and inserts the certificate check into the per-project
`pre-push-gate.sh` (graceful warn + manual snippet if the gate was customised past
the anchor). Idempotent — re-running detects an already-v0.8.2 install and no-ops.

**v0.8.2→v0.9.0 (`migrate-v0.8.2-to-v0.9.0.sh`):**

| Flag | Effect |
|------|--------|
| `--dry-run` | Show actions only |
| `--yes` | Skip the apply confirmation prompt |
| `--plugin-dir=<path>` | Path to the espalier-engineering plugin checkout |

Creates the three new per-project files (security-standards rule, harness-security
agent, espalier-security skill) with project-name + tools-mode substitution, then
`bootstrap --force` refreshes the pure-copy pipeline files + symlinks + runs the
32-check validation. Surgically appends the security sections to the per-project
`harness-coder.md` / `harness-reviewer.md` / `espalier-testing` SKILL and inserts
the secret/dependency scan into `pre-push-gate.sh`. Idempotent — the already-v0.9.0
check requires all five artifacts present, so a crash mid-run is completed on re-run.

## Anti-Patterns

- NEVER skip the dry-run preview — users should see what will change before applying.
- NEVER pass `--yes` to any script without asking the user first.
- NEVER reorder: v0.1→v0.2 before v0.3→v0.4 before v0.4→v0.5. Each migration
  assumes the previous layout.
- NEVER modify a migration script from this skill — if a bug surfaces, file an
  issue against the plugin.
