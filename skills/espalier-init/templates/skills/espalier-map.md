---
name: espalier-map
description: Multi-session planning lane — chart an effort too big for one session (an epic, a greenfield build, a product on a boilerplate) as a map of decision tickets under espalier/maps/, then resolve them one ticket per session until the way to the destination is clear; a cleared map hands off as FILED change skeletons for /espalier, never as code. Slash: /espalier-map
---

# Espalier Map

A planning lane for efforts **too big for one session**. It charts the effort
as a **map** — a named destination plus **decision tickets** — under
`espalier/maps/`, then works the tickets one session at a time until nothing
is left to decide before someone goes and builds the thing. The concept is
adapted from Matt Pocock's `wayfinder` skill (MIT); the enforcement — the
write-guard hook, the ticket cap, the rules/wiki cross-check on every
decision — is Espalier's.

**This lane plans. It never does.** Every ticket resolves a question; the map
is finished when the route is clear. The one exception is the `task` ticket
type, which earns its place only by unblocking a decision — and even that runs
through an explicitly approved write window (see The Session Marker).

## When to Use

- "/espalier-map <loose idea>" — chart a new map
- "/espalier-map <map slug> [ticket NNN]" — work the next (or a named) ticket
- "/espalier-map" — list maps in flight and ask which to work
- An `/espalier` requirement that is really an epic (many features, many
  sessions, route unclear) — that lane will suggest coming here
