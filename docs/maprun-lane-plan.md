# v0.19.0 — Run Lane (the map executes itself, survivably)

Design record for the `/espalier-maprun` map-execution lane. Field-derived: the
lane was built and battle-tested inside a production repo
(portal.quota.com.au, 14-ticket Keystone schema map) before being generalized
here; every mechanism below exists because a real failure demanded it.

## Why

v0.18.0's map lane ends with a handoff: a cleared map files `Status: FILED`
change skeletons and `/espalier` adopts them "one at a time". For a 14-slice
epic that means fourteen hand-driven sessions, serially, with a human
re-priming context each time. The planning ceiling moved above one session;
the execution ceiling did not.

`/espalier-maprun` closes that gap: one interactive **master** pass reaps
finished workers, merges what passed, relays parked questions, grills and
dispatches up to N headless pipelines in isolated worktrees, syncs external
trackers, then **stops**. Workers keep grinding after the master's session
ends. Over hours and days the map's dependency graph drains itself, with a
human in the loop only where a human is genuinely needed.

## The Shape (three moving parts)

| Part | What it is | Why |
|---|---|---|
| **Master** | interactive session, invoked per pass | The ONLY thing that can ask a question. Cheap, interruptible. |
| **Workers** | up to N headless sessions (`claude -p` / `codex exec`), one per git worktree | Real sessions with their own main loop — they spawn coder/reviewer/security subagents with no nesting problem, and they outlive the master. |
| **State** | `plan.json` (static) + `state.json` (mutable) beside the map | The master holds NOTHING in context. Every pass rebuilds from disk. |

The master never runs a pipeline and never spawns pipeline subagents — it
supervises processes. That split is what lets work continue after any
termination.

```
espalier/maps/{slug}/plan/
├── plan.json          tickets, dependency edges, branches, worker + sync config
├── state.json         mutable run state — the single source of truth
├── map-plan.md        human-readable plan (authored by the plan step)
├── questions/<key>.md parked questions awaiting a human
├── logs/<key>.log     worker output (+ .pid, .heartbeat)
└── verify-report.md   integration verification result
```

## Survival Model (the failure you are designed for is being killed)

Every long-horizon property is structural, never behavioral:

- **Master context = disposable.** Each pass runs in a FRESH session and
  rebuilds truth from `state.json` + worktrees. Anything remembered from a
  prior pass is duplicated on disk or stale — compaction summaries are where
  stale ticket beliefs survive, so the design assumes zero session
  continuity. Killing a master mid-pass loses at most that pass (every step
  is idempotent).
- **Liveness is measured by the supervisor, not the agent.** The dispatch
  wrapper writes a heartbeat around the worker process. `reap` cross-checks
  pid liveness against process identity (pid recycling after a reboot) and
  heartbeat age (`heartbeat_stale_seconds`) — a "live" pid with a stale
  heartbeat is flagged SUSPECT, never trusted.
- **Death is diagnosed, not assumed.** A vanished worker with no outcome
  sentinel is checked against its log for usage-limit signatures (→ `QUOTA`,
  resumable) and against git for whether the worktree matches its claimed
  stage. A state file claiming more than the worktree shows gets its stage
  cleared — the next worker rebuilds from git evidence (worker contract:
  "the worktree is the fact; the state file is the claim").
- **Resume is a first-class dispatch path.** Re-dispatch reuses the existing
  worktree and branch; espalier resumes from `pipeline-state.md`. Before
  spawning, dispatch checkpoints any uncommitted work, merges the
  integration branch in (relayed answers and merged sibling slices become
  visible — without this, a parked-question answer committed to the
  integration branch never reaches the resumed worker), and deletes the
  previous attempt's outcome sentinel (a stale `ESCALATED` sentinel would
  re-halt the run the moment a fresh worker starts).
- **Quota exhaustion is expected, not exceptional.** `QUOTA` frees the slot,
  survives as-is, and re-enters the frontier on a later pass.

## Context Hygiene (what pollutes long-horizon work, and the countermeasure)

