# Migrating v0.17.0 → v0.18.0

v0.18.0 is the **map-lane release**: the `/espalier-map` multi-session
planning lane (decision maps under `espalier/maps/`), the `map-guard`
plan-don't-do hook, grill `mode=decision`, and the greenfield
decide-then-bind init path (that last one is plugin-side — nothing to migrate
in an existing install).

## What the migration does

Run `/espalier-migrate` (recommended) or the script directly:

```bash
bash <plugin>/scripts/migrate-v0.17.0-to-v0.18.0.sh --dry-run   # preview
bash <plugin>/scripts/migrate-v0.17.0-to-v0.18.0.sh --yes       # apply
```

- **New files:** `espalier/skills/espalier-map/SKILL.md` (+ a symlink for
  every platform recorded in `espalier/.platforms` — `.claude/skills/`,
  `.agents/skills/`, `.github/skills/`), `espalier/hooks/map-guard.sh`, and
  the empty `espalier/maps/` dir (it enters git with its first map).
- **Pure-copy refresh** (backup-on-diff → `<file>.pre-v0.18.bak`):
  `espalier/pipeline.md` (lanes note), the `espalier` SKILL (epic router hint,
  map-slice adoption, completion offer) and the `espalier-grill` SKILL
  (`mode=decision`).
- **Wiring:** `.claude/settings.json` gains one PreToolUse `Write|Edit` entry
  for the map-guard (additive merge — your own hooks are untouched);
  `.codex/config.toml` gains the marker-guarded `ESPALIER MAP GUARD v1` block
  (run `/hooks` once in Codex to trust it); the Copilot
  `.github/hooks/espalier-gates.json` gets a targeted `preToolUse` insert —
  the file is otherwise preserved, and an unparseable file is warned about,
  never clobbered.
- **Config:** appends `max-open-tickets: 9` to `espalier/.espalier-config`
  (append-if-missing; your tuning survives).
- **Instruction files:** one grep-guarded `/espalier-map` line inside the
  existing `## Espalier` section of `CLAUDE.md` / `AGENTS.md` /
  `.github/copilot-instructions.md`, per wired platform.

## What changes day-to-day

- **A third altitude.** `/espalier-fix` for a bug, `/espalier` for a feature
  that fits one session, `/espalier-map` for the effort that doesn't — an
  epic, a greenfield build, a product on a boilerplate. The `/espalier` lane
  now says so in one line when a `feat:` smells like an epic, exactly the way
  it already demotes small `fix:` requirements.
- **Plan, don't do — enforced.** A map session drops
  `espalier/maps/.active-session`; while it exists (and is fresher than 12h),
  the map-guard blocks Write/Edit outside `espalier/maps/` with the standard
  exit-2 contract. Task tickets that genuinely need outside writes get a
  user-approved `allow: <prefix>` window in the marker. No marker — zero
  overhead; the hook is inert in every non-map session.
- **One ticket per session** (research tickets exempt — they run as parallel
  scouts). A cleared map hands back FILED slices; run `/espalier` per slice
  and the pipeline adopts them with their `charted_from:` audit link.
- **Decisions meet your conventions.** Grilling tickets run the grill in
  `decision` mode: candidate answers are cross-checked against
  `espalier/rules/` and `espalier/wiki/` before the decision locks.

## Compatibility

- The map tracker is plain files (file-per-ticket, same reasoning as the
  v0.17 conventions file-per-key): two devs on different tickets can never
  merge-conflict; claims are the lock (`claimed_by` frontmatter — push claim
  commits early on shared maps); `map.md`'s append-y sections resolve
  conflicts by keeping both lines.
- Greenfield installs converge to normal brownfield behavior: the decided
  rules bootstrap the first code, then drift/doctor/prune/conventions treat
  the code as ground truth exactly as before. Early convention-promotion
  prompts while the first features land are the system converging, not a
  defect.
- Attribution: the lane concept is adapted from Matt Pocock's `wayfinder`
  skill (MIT — [mattpocock/skills](https://github.com/mattpocock/skills));
  the storage format, guard hook, caps, and grill integration are Espalier's.
