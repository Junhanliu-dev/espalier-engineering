---
name: espalier-simplify
description: Evidence-first simplification survey of the EXISTING code — hunt accidental complexity (dead surface, split truth, ownerless abstractions, relay layers, feature fossils), prove each candidate with a consumer map and a decisive check, write the ranked inventory to espalier/wiki/simplify-survey.md, and file proven cuts as refactor change skeletons that /espalier runs through its full coder + review panel. Read-only against source; never deletes code itself. Docs that describe retired surface get flagged for /espalier-prune.
---

# Espalier Simplify

A standalone lane that reduces what the codebase must keep coherent: the
number of facts, states, contracts, checks, and concepts a maintainer has to
hold in their head. Fewer lines are evidence, never the objective — a run may
conclude that the inspected surface is already justified, and that is a valid
result.

Method adapted from `tt-a1i/simplify-codebase` (MIT) — prove first, then
delete. The enforcement is Espalier's: the survey is read-only, every cut runs
as a normal `refactor` change through `/espalier` (approval gate, coder,
two-agent panel, exit gates, push gate), and the docs that described the
retired surface are flagged into the drift sidecar for `/espalier-prune`.

It is NOT a pipeline. No stages, no gates, no round counters. It writes ONE
wiki page, files change skeletons on request, and flags docs. It never edits
source, never spawns `harness-coder`, and never blocks anything.

## When to Use

- "/espalier-simplify" — survey the whole repo
- "/espalier-simplify src/billing" — survey one area
- "/espalier-simplify are the two readiness flags the same state?" — one lead
- "What in this codebase is dead / duplicated / over-built?"
- After a big feature lands or a product line is retired — the code that
  supported it usually outlives it.

Do NOT use for:
- A style or readability pass → the pipeline's Readability Review already
  runs on every change; a repo-wide restyle is not a simplification.
- Performance tuning → `/espalier refactor: <what>` with a measured goal.
- A change you already know how to make → `/espalier refactor: <what>`.
- Reviewing a diff → the Stage 4 panel (its Minimalism Review covers
  over-building in NEW code; this lane covers what is ALREADY there).

## Trigger

```
/espalier-simplify [scope]
```

`scope` is optional. A path that exists (`src/api`, `packages/core`)
restricts the survey to partitions under it (**Broad, bounded**). Any other
text is a **Focused** lead — a subsystem, symbol, flag, dependency, or
suspected duplication in the user's words; cover that boundary thoroughly
before widening. No scope → **Broad**, whole repo. No other flags.

## Preconditions

Needs an Espalier install whose contract map exists:
`espalier/wiki/architecture.md`, `espalier/rules/engineering-structure.md`,
`espalier/rules/security-standards.md`, and `espalier/hooks/drift-helpers.sh`.
If `espalier/.greenfield` exists or any of those is missing, stop and tell the
user to finish `/espalier-init` (or `/espalier-migrate`) — a survey without
the discovered contract cannot tell a dead export from a plugin hook.

## Procedure

### 1. Establish the contract (docs first, code second)

Espalier already wrote the decision records a simplification must respect.
Read, in this order, and keep notes — this is the map every scout gets:

1. `espalier/rules/engineering-structure.md` + `espalier/wiki/architecture.md`
   — the layer / module map (the Broad partition list) and dependency
   directions.
2. `espalier/rules/security-standards.md` → Trust Boundary + sensitive-field
   taxonomy; `espalier/rules/production-standards.md` → resilience /
   observability / data-safety controls. Everything named there is
   **protected surface** (step 3).
3. `espalier/wiki/external-services.md`, `espalier/wiki/data-models.md`,
   `espalier/wiki/critical-paths.md` — wire contracts, persisted
   representations, migrations, entry points.
4. `espalier/skills/espalier-coding/specs/*.md` — the mandated per-layer
   shapes: a construct a spec mandates is never "ownerless flexibility".
5. Decision history: `espalier/changes/*/*/requirements.md` (newest 20 —
   folders sort chronologically) and `review-record.md` for anything naming
   the area; a prior `espalier/wiki/simplify-survey.md` (its `JUSTIFIED` rows
   and filed cuts are decisions, not leads to re-find);
   `espalier/wiki/security-audit.md` if present (`Controls Confirmed` are
   contracts).
6. Version-control state: `git status --porcelain` (unrelated work is left
   alone); generated / vendored / fixture / migration dirs
   (`.gitattributes` `linguist-generated`, `vendor/`, `generated/`,
   `__snapshots__`, migration folders); published-package surfaces
   (`package.json` `exports` / `main`, `pyproject` entry points, public API
   routes).