| Pollution | Countermeasure |
|---|---|
| Master beliefs from earlier passes | Pass-per-fresh-session rule + "status output is the only memory" anti-pattern |
| Full review records entering master context on escalation | Master reads records through a subagent returning only verdict sentinels + decisive findings |
| Worker context growth across 6 stages | `worker_mode: staged` — the dispatch wrapper loops one headless session per stage group (1–2, 3–4, 5–6), each fresh session resuming from `pipeline-state.md`. Bounded context, finer crash/quota resume. `session` mode (one session per ticket) remains the default. |
| Workers reading master state, sibling logs, other tickets' questions | No `--add-dir` at all. The worker's question channel is a file INSIDE its own change folder (`.maprun-question.md`); `reap` collects it into `plan/questions/<key>.md`. A worker structurally cannot see `plan/`. |
| Workers reading sibling slices' folders | Prompt-level: the contract names exactly what a worker may read (its change folder, `espalier/rules/`, `espalier/wiki/`, the map's decision tickets). Sibling `changes/feat/*` folders are off-limits. |
| Host-level user config leaking into workers | Optional `worker_setting_sources` (e.g. `project,local`) passed as `--setting-sources` — strips user-level hooks/memory injections from headless workers. Unset = platform default. |

## One Pass (master algorithm)

0. `maprun.py <map> status` (init first if no state.json) — the output, not
   memory, is the truth.
1. **Reap** — classify every DISPATCHED worker (sentinel, question file,
   liveness, quota signature, git-state check). Collect in-worktree question
   files into `plan/questions/`.
2. **Escalations halt the run** — report (via subagent excerpts), sync, stop
   the pass. Reap already marked the downstream subtree BLOCKED.
3. **Relay parked questions** — `AskUserQuestion`, write answers into the
   slice's `requirements.md` in the integration worktree, commit, delete the
   question file, `mark <key> TODO`. A PARKED ticket with no question file
   means a prior pass crashed after relaying: just mark TODO.
4. **Merge PASSED tickets** (oldest first) via `maprun-merge.sh` — exit 2 =
   genuine conflict = escalate, halt.
5. **Grill, then dispatch** the frontier — `espalier-grill mode=spec` per
   un-grilled slice (the ONE moment a human shapes the work; workers run
   no-grill), commit answers + `grilled:` stamp to the integration branch,
   `maprun-dispatch.sh` each key.
6. **Completion** — all MERGED → `maprun-verify.sh` runs the discovered
   build/test commands on the assembled branch + plan-declared checks; pass →
   DONE/COMPLETE, fail → report and halt.
7. **Report and stop.** Never loop, never schedule a wakeup, never leave the
   session running. The human owns cadence; the workers own autonomy.

## Worker Contract (embedded in the dispatch prompt)

1. Stages 1–6 only; commit locally; never push (blocked at git config level —
   `pushurl` invalid scheme + `push.default nothing`; config, not instruction).
2. The change folder is the ticket: adopt `espalier/changes/feat/<slug>/`,
   read its `requirements.md` as THE requirements document, keep its
   `pipeline-state.md` current (Current Stage / Stage History / `- Status:`
   line) exactly as the normal `/espalier` runner does. Both files missing →
   the branch is mis-based → write `MISBASED`, stop (reaped as escalation).
3. No grill (`--no-grill` semantics; requirements grilled by map + master).
4. Cannot answer from requirements/map/rules → write the question to
   `.maprun-question.md` in the change folder, sentinel `PARKED`, stop. Never
   guess in place of asking.
5. Exactly one outcome sentinel, written last:
   `PASSED · ESCALATED (reason underneath) · PARKED · MISBASED`.
6. Resume discipline: verify the worktree contains what `pipeline-state.md`
   claims before resuming; correct the file down to the git evidence.

Workers run `ESPALIER_UNATTENDED=1` (the requirements gate auto-approves —
legitimate because the master already grilled with a human) plus the
plan-declared `worker_env` seeds (build-time env some stacks need).

## State Vocabulary

`TODO → DISPATCHED → {PASSED → MERGED → DONE | PARKED | QUOTA | ESCALATED}`,
plus `BLOCKED` (upstream escalated). Dispatchable = `TODO|QUOTA` ∧ deps all
`MERGED|DONE` ∧ slot free ∧ nothing `ESCALATED` anywhere. `PARKED`/`QUOTA`/
`PASSED`/`ESCALATED` free their slot. Any `ESCALATED` empties the frontier.

## Generalization Deltas (portal-specific → plan.json-declared)

The engine ships as hook templates with ZERO repo-specific content; everything
the portal version hardcoded moves into `plan.json`, seeded by the plan step
from DISCOVERY (the same build/lint/test commands the pre-push gate already
discovered):

