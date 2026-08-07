# v0.18.0 Implementation Plan — Map Lane + Greenfield + Boilerplate

Companion to `docs/map-lane-plan.md` (design rationale). This file is the
executable checklist: every file, every edit, every check number, in commit
order. Base: `feat/map-lane` branched off `feat/multi-dev-maintenance`
(v0.17.0). v0.17.0 ships tonight untouched; v0.18.0 stacks on top.

Status legend: `[x]` already landed on the branch, `[ ]` pending.

---

## Phase A — New artifacts (plugin side)

### A1. `[x]` `docs/map-lane-plan.md` — design record
Rationale, wayfinder attribution (MIT, Matt Pocock), three-tier lane table,
deferred list (GitHub-Issues tracker mode, evals, BUILT auto-flip).

### A2. `[x]` `skills/espalier-init/templates/skills/espalier-map.md` — the lane skill (pure-copy)
~300 lines, `name: espalier-map` (folder = frontmatter, naming invariant).
Contracts encoded:
- Storage: `espalier/maps/{YYYY-MM-DD}-{kebab}/` — `map.md` (index, not
  store: Destination / Notes / Decisions-so-far / Not-yet-specified /
  Out-of-scope / Session-log / Spawned-Changes) + `tickets/NNN-{kebab}.md`
  (frontmatter: `type: grilling|prototype|research|task`,
  `status: open|closed|out-of-scope`, `blocked_by: []`, `claimed_by`,
  `claimed_at`) + `assets/`. File-per-ticket = no cross-ticket merge
  conflicts (same argument as v0.17 file-per-key).
- Frontier = open ∧ blockers-closed ∧ unclaimed; grep-derivable; refer by
  name, never bare ordinal.
- Session marker `espalier/maps/.active-session` (map slug +
  `session_started:` + zero-or-more `allow: <prefix>` lines); skill writes it
  at session start, removes on EVERY exit path; commits map bookkeeping at
  session end (`chore(espalier): map {slug} — …`).
- Chart mode: destination named first (grilled), breadth-first fog pass,
  **no-fog exit** routes to `/espalier`, create-then-wire tickets,
  `max-open-tickets` cap check, research tickets fired in parallel at end,
  stop (charting resolves nothing).
- Work mode: load map.md low-res only → pick/claim frontier ticket → resolve
  by type → `## Resolution` + close + gist line + session-log row → graduate
  fog (remove from fog when ticketed) → cleared-check → stop. ONE
  non-research ticket per session.
- Ticket types: grilling → `espalier-grill mode=decision`; research → AFK
  scout/oracle (the one-per-session exemption); prototype → HITL, user picks
  winner; task → does-only-to-unblock, write windows via user-approved
  `allow:` marker lines.
- Handoff on CLEARED: slice → `espalier/changes/feat/{slug}/` skeletons with
  `Status: FILED` + `charted_from: maps/{slug}` + `tickets: [NNN,…]`
  frontmatter — adopted by `/espalier`'s EXISTING FILED-skeleton scan (reuse,
  no new adoption machinery). Spawned-Changes table tracks them; BUILT flip
  is offer-only.
- Greenfield mode: fixed destination template; on CLEARED routes back to
  `/espalier-init` Pass 2 instead of slicing.
- Degrade rules: missing `drift-helpers.sh` → treat interactive; empty
  rules/wiki → Step 1.5 skips silently.
- Anti-patterns list + Codex/Copilot fallback table.

### A3. `[x]` `skills/espalier-init/hook-templates/map-guard.sh` — the plan-don't-do guard (non-substitution)
PreToolUse; blocks Write/Edit outside allowlist while marker fresh.
- Contract verified by 8 smoke cases (scratch repo): no-marker→0,
  outside-write→2 + stderr reason, maps-path→0, `allow:` window→0,
  traversal/absolute `allow:` rejected→2, stale (>12h mtime)→0,
  apply_patch body parsed→2, outside-repo path→0.
- Same JSON extraction as `post-edit-wrapper.sh` (tool_input.file_path +
  `*** Add/Update File:` patch lines) → works under Claude, Codex, and the
  Copilot camelCase adapter unchanged. No python → advisory exit 0 (same
  policy as post-edit). BSD/GNU `stat` both handled.