Record the survey commit — `SURVEY_SHA=$(git rev-parse --short HEAD)` — it
goes in the page header and is the `--since` anchor for the doctor later.

**Byproduct — a doc contradicted by the code** (a module the architecture
page lists no longer exists; an external service the wiki names is imported
nowhere): flag it, do not edit it:

```bash
. espalier/hooks/drift-helpers.sh
mark_stale "espalier/wiki/architecture.md" "$(git rev-parse HEAD)" "simplify-verify: <one-line mismatch>"
```

and surface one line pointing at `/espalier-prune <that file>`.

### 2. Partition and spawn the scouts (read-only)

**Broad:** one partition per layer in `engineering-structure.md`'s module
map, plus ONE cross-cutting partition (build / config / feature flags / env
keys, dependency manifests, scripts, CI, tests + fixtures, docs / examples).
Group partitions by directory into at most 4 batches and spawn them
concurrently in ONE message. A batch must never split a layer from the layer
that registers or dispatches it (a handler from its router, a plugin from its
registry) — group by ownership, not alphabetically. **Focused:** one scout on
the named boundary, one on everything that consumes it.

Scouts are read-only Agent-tool spawns using the Scout Prompt below. They
return proof records as their final message; they write nothing. A scout that
returns nothing usable is re-spawned once; a second failure is recorded in the
page's Coverage section as a blind spot — never silently dropped.

```
Agent tool (read-only — Read, Grep, Glob, Bash for searches only):
  prompt: |
    {Scout Prompt below — CONTRACT MAP, PRIOR DECISIONS, PARTITION filled in}
```

### 3. Consolidate and rank

Merge the batches. Two records with the same cut boundary are one candidate
(keep the stronger evidence). Then classify EVERY record — nothing is left
unclassified:

| Class | Bar |
|-------|-----|
| `HIGH` | Contract proof reached: every repository hit classified (runtime / support / uncertain — none left uncertain), dynamic and external reachability resolved, no protected surface inside the cut, a decisive check named, net effect positive (concepts removed > machinery added). |
| `LEAD` | Consumer map done but a named fact is still missing (an external consumer, a persisted format, a plugin registration). The record states the exact fact that decides it. |
| `JUSTIFIED` | A real consumer, a current decision (rule, spec, requirement, ADR) that still owns the design, or a cut that would only relocate complexity. Kept on the page when the rejection teaches something; otherwise dropped. |

Rank `HIGH` by confidence first, benefit second — a small proved cut outranks
a large guess. Line counts, candidate counts, and dramatic scope earn nothing.
A survey that finds no `HIGH` candidate is a valid, complete result.

**One candidate per ownership boundary.** A shape guardrail and the
implementation it once described are SEPARATE candidates with separate proof
records and cut boundaries — retiring one is never authority to retire the
other; the same holds for any two cuts that merely sit near each other. Each
filed skeleton (step 5) carries exactly one boundary. A boundary too large
for one `/espalier` session (dozens of files across layers, a data
migration, a published API version) is never filed as one skeleton: keep it
`LEAD — needs a map` and give the exact invocation
`/espalier-map retire: {boundary} (simplify-survey #{n})` — the map copies
the row's `simplify_from` into map.md and into every slice it files, so the
pipeline's simplification machinery still fires per slice. On a later
survey run, a row whose `#{n}` appears in some `espalier/maps/*/map.md`
frontmatter reads `map: {map-slug} ({status})` and is never re-proposed
while that map is IN_PROGRESS or CLEARED.

**Rule-owned constructs are `JUSTIFIED`, never cuts.** A construct that
`espalier/rules/` or a layer spec mandates stays — write
`JUSTIFIED (owned by rules/{file})` even when the RULE itself looks
over-built. The survey never edits a rule: if the rule is the burden, say so
on the row and route it through the Stage 0 convention-promotion path or a
`/espalier docs:` change, not a deletion.

**Protected surface is never an incidental cut.** Authorization and ownership
checks, input-trust validation, security isolation, data-loss prevention,
stored-format and migration compatibility, cleanup that establishes
quiescence, accessibility essentials, and every control
`security-standards.md` / `production-standards.md` requires. A candidate
that would retire one is recorded as `LEAD` with its `Consequence:` spelled
out; it becomes `HIGH` only when the user explicitly directs it, and the filed
requirement then says so in its own words. Deleting a reachable capability,
supported interface, or compatibility path is a PRODUCT decision — the survey
describes the consequence; the pipeline's approval gate is where it is decided.

### 4. Write the wiki page

Write — OVERWRITE, current state only — `espalier/wiki/simplify-survey.md`:

```markdown
# Simplification Survey — {project}

> Point-in-time survey generated by `/espalier-simplify`. Re-run the skill to
> refresh; do NOT `/espalier-prune` this page (it has no scout source — it is
> regenerated, not refreshed). Not drift-tracked.

- **Date:** {YYYY-MM-DD}
- **Commit:** {SURVEY_SHA}
- **Scope:** {scope-path | "focused: <lead>" | "full repo"}
- **Coverage:** {N partitions across M batches; blind spots: …}
- **Result:** {X} HIGH · {Y} LEAD · {Z} JUSTIFIED — or NOTHING TO CUT

## Candidates
| # | Class | Cut boundary | Burden retired | Consequence | Decisive check | Status |
|---|-------|--------------|----------------|-------------|----------------|--------|
| 1 | HIGH | src/export/v1/* + `legacyExport` flag + 3 fixtures | one export format, one flag, 2 sync paths | none — no caller since 2025-11 (git log) | `test/export` suite green; `grep -rn legacyExport` empty | OPEN |

## Proof Records
{one block per HIGH / LEAD candidate, in the Proof Record format below —
verbatim from the scout, merged when two scouts hit the same boundary}

## Justified (kept on purpose)
{candidate — why it stays — the decision that owns it (rule / spec /
requirement / file:line)}

## Unresolved leads
{candidate — the ONE fact that decides it — where to find it}

## Coverage
{per partition: entrypoints inspected, central paths read, searches run,
records consulted, blind spots}
```

`Status` starts `OPEN` for every `HIGH` row. Filing a cut (step 5) rewrites
its cell to `refactor/{slug}`; on every later survey run, re-derive that
row's live state from `espalier/changes/refactor/{slug}/pipeline-state.md`
(`FILED` / `IN_PROGRESS` / `COMPLETE` / `ABORTED` …) as
`refactor/{slug} (COMPLETE)`, and never re-propose a candidate whose change
is COMPLETE (the surface is gone) or IN_PROGRESS. A later run PRESERVES
`JUSTIFIED` rows and their reasons unless the evidence changed (the owning
decision was removed, a consumer disappeared) — say what changed when you
flip one.

After writing the page, commit it immediately (`git add
espalier/wiki/simplify-survey.md && git commit -m 'docs(espalier):
simplification survey {date}'`) — a filed change requires a clean tree at
Stage 7 and must never sweep this page into its own commit.

### 5. Offer the handoff (interactive only) — file cuts as refactor skeletons

Decide interactivity with the explicit-signal helper — NEVER a bash TTY test
(stdin has no TTY inside Claude Code even with the user right there):

```bash
. espalier/hooks/drift-helpers.sh
interactivity_mode        # -> "interactive" | "unattended"
```

If there are `HIGH` candidates AND the run is interactive, ask ONE
`AskUserQuestion` (multiSelect) listing each `HIGH` row — label
`#{n} {cut boundary, ≤60 chars} — {consequence, ≤40 chars}` — plus the
implied "none for now" via selecting nothing. For EACH selected candidate,
file a change skeleton exactly as a cleared `/espalier-map` does (the
pipeline's FILED-skeleton scan adopts it; `refactor/` is scanned like `feat/`):

1. Derive the requirement title `refactor: retire {cut boundary, short}` and
   its `{kebab}` by the pipeline's rule (kebab-case, max 80 chars, slashes
   stripped) → `espalier/changes/refactor/{YYYY-MM-DD}-{kebab}/`. Draft the
   requirement text (step 2) and score it with `espalier-grill` in
   `mode=score` — the map lane's crispness gate: `skip` / `light` → file
   it; a would-be-`full` draft still carries fog the record did not
   resolve — do NOT file it, downgrade the row to `LEAD` naming the
   missing fact, and move on.
2. `requirements.md` — frontmatter + the proof record + the retired-surface
   list + acceptance criteria that name the checks:

   ```markdown
   ---
   simplify_from: wiki/simplify-survey.md#{n}
   survey_commit: {SURVEY_SHA}
   ---
   # refactor: retire {cut boundary}

   ## Simplification Evidence
   {the candidate's Proof Record, verbatim}

   ## Retired Surface
   {one identifier per line — every symbol, file, route, config key, env
   var, flag, event / protocol string, table / column, fixture, doc section,
   dependency, and script inside the cut boundary; the coder retires ALL of
   them, the reviewer re-searches EACH, and the pipeline's Completion step
   greps the espalier docs for them}

   ## Acceptance Criteria
   - [ ] Every entry under Retired Surface is gone — declaration,
         registration, dispatch, implementation, imports / exports /
         barrels, generated inventories, config, fixtures, docs, dedicated
         tests, dependencies.
   - [ ] Residue search (`grep -rn` for each retired name, string, path,
         key) is empty outside git history and CHANGELOG.
   - [ ] Decisive check: {from the record} passes; the surviving contract's
         tests pass.
   - [ ] No replacement machinery (shim, adapter, sync layer, compat
         branch) unless named here: {none | the one consumer that needs it}.
   - [ ] Consequence accepted: {the observable behavior or compatibility
         surrendered, in plain words — or "none"}.

   ## Scope Definition
   - **In scope:** {files / dirs in the cut boundary}
   - **Out of scope:** {adjacent candidates on the page — one change per
         ownership boundary}
   ```