| Portal hardcoded | plan.json key |
|---|---|
| `backend`/`frontend` workspaces + node_modules cloning | `workspaces: [{dir, deps: clone\|install\|none, install_cmd}]` |
| `backend/schemas/index.ts merge=union` | `union_merge: ["path", …]` |
| Keystone `SESSION_SECRET`/`DATABASE_URL`/`CI` env seeds | `worker_env: {K: V, …}` |
| `npm run build` / `npm run test:coverage` verify steps | `verify: {commands: [{name, dir, run}], expected_registrations: {file, pattern, min}}` |
| `claude -p` spawn line | `worker_platform: claude\|codex` (dispatch adapter; codex uses `codex exec`) |
| — (new) | `worker_mode: session\|staged` |
| — (new) | `worker_setting_sources` (optional `--setting-sources`) |
| ClickUp/Harvest IDs | unchanged shape — first-class OPTIONAL: absent config = silent no-op; credentials from `.local.env`, never printed, never committed |

## The Plan Step (`/espalier-maprun <map> plan`)

A cleared map does not carry execution config, so the run lane authors it
once, interactively:

1. Read the map's Spawned Changes + each FILED skeleton's frontmatter.
2. Propose the ticket list + dependency edges (from the map's decision
   dependencies; the human confirms/edits — edges are the one thing worth a
   human minute, a wrong edge serializes or collides work).
3. Ask: integration branch name, base branch, concurrency, worker platform/
   mode/model, optional ClickUp list + Harvest project mapping.
4. Seed `workspaces`/`verify`/`worker_env`/`union_merge` from DISCOVERY and
   the pre-push gate's discovered commands; show for confirmation.
5. Write `plan/plan.json` + human-readable `plan/map-plan.md`; `maprun.py
   init` seeds `state.json`.

## Safety Rails (structural)

- Push impossible from every worktree (ticket + integration), at git config
  level. The integration branch is never pushed — remote delivery is a
  deliberate human act after review.
- The user's working checkout is never touched; all merges/edits happen in
  the integration worktree.
- Declared `union_merge` paths absorb the guaranteed registry collision;
  anything else that conflicts is genuinely worth a human.
- Workers run permissive permission modes ONLY inside throwaway worktrees
  that cannot reach a remote.
- Dispatch refuses to run while an unanswered question file exists (exit 4)
  and escalates integration-sync conflicts (exit 3) instead of resolving.

## Wiring Deltas

- `templates/skills/espalier-maprun.md` (new, pure-copy) + Stage 3 cp + Stage 2
  mkdir (`espalier/skills/espalier-maprun`).
- `hook-templates/maprun.py`, `maprun-dispatch.sh`, `maprun-merge.sh`,
  `maprun-verify.sh`, `maprun-integration.sh` (new, non-substitution) +
  Stage 4 cp — **write-if-absent** for repos (like portal) already carrying a
  locally-adapted engine.
- `ESPALIER_SKILL_NAMES` += espalier-maprun → symlinks on all three platforms.
- `templates/pipeline.md` + `templates/skills/espalier-map.md`: the handoff
  section gains the batch alternative ("adopt one at a time via `/espalier`,
  or drive the whole map with `/espalier-maprun`").
- Platform instruction sections (CLAUDE.md / AGENTS.md /
  copilot-instructions) gain the `/espalier-maprun` line.
- Validation: +2 unconditional checks (61 maprun-skill wired, 62 maprun engine
  present + executable) → totals 52 claude / 57 codex / 62 copilot.
- `scripts/migrate-v0.18.0-to-v0.19.0.sh` (migration #26): mkdir + cp
  (write-if-absent for the engine files) + chmod + platform symlinks +
  pure-copy refresh of pipeline.md / espalier-map SKILL (backup-on-diff
  `<file>.pre-v0.19.bak`) + instruction-file lane lines.

Platform note: the run lane's SKILL wires everywhere, but dispatching workers
requires a local headless CLI — claude (`claude -p`) or codex (`codex exec`).
A copilot-only install gets the skill with a stated requirement to run the
master from Claude Code or Codex.

## Eval (`eval/maprun/` — grill-harness pattern)

Fixtures plant run states; the runner drives ONE master pass in eval mode (no
processes — worker liveness/logs STATED in the fixture); an LLM judge scores
against `rubric.md`; 0.80 catch-rate gate plus per-fixture bars. Planted
failure modes: dispatching past an escalation, answering a parked question
instead of relaying, trusting `state.json` over the worktree, resuming a
QUOTA ticket as an error, looping/scheduling instead of stopping, merging on
a conflict, skipping the grill before dispatch.

## Deferred (explicitly)

- `espalier-stats.sh` run-lane section (per-map worker attempt/duration
  distributions) — follow-up.
- A `codex exec` end-to-end worker sim in the hook suite (the adapter ships;
  the sim needs a codex binary on CI).
- Auto-generation of plan.json dependency edges from map ticket `blocked_by`
  graphs (v1 proposes, human confirms).