- A greenfield repo (via `/espalier-init`'s greenfield path) or a boilerplate
  repo whose product decisions are still fog

Do NOT use for:
- Work that fits one session → `/espalier <requirement>` (Stage 1 grill is the
  single-session planner). The split is **session count, not project size**.
- A bug → `/espalier-fix <bug>`.
- Questions about the codebase → `/espalier-ask <question>`.
- Executing a cleared map → `/espalier` per spawned slice; this lane never
  writes product code.

## Storage Layout (the local tracker)

The map is files, not an issue tracker — same audit-chain philosophy as
`espalier/changes/`. Everything is git-tracked.

```
espalier/maps/{YYYY-MM-DD}-{kebab}/       # date prefix: lexical sort == chronological
├── map.md                                # the index — low-res view, loaded once per session
├── tickets/
│   ├── 001-{kebab}.md                    # one file per ticket (file-per-key: two sessions
│   ├── 002-{kebab}.md                    #  on different tickets can never merge-conflict)
│   └── ...
└── assets/                               # research findings, prototype pointers — linked, never pasted
```

### map.md

```markdown
---
map: {slug}
status: IN_PROGRESS        # IN_PROGRESS | CLEARED | BUILT | ABANDONED
started: {ISO timestamp}
---

# Map: {title}

## Destination

<what reaching the end looks like — the spec, locked decision, or scaffolded
skeleton this effort is finding its way to. One or two lines; every session
orients to it before choosing a ticket.>

## Notes

<domain; skills every session should consult; standing preferences.
NEVER an execution override — this lane has no "carry execution into the map"
switch. Write windows exist only per task ticket, per session, user-approved.>

## Decisions so far

<!-- the index — one line per closed ticket; the detail lives in the ticket -->
- [001 — {ticket title}](tickets/001-{kebab}.md) — {one-line gist of the answer}

## Not yet specified

<!-- the fog: decisions you can tell are coming but cannot phrase sharply yet.
     Test: can you state the QUESTION precisely now? (Not: can you answer it.)
     Sharp → ticket (even if blocked). Not sharp → one loose line here. -->

## Out of scope

<!-- work ruled beyond the destination. Never graduates. One line + why,
     linking the closed ticket if one was mis-charted. -->

## Session log

| Date | Ticket | Action |
|------|--------|--------|

## Spawned Changes

<!-- filled at handoff: one row per FILED slice -->
| Change | Status |
|--------|--------|
```

### Ticket files

`tickets/NNN-{kebab}.md` — NNN is a zero-padded ordinal, assigned once, never
reused. The file IS the ticket's identity.

```markdown
---
ticket: NNN
title: {short title}
type: grilling            # grilling | prototype | research | task
status: open              # open | closed | out-of-scope
blocked_by: []            # ticket ordinals, e.g. [001, 004]; [] = unblocked
claimed_by:               # git user.email of the working dev; empty = unclaimed
claimed_at:
---

## Question

<the decision or investigation this ticket resolves — sized to one session>

## Resolution

<!-- written on close: the answer, its rationale, and any rules/wiki citations
     from the grill's cross-check. Assets linked, never pasted. -->
```

**The frontier** — the tickets a session may take — is every ticket with
`status: open`, every `blocked_by` ordinal pointing at a `closed` ticket, and
an empty `claimed_by`. Derive it by reading frontmatter; in bash:

```bash
grep -l '^status: open' espalier/maps/{slug}/tickets/*.md
```

then filter blockers/claims from each file's frontmatter. Refer to tickets **by
title** in everything the user reads — the ordinal rides inside the link, never
stands in for the name.

## Ticket Types

Every ticket is **HITL** (worked with the human, who speaks for themselves —
never answer your own questions) or **AFK** (agent-driven).

| Type | Mode | Reach for it when | Resolved by |
|------|------|-------------------|-------------|
| `grilling` | HITL | The default: the question settles by talking it through. | `espalier-grill` in `mode=decision` (see below) |
| `prototype` | HITL | "How should it look/behave" — talking can't settle it. | A cheap, rough artifact on a throwaway branch or in `assets/`; the USER picks the winner — never close a prototype ticket on your own choice. |
| `research` | AFK | A fact outside this repo blocks a decision (library capability, API shape, best practice). | scout/oracle subagents (ctx7 + web, same pattern as init Phase 1); findings land in `assets/` + the Resolution. |
| `task` | Either | Nothing to decide, but manual work blocks a decision — provisioning, signing up, scaffolding so the shape can be seen. | The agent alone where it can (through an approved write window), else a precise checklist for the human. |

`task` is the only type that *does*, and it exists to **unblock a decision** —
never to deliver a piece of the destination. A task ticket that reads like a
slice of the build is mis-typed: move it to the handoff.

Research is the only type exempt from one-ticket-per-session — fire all
unblocked research tickets as parallel subagents whenever you touch the map.

### Grilling tickets — `espalier-grill` `mode=decision`

Invoke the `espalier-grill` skill with `mode=decision`, `input_text` = the
ticket's Question plus the map's Destination and relevant Decisions-so-far
lines, and `reqs_path` = the ticket file. Decision mode keeps grill's
machinery — sequential questions chosen by listing 3–5 divergent candidate
answers and asking what eliminates most, the ≤ 8 code-read budget, and
**Step 1.5's rules/wiki cross-check** — so a decision that collides with an
encoded convention (`espalier/rules/`, `espalier/wiki/`) is surfaced as a
citation-carrying question BEFORE it locks. Resolutions land in the ticket's
`## Resolution`, criteria-grade, with citations.

## The Session Marker (plan-don't-do, enforced)

Every map session — chart or work — starts by writing the marker and ends by
removing it:

```bash
mkdir -p espalier/maps
printf 'map: %s\nsession_started: %s\n' "{slug}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  > espalier/maps/.active-session
```

While the marker exists, the `map-guard.sh` PreToolUse hook **blocks every
Write/Edit outside `espalier/maps/`** (exit-2 contract). This is the
machine-enforced form of "plan, don't do" — the drift this lane's upstream
inspiration is best known for is structurally impossible here.

- **Task-ticket write windows:** when a task ticket genuinely needs writes
  outside the map (a scaffold CLI, a config file), ask the user first
  (`AskUserQuestion`: run it / checklist for the human / skip), and on
  approval append `allow: <path-prefix>` lines to the marker — one per
  approved prefix. The window dies with the marker at session end.
- **Stale markers:** the guard treats a marker older than 12h as inactive, so
  a crashed session never bricks later work. Still remove it on every exit
  path — including aborts.
- **Session end:** remove the marker, then commit the map bookkeeping:
  `git add espalier/maps && git commit -m 'chore(espalier): map {slug} — {charted|ticket NNN resolved|handoff}'`.
  Claims only coordinate across devs once pushed — on a shared map, push the
  claim commit before starting long work.

## Invocation — Chart (new map)

Input: a loose idea. Output: a map with its first frontier. **Charting
hand-resolves nothing** — it is one session's work, and it stops.

1. **Marker up** (slug derived below).
2. **Name the destination.** Grill the idea itself (`espalier-grill`
   `mode=decision` on "what does DONE look like for this effort?") until the
   destination is one or two sharp lines. The destination fixes the scope
   every later ticket is measured against. Scope it to a bounded epic — "the
   whole product" is the waterfall trap; slice V1 out of it.
3. **Map the frontier, breadth-first.** Fan out across the space — open
   decisions, first steps takeable now, suspected fog. Do NOT go deep on any
   one thread. **No-fog exit:** if this surfaces no fog — the route is already
   clear, the effort fits one session — write no map: remove the marker and
   route the user to `/espalier <requirement>`.
4. **Create the map.** Slug = `{YYYY-MM-DD}-{kebab-of-title}` (date PREFIX —
   lexical sort must equal chronological, same rule as changes/). Write
   `map.md` with Destination + Notes filled, Decisions-so-far empty, the fog
   sketched into Not-yet-specified.
5. **Create the tickets you can state sharply now** — create files first, then
   wire `blocked_by` in a second pass (ordinals must exist before they can be
   referenced). Everything not yet sharp stays in the fog section — do NOT
   pre-slice fog into ticket-sized pieces.
   **Cap check:** creating a ticket when open tickets ≥ `max-open-tickets`
   (default 9; `grep '^max-open-tickets:' espalier/.espalier-config`, fall
   back to 9) → stop and ask: narrow the destination / split into two maps /
   raise the cap for this repo. Never silently exceed it.
6. **Fire the research tickets** — every `research` ticket spawns its
   scout/oracle subagent now, in parallel; write findings into `assets/` and
   each ticket's Resolution, close them, and index them in Decisions-so-far.
7. **Marker down, commit, stop.** Report the map path, the frontier by name,
   and the next command (`/espalier-map {slug}`).

## Invocation — Work (one ticket)

Input: a map slug/path, optionally a ticket. **One non-research ticket per
session. Then stop.** Expect other sessions (other devs) to be editing the
map concurrently — claims exist for exactly that.

1. **Marker up.** Load `map.md` only — the low-res view. Zoom into individual
   tickets on demand; never bulk-read every ticket.
2. **Choose the ticket.** Named by the user → that one. Otherwise the first
   frontier ticket by ordinal. Nothing on the frontier but open tickets
   remain → report what blocks what, by name, and stop. **Claim it** before
   any work: set `claimed_by: $(git config user.email)` + `claimed_at`.
   A claimed-by-someone-else ticket is not yours — pick the next.
3. **Resolve by type** (table above). Grilling → `espalier-grill`
   `mode=decision`. If resolution reveals the ticket sits beyond the
   destination → set `status: out-of-scope`, add the one-line Out-of-scope
   entry (gist + why), and it never appears in Decisions-so-far.
4. **Record.** Write `## Resolution` in the ticket, set `status: closed`,
   append the one-line gist to the map's Decisions-so-far, add a Session-log
   row.
5. **Graduate the fog.** Re-read Not-yet-specified: anything the answer made
   sharp becomes a new ticket (create-then-wire, cap check applies) and is
   REMOVED from the fog section — a patch lives as fog or ticket, never both.
   If the answer invalidates existing open tickets, update or close them and
   say so. New research tickets fire immediately (the exemption).
6. **Cleared check.** No open tickets AND an empty Not-yet-specified → the map
   is CLEARED: run the Handoff below in this same session.
7. **Marker down, commit, stop** — report the resolution gist, what
   graduated, and the next frontier by name.

## Handoff (map CLEARED → FILED skeletons)

A cleared map is linked decisions, not a build plan. Collapse it into
implementation slices and file each as a change skeleton `/espalier` already
knows how to adopt:

1. Set `status: CLEARED` in map.md.
2. **Slice the destination** into implementation changes a single `/espalier`
   run can hold — each slice ≤ ~5 files expected (the espalier-requirements
   decomposition rule), ordered so earlier slices unblock later ones.
3. For each slice, create `espalier/changes/feat/{YYYY-MM-DD}-{kebab}/`:
   - `requirements.md` — draft: goal line, the acceptance-criteria lines the
     relevant Resolutions already settled (with their citations), scope
     in/out, and frontmatter:

     ```markdown
     ---
     charted_from: maps/{map-slug}
     tickets: [NNN, NNN]
     ---
     ```
   - `pipeline-state.md` from `espalier/changes/_template/pipeline-state.md`
     with `- Status: FILED` added under `## Status`.
4. Add every slice to the map's Spawned Changes table (`FILED`).
5. Tell the user the run order: `/espalier <slice 1 requirement>` … — the
   pipeline's FILED-skeleton scan adopts each folder, and Stage 1 starts from
   the drafted requirements (already part-grilled by the map; Stage 1 grill
   then covers only what the slice adds).
6. When later `/espalier` runs complete a spawned change, they may offer to
   flip this map's status to `BUILT` once every row is COMPLETE. (Offer —
   never auto-flip.)