3. `pipeline-state.md` from `espalier/changes/_template/pipeline-state.md`
   with `- Status: FILED` added under `## Status` (a non-active status: the
   push gate ignores it and nothing resumes it until adopted).
4. Rewrite the page row's `Status` cell to `refactor/{slug}`; commit page +
   skeletons together: `git add espalier/wiki/simplify-survey.md
   espalier/changes/refactor && git commit -m 'docs(espalier): file
   simplification cuts {date}'`.

Then tell the user how to run them — one per fresh session is the default (a
deletion is a product decision; the approval gate and the panel deserve a
clean context): `/espalier refactor: retire {cut boundary}` for each
skeleton, earliest-unblocking first. Offer (`AskUserQuestion`) to start the
FIRST one now in this session; never start more than one. Stage 1 begins from
the drafted requirements — the grill covers only what the record leaves open
(the consequence acceptance is the product question; expect it to be asked).

Only an EXPLICITLY unattended run (`CI` / `ESPALIER_UNATTENDED` /
`ESPALIER_LOOP` / `ESPALIER_HEADLESS` → `interactivity_mode` returns
`unattended`) skips the handoff: write the page, print its path and the
HIGH / LEAD counts, file nothing. If you (the orchestrator) can call
`AskUserQuestion`, you ARE interactive and MUST offer it.

### 6. After a cut lands — docs, prune, doctor

The refactor change runs the normal pipeline: the coder retires the whole
boundary and reports a `### Retired Surface` block; the reviewer re-searches
every retired name for a consumer the record missed (a hit is a P0
`[simplify-consumer]` — the round FAILs; the survey row was wrong, not the
coder). A missed consumer the coder cannot prove dead ABORTS the change:
the pipeline reverts the cut (never a partial delete), flips the row to
`LEAD — missed consumer: {file:line}`, and the next survey starts from that
fact. The security auditor sees any control that moved. At **Completion**
the pipeline (not this skill) greps `espalier/wiki/`, `espalier/rules/`, and
`espalier/skills/espalier-coding/specs/` for every Retired Surface identifier
and `mark_stale`s each doc that still describes it (reason
`simplify: <name> retired in refactor/{slug}`) — the post-merge detector keys
off paths, so a doc that names a deleted function would otherwise stay green.
Refresh is `/espalier-prune --all-stale` (gated, per file); these are YOUR
OWN flags, so the feature-branch escape hatch in prune's Multi-Developer
Discipline applies — one isolated `docs:` commit — or leave the rows for the
weekly maintenance run.

After a batch of cuts (several changes COMPLETE since the survey), run
`/espalier-doctor --since {SURVEY_SHA}` — it re-scouts only the layers those
changes touched and catches the silent drift a name grep cannot (a layer
whose description is now half-true).

## Scout Prompt

