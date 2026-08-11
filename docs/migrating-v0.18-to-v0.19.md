# Migrating v0.18.0 → v0.19.0

v0.19.0 is the **run-lane release**: `/espalier-maprun` drives a CLEARED map's
FILED slices to completion over hours and days — an interactive **master**
pass dispatches headless pipeline **workers** (stages 1–6) into isolated,
push-blocked git worktrees, merges what passes into an integration branch,
relays worker questions to the human, and stops. All run **state** lives on
disk (`plan.json` + `state.json` beside the map), so a master killed by quota
exhaustion, network loss or a closed laptop resumes exactly where it stopped.

## What the migration does

Run `/espalier-migrate` (recommended) or the script directly:

```bash
bash <plugin>/scripts/migrate-v0.18.0-to-v0.19.0.sh --dry-run   # preview
bash <plugin>/scripts/migrate-v0.18.0-to-v0.19.0.sh --yes       # apply
```

- **New files:** `espalier/skills/espalier-maprun/SKILL.md` (+ a symlink for
  every platform recorded in `espalier/.platforms`) and the run engine —
  `espalier/hooks/maprun.py` plus
  `maprun-{dispatch,merge,integration,verify}.sh`.
- **Engine files are write-if-absent.** A repo already carrying a
  locally-adapted maprun engine (the lane was field-built inside a production
  repo before being generalized) keeps its own files; only the SKILL doctrine
  refreshes (backup-on-diff). Delete a local engine file and re-run the
  migration to adopt the upstream version of it.
- **Pure-copy refresh** (backup-on-diff → `<file>.pre-v0.19.bak`):
  `espalier/pipeline.md` (lanes note names the batch executor) and the
  `espalier-map` SKILL (the handoff now offers both run options).
- **Instruction files:** one grep-guarded `/espalier-maprun` line inside the
  existing `## Espalier` section of `CLAUDE.md` / `AGENTS.md` /
  `.github/copilot-instructions.md`, per wired platform.
- **No config keys, no hook wiring.** The run lane is invoked, never
  event-driven; per-map execution config lives in the map's own
  `plan/plan.json`, authored by `/espalier-maprun <map> plan`.

## What changes day-to-day

- **The map executes itself.** `/espalier-map` still plans; a cleared map's
  handoff now offers two run options: adopt slices one at a time with
  `/espalier`, or author `plan/plan.json` once (`/espalier-maprun <map> plan`)
  and then advance the whole map one **pass** at a time (`/espalier-maprun
  <map>`). A pass reaps, merges, relays questions, grills, dispatches, and
  stops — the workers keep grinding after your session ends.
- **One pass, one fresh session.** Everything a pass needs is on disk;
  master memory of a previous pass is stale by definition. The skill tells
  you to `/clear` between passes and treats `status` output as the only
  memory.
- **Workers cannot push and cannot ask.** Push is blocked at git config
  level in every worktree; questions park into the worker's own change
  folder and reap carries them to the master — the human answers them at the
  next pass. Stages 7–10 (push, CI, deploy, acceptance) remain a deliberate
  human act on the assembled integration branch.
- **Two worker shapes.** `worker_mode: session` (default) runs a ticket in
  one headless session; `staged` runs one fresh session per stage group
  (1–2 / 3–4 / 5–6) for bounded context on long tickets, with the generated
  wrapper — not the master — owning the loop.
- **Optional trackers.** `clickup`/`harvest` blocks in `plan.json` sync a
  board and one time entry per ticket; absent config is a silent no-op and
  sync failures never block the build.

## Requirements

Workers need a local headless CLI: Claude Code (`claude -p`) or Codex
(`codex exec`) — set `worker_platform` in `plan.json`. Run the master from an
interactive Claude Code or Codex session. A Copilot-only install receives the
skill but cannot dispatch workers until one of those CLIs is present.

## Validation

Bootstrap validation grows to **52 / 57 / 62** checks (claude / +codex /
+copilot): #61 maprun-skill wired, #62 maprun engine present + executable.