Skip the slicing ONLY when the cleared map turned out genuinely small (one
slice): file the one skeleton and say so.

## Greenfield mode

When invoked from `/espalier-init`'s greenfield path
(`/espalier-map greenfield: <idea>`), the destination template is fixed:
*"conventions + architecture decided; skeleton scaffolded; ready for
decision-sourced init Pass 2."* Typical tickets: stack choice (research),
architecture/layers, error-handling convention, naming, testing strategy,
core domain model (grilling), scaffold via the chosen boilerplate CLI (the
one task ticket, through an approved write window). On CLEARED, the handoff
is different: instead of FILED slices, route the user back to
`/espalier-init` — its Pass 2 reads this map's Resolutions as the DISCOVERY
source and generates rules/wiki/skills citing `decided_in:
maps/{slug}/tickets/NNN`. Product-feature slices come after that, from a
second, normal map or straight `/espalier` runs.

If `espalier/rules/` and `espalier/wiki/` are empty (greenfield Pass 1), the
grill's Step 1.5 has no map to cross-check — it skips silently, by its own
contract. If `espalier/hooks/drift-helpers.sh` is missing (partial install),
skip the helper sourcing and treat the session as interactive — degrade, never
crash.

## Concurrency

- Claims are the lock: assignee IS the claim, and an open unclaimed ticket is
  takeable. Push claim commits early on shared maps.