```
You are a read-only simplification scout for {project}. You SEARCH and READ;
you write nothing and change nothing. Your job is to find accidental
complexity in ONE partition and PROVE or REJECT each lead with evidence.
Search results are leads, never deletion authority.

CONTRACT MAP (respect every line — these are decisions, not leads):
{layers + dependency directions; protected surface: trust-boundary controls,
sensitive-field taxonomy, production seeds; external services + wire
contracts; persisted models + migrations; entry points; per-layer mandated
shapes; generated / vendored / fixture / public-package dirs}

PRIOR DECISIONS (never re-propose; cite if relevant):
{JUSTIFIED rows + filed / complete cuts from the previous survey, if any}

PARTITION: {directories / responsibilities this scout owns}

HUNT with these lenses — each is a burden the team must keep coherent:
- Dormant contract: export, hook, event, option, route, command, package,
  protocol field with no current production consumer.
- Split truth: several states, caches, summaries, formats, or event families
  encode ONE fact and must stay synchronized.
- Ownerless flexibility: abstraction, fallback, strategy, flag, or extension
  point no current product path owns (one implementation, nothing sets it).
- Relay layer: wrapper, package, service, or route that forwards without
  reducing coupling or establishing a boundary.
- Parallel state machine: flags, promises, queues, sentinels, callbacks
  describing the same transition for the same owner.
- Boundary theater: validation, copying, rollback, or defensive code on a
  TRUSTED same-owner handoff (NOT on an owned boundary: untrusted input,
  storage, network, plugins, workers — those are protected).
- Local infrastructure: hand-rolled parsing / retry / matching / scheduling
  that the platform or an already-installed dependency provides (NEVER
  propose a NEW dependency).
- Support drag: tests, snapshots, examples, docs are the ONLY reason a
  surface remains.
- Feature fossil: the feature is gone; schema, config, tests, compat logic,
  or design records still carry its outline.
- Implementation-shape guardrail: a test, source scan, snapshot, inventory,
  import ban, or build / CI check that enforces file layout, literal source
  text, private defaults, exact component counts, or a historical
  implementation identity without owning observable behavior. NEVER one
  that enforces an active rule in `espalier/rules/`, a layer spec, or a
  shipped espalier hook (`check-layer-boundaries.sh`, `pre-push-gate.sh`)
  — that is live engineering policy, not a fossil. Provenance ("written by
  an AI", a "defensive" label, an old date) is a discovery hint, never
  removal evidence.

Do NOT equate visual similarity with duplication — independent
implementations may isolate failure domains, protect different owners, or
serve different compatibility contracts. A construct the CONTRACT MAP
mandates (layer shape, project wrapper) is never a lead.

For every lead, CLIMB THE EVIDENCE LADDER and stop at the rung you reach:
1 smell → 2 static lead (search / analyzer says unused) → 3 consumer map
(EVERY repository hit classified runtime / support / uncertain, callers and
callees READ) → 4 contract proof (dynamic loading, string dispatch, config
keys, reflection, templates, external / published use, persisted data,
ownership, design history all resolved) → 5 behavior proof (the decisive
check that would fail if the cut were wrong). Search exact symbols AND their
alternate forms: file / package names, config + env keys, event / protocol
strings, serialized field names, registry ids, doc examples. Read git log /
blame for the reason the surface exists and whether it still holds.

Prove cut boundaries BELOW file granularity when a candidate shares a file
with surviving code: name the exact members, selectors, fields, keys,
registry entries, generated fragments, and fixtures that are
candidate-exclusive.

Return ONLY proof records, one per lead that reached rung 3 or higher —
at most 12, strongest evidence first; every further lead is ONE line
(`Lead: {what} — {rung reached} — {next fact}`) — in this exact format
(plus one line naming each partition sub-area you did NOT inspect and why):

Candidate: {exact contract / representation / layer to remove or merge}
Lens: {one of the lenses above}
Burden: {concepts, sync, publication, or test cost it creates today}
Reachability: runtime={…} support={…} dynamic={resolved: …|UNRESOLVED: …} external={…} persisted={…}
Rationale: {why it exists (git log / blame) — does that reason still hold?}
Cut: {declarations, registrations, implementations, branches, artifacts, docs, tests, deps affected — file:line}
Consequence: {observable capability or compatibility surrendered — or "none"}
Protected: {none | which protected surface it touches}
Confidence: {rung reached 3|4|5} / Risk: {blast radius, reversibility}
Proof: {the smallest check that exposes an incorrect cut}
Net effect: {concepts removed − replacement / migration machinery added}
```

## Cost

MEDIUM — 1-4 read-only scouts over the partitions plus one wiki write; scales
with the partition count, not repo size (use a scope path on a large
codebase). Each filed cut is a full `/espalier` refactor run on top, budgeted
like any change.

## What This Skill Does NOT Do

- Never edits or deletes source code, and never spawns `harness-coder` —
  every cut is a `refactor` change through `/espalier`, with its own approval
  gate, coder, two-agent panel, exit gates, and push gate.
- Never blocks anything. No gate reads the survey page; it is an inventory.
- Never edits a rule, wiki, or spec — a contradicted doc is flagged
  (`mark_stale`), and the docs describing retired surface are flagged by the
  pipeline's Completion step; refresh is `/espalier-prune`.
- Never retires protected surface as a side effect — a control moves only as
  an explicitly requested change whose requirement says so.
- Never appends history — the page is OVERWRITTEN per run (Status cells and
  JUSTIFIED decisions carried forward as described); git holds prior surveys.
- Does not replace `/espalier-doctor` (a systematic drift scan) — it points
  at `--since {SURVEY_SHA}` once a batch of cuts has landed.