### A4. `[x]` `templates/skills/espalier-grill.md` — decision mode (pure-copy)
- `[x]` description mentions `/espalier-map` + decision mode.
- `[x]` Inputs table row `decision` + "Decision-mode deltas" subsection:
  skip Step 1 signal-count (default tier `light`, user can bump), Step 1.5
  cross-checks CANDIDATE ANSWERS (unchanged silent-skip on empty rules/wiki),
  Step 2 divergent-candidates technique, Step 3 writes ticket
  `## Resolution` (+ `(default — revisit)` on non-answer), verdicts
  `GRILLED | SKIPPED: non-interactive`.
- `[x]` Verdict table: annotate the two spec/diagnosis-only verdicts so
  decision mode's reduced verdict set is consistent there too.

---

## Phase B — Existing template edits

### B1. `[x]` `templates/skills/espalier.md` (pure-copy) — 3 surgical edits
1. **Router hint** (near the fix-lane demotion paragraph in State File
   Format): an epic-smelling `feat:` — multiple features, explicit
   multi-session scope, or a requirement whose Stage 1 grill would blow the
   `full` tier — gets one line suggesting `/espalier-map` before proceeding.
   Mirror of the existing small-`fix:` demotion text.
2. **FILED adoption**: Session Resumption step 5's parenthetical gains
   "or slices filed by a cleared `/espalier-map` handoff"; adopted skeletons
   inherit `charted_from` / `tickets` frontmatter (exactly like `caused_by` /
   `filed_from_partial_fix` today).
3. **Completion**: when the closing change's `requirements.md` carries
   `charted_from:` — after Stage 10 COMPLETE, check the map's Spawned-Changes
   rows; if every spawned change is COMPLETE, OFFER (AskUserQuestion, never
   auto) flipping the map `status: CLEARED → BUILT` + updating its table row.

### B2. `[x]` `templates/pipeline.md` — 1 addition
Short "Lanes" note before Stages: `/espalier-map` sits ABOVE this pipeline —
multi-session planning that hands off FILED skeletons into Stage 1; pointer
to the skill. (No stage renumbering, no gate changes.)

### B3. `[x]` `skills/espalier-init/SKILL.md` — greenfield path
1. Description: add greenfield/boilerplate sentence.
2. New "Greenfield Path (Decide, Then Bind)" section after Phase 0:
   - Detection: no dependency manifest AND < 5 source files, or user says
     greenfield → AskUserQuestion: chart-first (recommended) / minimal
     espalier anyway / abort.
   - **Pass 1:** Phase 0 questions as normal → SKIP Phase 1 scouts + Phase 2
     writes → bootstrap with `--greenfield --lang=unsupported` (+ the Phase 0
     answers) → print next step: `/espalier-map greenfield: <idea>`.
   - **Pass 2** (re-run after map CLEARED): detect `espalier/.greenfield` +
     a CLEARED greenfield map → synthesize DISCOVERY from the map's ticket
     Resolutions, MERGED with normal Phase 1 scouts over whatever the
     scaffold task produced (decisions win conflicts, scouts fill gaps) →
     standard Phase 2 Write batch, but every rule sourced from a decision
     cites `decided_in: maps/{slug}/tickets/NNN` instead of `file:line` →
     write the real `pre-push-gate.sh` + lang-specific
     `check-layer-boundaries.sh` (overwriting Pass 1 placeholders) → remove
     `espalier/.greenfield` → `bootstrap --validate-only`.
3. Boilerplate note (one paragraph): a boilerplate repo has code — run init
   NORMALLY (scouts discover its conventions), THEN `/espalier-map` for
   product fog; init-first makes grill Step 1.5 live for the map.
4. Output-structure tree + skill-count prose: add `espalier-map`,
   `espalier/maps/`.

---

## Phase C — `scripts/bootstrap-espalier.sh`

All numbered against current v0.17 line layout:

1. Header comment: add espalier-map to the pure-copy list; validation counts
   line becomes `50 claude-only, 55 with codex, 60 with copilot`; document
   `--greenfield`.