- Two sessions editing different tickets can never conflict (file-per-ticket).
  Same-ticket conflicts mean a claim was skipped — resolve by keeping the
  earlier claim, moving the later work to a fresh session.
- map.md is the one shared file; its append-y sections (Decisions so far,
  Session log) merge like the conventions playbook: on conflict, keep both
  lines.

## Anti-Patterns

- NEVER write product code, tests, or config outside `espalier/maps/` in a map
  session — the guard blocks it, and an approved `allow:` window is the ONLY
  exception. If the pull to "just build it" is strong, that is the signal the
  map is cleared (or this ticket belongs in the handoff).
- NEVER resolve more than one non-research ticket in a session.
- NEVER answer your own grilling/prototype questions — HITL tickets resolve
  only through the live exchange.
- NEVER let a ticket read "build the X" — a ticket is a question; deliverables
  live past the handoff.
- NEVER restate a resolution's detail in map.md — the map gists and links; a
  decision lives in exactly one place (its ticket).
- NEVER leave a graduated fog patch in Not-yet-specified, and never pre-slice
  fog into tickets you cannot yet state sharply.
- NEVER charge past `max-open-tickets` — over-charting is how ticket 13
  invalidates tickets 14–27.
- NEVER refer to a ticket by bare ordinal in narration — names read, numbers
  don't.

## Platform fallbacks (Codex / Copilot)

| Claude Code mechanic | Substitute |
|---|---|
| `/espalier-map` slash | `$espalier-map` (Codex) / the same-named Agent Skill (Copilot) |
| `AskUserQuestion` | ask in chat, numbered, and WAIT — never proceed on a guessed answer |
| scout/oracle research subagents | platform subagents with the same prompts, else run the research inline, sequentially |
| `map-guard.sh` PreToolUse | wired via `.codex/config.toml` / `.github/hooks/espalier-gates.json`; where a surface runs no hooks (VS Code chat), the marker contract above is the gate — honor it in-skill |
