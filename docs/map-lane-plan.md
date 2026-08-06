# v0.18.0 — Map Lane + Greenfield (Decide, Then Bind)

Design record for the `/espalier-map` multi-session planning lane, the
greenfield init path, and the boilerplate workflow docs. Shipped together as
v0.18.0 on top of v0.17.0.

## Why

Espalier's planning ceiling has been one session: Stage 1 grill caps at 7
questions, one requirement → one `changes/{type}/{slug}/` folder → 10 stages.
There is a lane below the full pipeline (`/espalier-fix`) but nothing above it.
An epic-scale effort lands in one oversized `requirements.md`; a greenfield
repo cannot run `/espalier-init` at all, because Phase 1 discovery scouts have
no code to read ("Discover, Don't Prescribe" dead-ends at zero code).

The lane concept is adapted from **Matt Pocock's `wayfinder` skill**
([mattpocock/skills](https://github.com/mattpocock/skills), MIT): a big foggy
effort is charted as a **map** of **decision tickets** and resolved one ticket
per session until the route is clear. Wayfinder's own field reports name its
open wounds — agents writing production code mid-map, no machine enforcement
of "plan, don't do", waterfall over-charting. Espalier's core thesis ("if a
constraint can't be machine-verified, the agent WILL drift") supplies exactly
those missing mechanisms: a PreToolUse guard hook, escalation caps in
`.espalier-config`, state files with status-driven resume, and the grill's
Step 1.5 rules/wiki cross-check applied to every decision before it locks.

## The three tiers after v0.18.0

| Scale | Lane |
|---|---|
| Single bug | `/espalier-fix` |
| One feature (fits one session) | `/espalier` (grilled) |
| Epic / greenfield / multi-session fog | `/espalier-map` → slices → `/espalier` per slice |

## Feature 1 — `/espalier-map` lane

New pure-copy skill `espalier-map` (folder = frontmatter name, per the naming
invariant). Local file tracker — no GitHub Issues dependency, consistent with
the file-per-key philosophy and the in-repo audit chain:

```
espalier/maps/{YYYY-MM-DD}-{kebab}/
├── map.md              # index, not store: Destination / Notes / Decisions so far
│                       # / Not yet specified (fog) / Out of scope / Spawned Changes
├── tickets/NNN-{kebab}.md   # one file per decision ticket
└── assets/             # research findings, prototype links — linked, never pasted
```

Ticket frontmatter: `type: grilling|prototype|research|task`,
`status: open|closed|out-of-scope`, `blocked_by: [NNN,…]`, `claimed_by:`
(git user.email; empty = unclaimed). The **frontier** = open + all blockers
closed + unclaimed — derivable by grep, no tracker API.

Core contracts (each machine-checked or state-recorded, not vibes):

- **Plan, don't do.** A map session writes only under `espalier/maps/`. The
  session drops a marker (`espalier/maps/.active-session`); the `map-guard.sh`
  PreToolUse hook blocks Write/Edit outside the allowlist while the marker
  exists (exit-2 contract). Task-ticket scaffold windows are opened by
  appending user-approved `allow: <prefix>` lines to the marker. A stale
  marker (>12h) reads as inactive, so a crashed session never bricks the repo.
  There is **no Notes-based execution override** — upstream wayfinder's
  self-licensing hole (agent writes its own exemption, reads it back later) is
  closed by construction.
- **One ticket per session** (research tickets exempt — they run as parallel
  scout/oracle subagents). Recorded in the map's session log.
- **`max-open-tickets`** (default 9, `espalier/.espalier-config`) — the
  anti-waterfall cap. Charting past the cap forces narrow-the-destination /
  split-the-map / raise-the-cap, echoing the existing escalation-cap pattern.
- **Grilling tickets resolve via `espalier-grill` `mode=decision`** — the
  divergent-candidates questioning technique plus Step 1.5's blind-spot pass,
  so every decision is cross-checked against `espalier/rules/` and
  `espalier/wiki/` before it locks. This is the lane's sharpest advantage over
  upstream wayfinder: a decision that collides with an encoded convention is
  caught at charting time, not at Stage 4 review.
- **No-fog exit.** If the opening breadth-first grill surfaces no fog, the
  effort fits one session — route to `/espalier` and write no map.
- **Handoff = FILED skeletons.** A cleared map slices its decisions into
  implementation changes and files each as an existing-mechanism `Status:
  FILED` skeleton under `espalier/changes/feat/` with `charted_from:
  maps/{slug}` frontmatter — the same adoption path the fix lane's
  PARTIAL_FIX root-cause feats already use. `/espalier` adopts them; the
  audit chain reads decision → ticket → change → commit.

## Feature 2 — Greenfield init (Decide, Then Bind)

`/espalier-init` gains a near-empty-repo path. Brownfield rules cite observed
patterns (`file:line`); greenfield rules cite resolved decisions
(`decided_in: maps/{slug}/tickets/NNN`). Two passes:

- **Pass 1:** Phase 0 questions as normal → `bootstrap-espalier.sh
  --greenfield --lang=unsupported` → full wiring (all lane skills incl.
  espalier-map, hooks, config) but: a placeholder `pre-push-gate.sh`, no
  rules/wiki content, and a tracked `espalier/.greenfield` marker that makes
  validation render checks 38–45 as "pending greenfield Pass 2" skips.
  Then chart: `/espalier-map greenfield: <idea>` — typical tickets: stack
  (research), architecture/layers, error-handling and naming conventions,
  core domain model, testing strategy (grilling), scaffold via the chosen
  boilerplate CLI (the one task ticket, through a guard-approved window).
- **Pass 2 (map CLEARED):** re-run `/espalier-init`. It detects
  `.greenfield` + a cleared map, synthesizes the DISCOVERY blob **from the
  map's decisions**, merged with normal Phase 1 scouts over whatever the
  scaffold ticket produced (decisions win conflicts; scouts fill gaps),
  runs the standard Phase 2 substitution writes with `decided_in:` citations,
  overwrites the placeholder gate, removes the marker, and runs
  `--validate-only`.

The maintenance loop stays coherent: rules bootstrap the first code, then the
code becomes ground truth and drift/prune/doctor operate exactly as on
brownfield.

## Feature 3 — Boilerplate workflow (docs only)

A boilerplate repo has code, so plain `/espalier-init` already discovers its
conventions. The product is the fog. Documented order: **init first, then
map** — init makes the map's Step 1.5 cross-check live, so product decisions
collide with the boilerplate's own discovered rules ("new HTTP client?"
collides with `wiki/external-services.md`). README gains a
"Greenfield & boilerplate" section; the CLAUDE.md / AGENTS.md /
copilot-instructions bootstrap sections gain the `/espalier-map` line.

## Wiring deltas

- `templates/skills/espalier-map.md` (new, pure-copy) + Stage 3 cp + Stage 2
  mkdir (`espalier/skills/espalier-map`, `espalier/maps`).
- `hook-templates/map-guard.sh` (new, non-substitution) + Stage 4 cp; wired as
  PreToolUse Write|Edit in `.claude/settings.json` (additive merge), a
  marker-guarded `ESPALIER MAP GUARD v1` block in `.codex/config.toml`, and a
  `preToolUse` entry in fresh `.github/hooks/espalier-gates.json` (existing
  copilot installs: migration inserts it if absent).
- `ESPALIER_SKILL_NAMES` += espalier-map → symlinks on all three platforms.
- `espalier/.espalier-config` += `max-open-tickets: 9` (append-if-missing).
- `--greenfield` bootstrap flag (placeholder gate + `.greenfield` marker +
  validation skip set 38–45).
- Validation: +2 checks (59 map-skill wired, 60 map-guard executable +
  registered) → totals 50 claude / 55 codex / 60 copilot.
- `scripts/migrate-v0.17.0-to-v0.18.0.sh` (migration #25): mkdir + cp + chmod
  + platform symlinks per `espalier/.platforms` + settings/codex/copilot hook
  wiring + config key + one-line lane mentions in the platform instruction
  files + pure-copy refresh of `espalier-grill` / `espalier` SKILL files
  (backup-on-diff `<file>.pre-v0.18.bak`).

## Deferred (explicitly)

- GitHub-Issues tracker mode (native blocking UI) — local markdown first;
  the format keeps ticket identity stable so a later exporter is mechanical.
- Eval fixtures for the map lane (grill-eval precedent) — follow-up release.
- Auto-flip of map status → BUILT from Stage 10 — v1 offers it as a prompt in
  the adopting lane's completion, no hard wiring.