2. Arg parse: `--greenfield` flag (`GREENFIELD=no` default).
3. Stage 2 mkdirs: `espalier/skills/espalier-map`, `espalier/maps`.
4. Stage 3: `cp templates/skills/espalier-map.md → espalier/skills/espalier-map/SKILL.md`.
5. Stage 4: `cp hook-templates/map-guard.sh → espalier/hooks/map-guard.sh`
   (chmod glob already covers it). `--greenfield` extra: write placeholder
   `pre-push-gate.sh` (write-if-absent; echoes "greenfield: gate pending init
   Pass 2", exits 0) + `touch espalier/.greenfield`.
6. `ESPALIER_SKILL_NAMES` += `espalier-map` (drives Claude/Codex/Copilot
   symlinks + WIRED counts; codex/copilot no-claude fallback counts stay
   derived from the loop).
7. Stage 8 `ESPALIER_HOOKS` PreToolUse: second entry `{matcher: "Write|Edit",
   command: bash "$CLAUDE_PROJECT_DIR/espalier/hooks/map-guard.sh",
   timeout: 5}` — the merge algorithm is already additive by
   (matcher, command), so existing installs re-running bootstrap gain it.
8. Stage 8b codex: append a SECOND marker block `ESPALIER MAP GUARD v1`
   (own grep-guard, so v0.17 installs whose `ESPALIER HOOKS v1` block exists
   still receive it): `[[hooks.PreToolUse]] matcher =
   "^(apply_patch|Edit|Write)$"` → map-guard.sh.
9. Stage 8e copilot: fresh-write template gains a second `preToolUse` entry
   (matcher `edit|write|create|apply_patch|str_replace_editor` → adapter
   `map-guard.sh`). Existing installs: file is write-if-absent — the
   MIGRATION inserts the entry via python json edit (C-item in migration
   script below).
10. Stage 9: `_append_config_key max-open-tickets 9` in BOTH branches
    (existing-config append + fresh heredoc gets a commented key line).
11. Stage 7/7b/7c instruction heredocs: add the `/espalier-map` line
    ("**For multi-session planning** (epics, greenfield) …"). Grep-guard is
    the existing `## Espalier` — new installs only; migration handles
    existing installs.
12. Stage 11 validation:
    - `TOTAL_CHECKS`: 48→50 base, 53→55 codex, 58→60 copilot.
    - Checks 2 / 47 / 52 (skills-load `ls -d` lists): append the
      espalier-map path.
    - New check 59 `map-skill` (platform-branched like 13/14):
      claude → `test -f .claude/skills/espalier-map/SKILL.md` else
      `test -f espalier/skills/espalier-map/SKILL.md`.
    - New check 60 `map-guard`: `test -x espalier/hooks/map-guard.sh` +
      (claude) `grep -q map-guard .claude/settings.json`.
    - Greenfield skip set: when `espalier/.greenfield` exists, checks 38–45
      render `skip_check … "pending greenfield Pass 2"` (counts stable).
    - Emit-order `cat` globs: extend `5[0-8]` → `5[0-9]` + `60`.

## Phase D — Migration

### D1. `[x]` `scripts/migrate-v0.17.0-to-v0.18.0.sh` (migration #25)
Pattern: copy of v0.16→v0.17 script shape (dry-run / --yes / --plugin-dir,
marker-based idempotency, backup-on-diff `.pre-v0.18.bak`, verification).
- Plugin staleness guard: template dir must contain
  `templates/skills/espalier-map.md`.
- Idempotency markers (any missing ⇒ run): espalier-map SKILL present;
  `map-guard.sh` present+executable; grill has `mode=decision`; espalier
  SKILL mentions `charted_from`; config has `max-open-tickets`; settings.json
  references map-guard (claude installs); codex config has `ESPALIER MAP
  GUARD` (codex installs); copilot gates reference map-guard (copilot
  installs).
- Actions: mkdirs; cp skill + hook (+chmod); per-platform symlinks read from
  `espalier/.platforms` (claude → `.claude/skills/`, codex →
  `.agents/skills/`, copilot → `.github/skills/`); pure-copy refresh
  (backup-on-diff) of `espalier-grill`, `espalier` SKILL files +
  `pipeline.md`; settings.json python merge (same additive algorithm — one
  new PreToolUse entry); codex marker-block append; copilot gates python
  json insert-if-absent; `max-open-tickets` append-if-missing; grep-guarded
  one-line `/espalier-map` mention appended to the `## Espalier` sections of
  CLAUDE.md / AGENTS.md / copilot-instructions where those sections exist.
- Verification checks mirror the markers.

### D2. `[x]` `skills/espalier-migrate/SKILL.md`
- Description clause: `…, and the v0.17.0→v0.18.0 map-lane release
  (/espalier-map multi-session planning + map-guard hook + greenfield
  decide-then-bind init)`.
- "Up to TWENTY-FOUR" → TWENTY-FIVE; list entry 25 (pure-copy + wiring,
  mechanical, script path).
- Chain sentences: every `… then v0.17.0` ending gains `then v0.18.0`;
  `a v0.16.0 install needs only v0.17.0` → `needs v0.17.0 then v0.18.0`;
  new final clause `a v0.17.0 install needs only v0.18.0`.
- Detection block: `NEEDS_V0180_PATCH` markers (keep in sync with D1's
  idempotency list — same rule the v0.17 block states); plugin staleness
  check now keys on `migrate-v0.17.0-to-v0.18.0.sh`; dry-run + apply
  invocation lines.

## Phase E — Tests (both suites must end green)

### E1. `[x]` `scripts/test-bootstrap.sh` (currently 177)
Add assertions: espalier-map SKILL copied + symlinked (each platform set the
suite already exercises); map-guard.sh copied + executable;
settings.json contains map-guard entry; codex config contains `ESPALIER MAP
GUARD v1`; fresh copilot gates contain map-guard; `max-open-tickets: 9` in
fresh config + appended on existing-config path; `--greenfield` run:
placeholder gate present, `.greenfield` marker present, validation passes
with 38–45 skipped, checks 59/60 pass; validation totals 50/55/60 asserted.

### E2. `[x]` `scripts/test-hooks.sh` (currently 127)
Port the 8 smoke cases as suite assertions (no-marker, block, maps-allow,
allow-window, traversal-reject, stale-expiry, apply_patch parse,
outside-repo) + adapter path: camelCase payload through
`copilot-hook-adapter.sh map-guard.sh` blocks the same.

### E3. `[x]` End-to-end sanity in scratch project
Full bootstrap (all three platforms) on a scratch repo → 60/60; re-run →
validate-only stays green; migration script against a simulated v0.17
install → verification green + idempotent second run exits "nothing to do".

## Phase F — Release docs + stamps

- `[x]` `CHANGELOG.md` — 0.18.0 entry (map lane, guard, grill decision mode,
  greenfield, boilerplate docs, migration #25, new validation totals, test
  suite totals).
- `[x]` `docs/migrating-v0.17-to-v0.18.md` — user-facing migration doc
  (v0.17 doc's shape: what it does / day-to-day / compatibility).
- `[x]` `README.md` — "Greenfield & boilerplate" section + lane table row +
  skill count updates; wayfinder attribution line.
- `[x]` `.claude-plugin/plugin.json` + `marketplace.json` — version 0.18.0.

## Commit plan (on `feat/map-lane`, user approves each)

1. `feat(map): /espalier-map lane skill + map-guard hook + grill decision mode` (A2–A4, B1, B2)
2. `feat(init,bootstrap): greenfield decide-then-bind path + v0.18 wiring + validation 50/55/60` (B3, C)
3. `feat(migrate): v0.17.0→v0.18.0 migration #25 + chain update` (D1, D2)
4. `test: bootstrap + hooks coverage for map lane, guard, greenfield` (E)
5. `release: v0.18.0 — map lane (multi-session planning) + greenfield/boilerplate` (F)

## Risks / mitigations

- **Stale marker bricks writes** → 12h mtime expiry in guard (tested).
- **Copilot gates file is user-owned after first write** → migration does a
  targeted json insert-if-absent, never a rewrite; unparseable file → warn +
  manual instruction, never clobber.
- **Validation numbering drift** → 59/60 appended after the platform blocks
  (same policy that kept 47–56 stable in v0.15–v0.17); greenfield skips
  reuse `skip_check` so totals never change shape.
- **Greenfield first changes diverge from decided rules** → expected
  convergence path; conventions promotion prompts handle it; called out in
  migration doc.
- **Scope discipline of the lane itself** → no-fog exit + session-count rule
  in both the skill and the `/espalier` router hint.
