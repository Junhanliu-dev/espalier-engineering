---
name: espalier-maprun
description: Master runner for a CLEARED Espalier map — drives its FILED change slices to completion over hours and days. One interactive pass reaps finished workers, merges what passed (opening one reviewable slice PR per ticket when the plan opts in), relays parked questions to the human, grills and dispatches up to N headless espalier pipelines in isolated worktrees, syncs optional trackers, then stops. Holds no state in context — everything is reconstructed from disk, so a master killed by quota exhaustion, network loss or a closed laptop resumes exactly where it stopped. Slash: /espalier-maprun
---

# Espalier Run

`/espalier-map` produces a cleared map and FILED change skeletons. `/espalier`
runs **one** of them. This lane runs **all of them**, over days, with a human in
the loop only where a human is genuinely needed.

## When to Use

- `/espalier-maprun <map-slug> plan` — author `plan/plan.json` for a CLEARED map
- `/espalier-maprun <map-slug>` — advance a map's run by one pass
- `/espalier-maprun` — advance the single map that has a `plan/` folder
- `/espalier-maprun <map-slug> status` — report without changing anything
- `/espalier-maprun <map-slug> pause [reason]` / `resume` — durable dispatch
  pause (`maprun.py <map> pause`): in-flight workers finish, merge and sync,
  but nothing new dispatches until resume. Survives every session boundary —
  the instruction lives in `state.json`, not in anyone's context.

Do NOT use for: a single change (`/espalier`), a map that is not yet CLEARED
(`/espalier-map`), or a bug (`/espalier-fix`).

The headless worker modes require a local headless CLI: Claude Code
(`claude -p`) or Codex (`codex exec`). Run the master from an interactive
Claude Code or Codex session. `worker_mode: inline` needs no headless CLI at
all — the master session does the work itself — which also makes it the one
mode available on a Copilot-only install.

## The Shape

Three moving parts, and the split between them is the whole design.

| Part | What it is | Why |
|---|---|---|
| **Master** | this session — interactive, invoked by a human | It is the ONLY thing that can ask a question. Every human decision routes here. |
| **Workers** | up to N headless sessions, one per git worktree — or, in `inline` mode, the master itself | Each headless worker is a real session with its own main loop, so it spawns its own coder/reviewer/security agents with no nesting problem. It outlives the master. |
| **State** | `plan.json` (static) + `state.json` (mutable), beside the map | The master holds **nothing** in context. Every pass rebuilds from disk. This is what makes the run survivable. |

**Two execution modes**, chosen once at plan time (`worker_mode`):

- **Headless** (`session` / `staged`) — the master supervises detached worker
  processes and never runs a pipeline itself. Workers keep grinding after the
  master's session ends; the operator watches them on the `watch` dashboard.
  Best for big maps, parallel slices, unattended runs.
- **Inline** (`inline`) — there are no detached workers: the master runs each
  ticket's pipeline **in this session**, spawning the stage agents
  (coder/reviewer/security) directly, exactly as a normal `/espalier` session
  would — but inside the ticket's prepared worktree. One ticket at a time,
  everything visible in the conversation, questions go straight to the human.
  Best for small maps, attended runs, or installs without a headless CLI.
  Nothing outlives the session, but the state machine makes that cheap: a
  killed session's half-done ticket is retried from `pipeline-state.md`.

In headless modes **the master never runs a pipeline itself and never spawns
pipeline subagents** — it supervises processes; that distinction is what lets
a worker keep grinding after the master's session ends. In `inline` mode that
rule inverts by design: the master IS the worker, one ticket at a time.

```
<map>/plan/
├── plan.json          tickets, dependency edges, branches, worker + sync config
├── state.json         mutable run state — the single source of truth
├── map-plan.md        the human-readable plan
├── questions/<key>.md parked questions awaiting a human
├── logs/<key>.log     worker output  (+ .pid, .heartbeat, generated helpers)
└── verify-report.md   integration verification result
```

## The Plan Step (once per map)

A cleared map carries decisions, not execution config. `plan` authors it:

1. Read the map's Spawned Changes table and each FILED skeleton's
   frontmatter (`charted_from:`, `tickets:`).
2. Propose the ticket list and dependency edges (derive candidates from the
   slices' ordering and their source decision tickets' `blocked_by` graphs).
   Put the edges to the human with `AskUserQuestion` — a wrong edge
   serializes or collides work, and it is the one thing worth a human minute.
3. Ask for: integration branch name, base branch, concurrency, worker
   platform (`claude`/`codex`), worker mode, model, and — optionally —
   ClickUp list/task ids and a Harvest project mapping.
   The **worker mode** question is the execution-mode choice — put the
   trade-off to the human plainly: `session`/`staged` = headless workers that
   outlive the session, watched on the dashboard, up to N in parallel;
   `inline` = the master works each ticket itself in-session (stage agents
   spawned directly, questions asked live, no headless CLI needed), one
   ticket at a time, with a fresh session recommended every 1–2 tickets.
   Ask the **PR opt-in** explicitly: with a `pr` config, the master pushes
   ticket branches and the integration branch and opens one reviewable slice
   PR per ticket (plus a final assembly PR) — name that rail change when you
   ask, because without `pr` nothing ever reaches the remote. If opted in,
   run `bash espalier/hooks/maprun-pr.sh <map-dir> setup` after `init` — it
   probes push capability and warns about `pull_request` workflows whose
   `branches:` filter would silently skip CI on slice PRs (that filter fix
   must land on the base branch before the first slice PR opens).
4. Seed `workspaces`, `verify`, `worker_env`, and `union_merge` from what
   init discovered (the same build/lint/test commands the pre-push gate
   runs); show the result for confirmation.
5. Write `plan/plan.json` + a human-readable `plan/map-plan.md`, and a
   `plan/.gitignore` containing `logs/`, `*.tmp`, `state.json`, and
   `questions/` — run state carries machine-local pids and absolute worktree
   paths, so it must never travel through git (plan.json and map-plan.md ARE
   tracked). Then:

```bash
python3 espalier/hooks/maprun.py <map-dir> init
```

## One Pass

Execute in order. Every step is idempotent — a pass interrupted anywhere is
safely repeated.

**Run each pass in a FRESH session** (`/clear` or a new terminal). Everything a
pass needs is on disk; anything remembered from a previous pass is either
duplicated there or stale — and stale beliefs about ticket states are how a
master relays a question twice or reports the wrong status. Continuing in an
old session is tolerable only if you treat prior knowledge as void and re-run
`status` before acting on anything.

### 0. Locate and load

Resolve the map directory, then:

```bash
python3 espalier/hooks/maprun.py <map-dir> status
```

Read it. That output — not your memory of a previous pass — is the truth.

### 1. Reap

```bash
python3 espalier/hooks/maprun.py <map-dir> reap
```

Classifies every `DISPATCHED` ticket by process liveness (pid + process
identity + heartbeat age), its outcome sentinel, its `pipeline-state.md`
stage, and a **git-state check** that confirms the worktree actually contains
the work its state file claims. A worker that died between writing state and
doing the work is caught here rather than resumed into corruption. Reap also
collects any in-worktree question file into `plan/questions/`.

Outcomes: `PASSED`, `ESCALATED`, `PARKED`, `QUOTA` (usage limit — resumable),
or back to `TODO` (died; retry). A worker that reports `MISBASED` (its branch
lacks the FILED skeleton) or `ABORTED` is classified `ESCALATED` — both mean
the run's ground truth is wrong and a human must look. A live pid with a
stale heartbeat is flagged `SUSPECT`, not trusted.

To see what a still-running worker is actually doing:

```bash
python3 espalier/hooks/maprun.py <map-dir> tail        # all DISPATCHED
python3 espalier/hooks/maprun.py <map-dir> tail <key>  # one
```

It parses the worker's streaming-JSON log into tool counts, recent tool
calls, recent assistant text, and the final result event. A worker with no
new events in ten minutes is worth investigating regardless of what its
heartbeat says. (Codex workers log plain text — read the log file directly.)

### 2. Escalations halt the run

If any ticket is `ESCALATED`, **stop the pass here**. Do not merge, do not
dispatch. Report each one with the reason and the relevant excerpt from its
worktree's `review-record.md` / `security-record.md`, sync trackers, and hand
back to the human.

Read those records through a subagent — one reader per escalated ticket,
returning only the decisive lines (the verdict sentinel and the P0/P1
findings or Escalation Reason block). Full records never enter the master's
context.

`reap` has already marked the whole downstream subtree `BLOCKED`, so the
report shows the true blast radius rather than discovering it one ticket at
a time.

### 3. Relay parked questions

For each `PARKED` ticket, read `plan/questions/<key>.md`. Put the questions to
the human with `AskUserQuestion` — you are the only part of this system that
can. Then:

1. Write the answers into that slice's `requirements.md` **in the integration
   worktree** (`bash espalier/hooks/maprun-integration.sh <map-dir>` prints
   its path), under a `## Answers relayed by the runner` heading, with the
   date.
2. Commit them to the integration branch (with a `pr` config, follow with
   `bash espalier/hooks/maprun-pr.sh <map-dir> sync` so the remote shows
   what workers will inherit).
3. Delete `plan/questions/<key>.md`.
4. `maprun.py <map-dir> mark <key> TODO` — it re-enters the frontier and
   resumes from its recorded stage on the next dispatch.

A parked question frees its slot and blocks only that ticket. It is **not** an
escalation and must not halt the run.

A `PARKED` ticket whose `plan/questions/<key>.md` is MISSING means a previous
pass crashed between relaying and re-marking: the answers already live in the
integration worktree's `requirements.md`. Just `mark <key> TODO` and move on.

### 4. Merge what passed

For each `PASSED` ticket, oldest first — **with a `pr` config, open the slice
PR before the merge** (order matters: once the merge is pushed, the branch is
contained in its base and the forge can no longer open a PR for it):

```bash
bash espalier/hooks/maprun-pr.sh <map-dir> open <key>    # pr config only
bash espalier/hooks/maprun-merge.sh <map-dir> <key>
```

- `open` exit 0 → the slice PR number/url are recorded in state. Exit 5 →
  the forge is unavailable (no gh, no auth, no push permission): **warn and
  continue** — the local merge never blocks on the forge; note in the report
  that this slice has no PR. Exit 1 → a rejected push; someone else wrote to
  a maprun branch on the remote — report it and do not force.
- merge exit 0 → `mark <key> MERGED`, then (pr config)
  `bash espalier/hooks/maprun-pr.sh <map-dir> sync` — the pushed integration
  branch now contains the slice branch, so the forge closes the slice PR as
  **merged** on its own, preserving its diff and CI verdict for review.
  Then `clickup <key>`, then log Harvest (below).
- merge exit 1 → an operational failure (not a conflict — the script prints
  what git said). Fix the environment and repeat the step; do not mark
  anything.
- merge exit 2 → a real conflict. `mark <key> ESCALATED --error "merge
  conflict: …"` and halt per step 2. Do not attempt to resolve it yourself:
  the declared `union_merge` rules already absorb the expected registry
  collisions, so anything reaching here is a genuine disagreement that needs
  a human. (An already-opened slice PR stays open — it is a good surface for
  the human to resolve on.)

Slice PRs are **advisory review, after the fact**: the run does not wait for
approvals or checks. Review comments become follow-up fix tickets (append to
the map, or `/espalier-fix`); nothing dispatches differently because a slice
PR has feedback.

### 5. Grill, then dispatch

```bash
python3 espalier/hooks/maprun.py <map-dir> frontier
```

For each key returned — **grill before you dispatch**:

1. Read that slice's `requirements.md`. If its frontmatter already carries
   `grilled: <timestamp>`, skip to dispatch.
2. Otherwise invoke `espalier-grill` with `mode=spec` against it, and put
   every question it raises to the human with `AskUserQuestion`. This is the
   ONE moment a human can shape the work — the worker runs `--no-grill` and
   cannot ask anything.
3. Write the answers into `requirements.md` in the integration worktree, add
   `grilled: <ISO timestamp>` to its frontmatter, and commit (with a `pr`
   config, `maprun-pr.sh <map-dir> sync` after the commit).
4. Dispatch:

```bash
bash espalier/hooks/maprun-dispatch.sh <map-dir> <key>
```

   Dispatch exit codes: **3** = syncing the integration branch into the
   ticket's existing worktree conflicted — `mark <key> ESCALATED --error
   "integration sync conflict"` and halt per step 2. **4** = an unanswered
   question still exists (master-side or un-reaped in the worktree) — run
   steps 1+3 for it first.

5. `maprun.py <map-dir> clickup <key>` (no-op without ClickUp config).

The worker branches off the integration branch, so it inherits every merge
and every grilled requirement that landed before it.

**Inline mode (`worker_mode: inline`)** — dispatch prepares the worktree,
marks the ticket `DISPATCHED`, spawns nothing, and hands the ticket to YOU:

1. Work tickets **one at a time**, in frontier order. For the current ticket,
   run the espalier pipeline stages 1–6 yourself — spawning the stage agents
   exactly as the `/espalier` skill directs — **inside the ticket's worktree**
   (dispatch printed its path; every stage agent must be told to operate on
   that directory, never on your main checkout). The change folder
   `espalier/changes/<type>/<slug>/` is already there with its drafted
   `requirements.md` — adopt it, keep `pipeline-state.md` current, commit to
   the ticket branch. Stop after Stage 6; never Stage 7+.
2. Questions need no parking: you are interactive — `AskUserQuestion` the
   human directly, write the answer into the slice's `requirements.md` in the
   worktree, commit, continue.
3. On stages 1–6 clean: `mark <key> PASSED`, run step 4 (merge, and the PR
   flow if configured) for it immediately, then take the next frontier ticket.
   On escalation: `mark <key> ESCALATED --error "…"` and halt per step 2.
4. **Context discipline:** after 1–2 tickets, finish the pass (report, stop)
   and continue in a fresh session — inline mode spends master context on
   pipeline work, and the state machine makes fresh sessions free. A session
   killed mid-ticket leaves `DISPATCHED` with no live process; the next
   session's reap retries it from `pipeline-state.md`, exactly like a dead
   headless worker.

Everything else — grill-before-dispatch, merge order, PR flow, verify,
halt-on-escalation — is identical in both modes.

### 6. Completion

When every ticket is `MERGED`:

```bash
bash espalier/hooks/maprun-verify.sh <map-dir>
```

Each ticket already built, tested and passed a review panel **alone**. This is
the only check that the *union* of them is coherent — it runs the plan's
declared build/test commands plus drift/forbidden-pattern/registration checks
on the assembled branch. On pass: mark every ticket `DONE`, set the run
`COMPLETE`, sync trackers — and with a `pr` config, open the assembly PR:

```bash
bash espalier/hooks/maprun-pr.sh <map-dir> final
```

Its body links every slice PR — the diff is big, but every line of it was
already reviewed on its slice PR; this one is the CI + sign-off gate, and
**merging it stays a human act**. Report, then offer (never auto-flip) the
map's `CLEARED → BUILT` transition. On fail: report the failures from
`verify-report.md` and halt — the run does not report COMPLETE on parts that
each work separately.

### 7. Report and stop

Tell the human, briefly: what moved, what is running now and roughly how long
it has been, what is waiting on them, and what the next pass will do. Then
**stop**. Do not loop, do not poll, do not schedule a wakeup. The workers
keep running without you; the human invokes the next pass.

## The Worker Contract

Every worker is spawned with these rules and must honour all of them. They are
embedded in the dispatch prompt; this is the reference.

1. **Stages 1–6 only.** Stop after Stage 6 passes. Never Stage 7 (push), 8, 9
   or 10. Commit locally to the ticket branch.
2. **The change folder is the ticket.** Adopt
   `espalier/changes/feat/<slug>/` — read its `requirements.md` as THE
   requirements document and keep its `pipeline-state.md` current
   (Current Stage, Stage History, the `- Status:` line) through every stage,
   exactly as the normal `/espalier` runner does. Missing skeleton →
   `MISBASED`, stop.
3. **Never push.** Blocked at git config level in the worktree — `pushurl` is
   set to an invalid scheme and `push.default` to `nothing`. Config, not
   instruction: an autonomous agent cannot talk its way past it.
4. **No grill.** Requirements were grilled by the map and again by the master.
5. **Read scope.** Its change folder, `espalier/rules/`, `espalier/wiki/`,
   the map's decision tickets, and the source tree — never sibling
   `espalier/changes/` folders, and it has no access to the master's `plan/`
   directory at all.
6. **Exactly one outcome sentinel**, written last, to
   `espalier/changes/feat/<slug>/.maprun-outcome`:
   `PASSED` · `ESCALATED` (reason underneath) · `PARKED` (question written to
   `.maprun-question.md` beside it first — reap carries it to the master) ·
   `MISBASED` (skeleton missing — reaped as an escalation).
7. **Never guess in place of asking.** Park instead.
8. **Verify before resuming.** `pipeline-state.md` may claim more than the
   worktree contains (a predecessor died mid-write). Correct it down to what
   the git evidence supports before continuing — the worktree is the fact.

Workers run with `ESPALIER_UNATTENDED=1` so the espalier requirements gate
auto-approves — legitimate here precisely because the master already grilled
those requirements with a human in step 5 — plus any `worker_env` seeds the
plan declares (build-time placeholders, never real secrets).

**Worker modes** (`worker_mode` in plan.json): `session` (default) runs the
whole ticket in one headless session. `staged` runs one fresh session per
stage group (1–2, 3–4, 5–6), each resuming from `pipeline-state.md` — bounded
context for long tickets, finer crash/quota resume; the generated wrapper
owns the loop, so the worker still outlives the master. It escalates after
two legs without stage progress, and a leg that dies on a usage-limit
signature makes the wrapper exit sentinel-less so reap classifies the ticket
as resumable `QUOTA`, never an escalation. `inline` spawns no worker at all —
the master works the ticket itself per step 5-inline; the contract above
still binds it (stages 1–6 only, the change folder is the ticket, never push,
resume discipline), except the question rules: an inline master asks the
human directly instead of parking, and marks state directly instead of
writing sentinels.

## State Vocabulary

| State | Meaning | Frees a slot |
|---|---|---|
| `TODO` | never started, or died and will retry | — |
| `DISPATCHED` | a worker is running | no |
| `PARKED` | waiting on a human answer | yes |
| `PASSED` | stages 1–6 clean, not yet merged | yes |
| `MERGED` | on the integration branch | yes |
| `QUOTA` | usage limit hit; resumable as-is | yes |
| `ESCALATED` | gave up — **halts the run** | yes |
| `BLOCKED` | an upstream ticket escalated | — |
| `DONE` | integration-verified at run end | — |

A ticket is dispatchable when it is `TODO` or `QUOTA`, all its dependencies
are `MERGED`/`DONE`, a slot is free, and **nothing anywhere is `ESCALATED`**.

## Watching the Run (for humans, not the master)

The operator never has to ask the master what is happening. Two read-only
commands work in a second terminal at any time — including while a master
pass is mid-flight (they never write state or move question files):

```bash
python3 espalier/hooks/maprun.py <map-dir> watch          # live dashboard, 10s refresh
python3 espalier/hooks/maprun.py <map-dir> watch 5        # faster refresh
python3 espalier/hooks/maprun.py <map-dir> feed <key> --follow   # one worker's
                                  # thinking / text / tool calls, streamed live
```

`watch` shows the run header (merged count, per-state totals, pause/halt) and
per ticket: name, state, current stage with its pipeline.md label (read live
from the worktree's pipeline-state.md), elapsed runtime, commits ahead of the
integration branch + dirty file count, whether the worker process is actually
alive, heartbeat age, a waiting outcome sentinel, the first line of any
parked question, unmet dependencies for TODO tickets, the worker's last
narration line ("say:"), and the last visible thing it did ("now:"). `feed` renders the worker's stream-json log as
greppable `THINK` / `SAY` / `TOOL` / `RES` lines (`feed <key> | grep TOOL`
gives the tool-call history). Codex logs are plain text and pass through raw.

These are observation surfaces only. Do not act on what you see there —
classification stays with `reap`, decisions stay with the master pass.

## Recovery

The failure you are designed to survive is being killed without warning.

- **Nothing lives in context.** Every pass rebuilds from `state.json`. A master
  that dies mid-pass loses at most that pass.
- **Liveness is measured by the supervisor, not the agent.** The dispatch
  script runs a heartbeat loop around the worker process, so a heartbeat means
  the process is alive — not that the agent chose to say so.
- **A stale heartbeat with a "live" pid is a suspect, not a worker.** After a
  reboot the pid may belong to someone else; `reap` cross-checks process
  identity and flags `SUSPECT`. Inspect with `tail <key>`; if the worker is
  truly gone, `mark <key> TODO`.
- **Death is diagnosed, not assumed.** A vanished process with no sentinel is
  checked against its log for usage-limit signatures (→ `QUOTA`, resumable)
  and against git for whether the worktree matches its claimed stage (→ retry,
  with the false stage claim cleared).
- **Worktrees are reused on resume.** Re-dispatching a `QUOTA` or `TODO`
  ticket picks up its existing worktree and branch; espalier resumes from the
  stage in its own `pipeline-state.md`. Dispatch first checkpoints any
  uncommitted work and merges the integration branch in, so relayed answers
  and merged sibling slices are visible to the resumed worker.
- **Quota exhaustion is expected, not exceptional.** Report which tickets are
  `QUOTA` and that the next pass will resume them; do not treat it as an
  error.

## ClickUp and Harvest (optional)

Configured under `clickup` and `harvest` in `plan.json`; absent config = the
sync commands are silent no-ops. Credentials read from `.local.env` at the
repo root and **never printed**.

- **ClickUp** — on every transition, `maprun.py clickup <key>` moves the
  task's status via `status_map` and leaves a comment. The board becomes the
  live view for anyone not reading state files.
- **ClickUp live stage mirror** — once per pass (any point after reap), run
  `maprun.py <map-dir> clickup-stages`: for each DISPATCHED ticket whose LIVE
  pipeline stage (read from its worktree) advanced since the last post, it
  maintains a single **"Pipeline: stage N — <label>" subtask** under the
  ticket's task (created on first stage, renamed on each advance; finalized
  by `clickup` at rest states — "merged ✓", "parked — waiting on a human
  answer", "escalated at stage N") and posts a `maprun: stage N` comment.
  Deduped via a sidecar in `plan/logs/`, never touches state.json — the
  operator may also run it from a cron or a second terminal for board
  updates between passes. Disable pieces with `"stage_subtask": false` /
  `"stage_comments": false` in the clickup config.
- **Harvest** — one time entry per ticket, on completion. The master is an
  interactive session, so post through your Harvest MCP rather than a stored
  credential:

  ```bash
  python3 espalier/hooks/maprun.py <map-dir> harvest-plan <key>   # → JSON payload
  ```
  then call the Harvest MCP's log-time tool with exactly those fields, then:
  ```bash
  python3 espalier/hooks/maprun.py <map-dir> harvest-record <key> <entry-id>
  ```

  `harvest-plan` returns `{"skip": …}` when unconfigured, already logged, or
  timing is missing — honour it and post nothing. Set `"mode": "record_only"`
  in the harvest config when the operator runs their own timer against the
  project: hours are recorded in `state.json` and never posted (no
  double-count). (`maprun.py harvest <key>`
  posts directly instead, but only if `HARVEST_ACCESS_TOKEN` /
  `HARVEST_ACCOUNT_ID` exist in `.local.env`.)

Both are best-effort. A missing credential or a network failure logs a line
and the pass continues — external sync must never block the build.

## Safety Rails

These are structural, not advisory:

- **Push is impossible from any worktree** (git config, worktree-scoped, both
  the ticket worktrees and the integration worktree — never the shared
  config, which would block the operator's own checkout).
- **Your working checkout is never touched.** All merges and edits happen in
  the integration worktree.
- **Without a `pr` config, nothing is ever pushed.** Getting work to the
  remote is a deliberate human act, after review — exactly v0.19 behavior.
- **With a `pr` config** (an explicit plan-time human opt-in), the MASTER —
  never a worker — pushes ticket branches and the integration branch and
  opens slice PRs. Merging the final assembly PR into the base branch
  remains a human act. Pushes are fast-forward only; a rejected push is
  reported, never forced.
- **Declared `union_merge` paths** absorb the registry collisions concurrent
  tickets are guaranteed to cause; anything else that conflicts is genuinely
  worth a human's time.
- Workers run with a permissive permission mode (`permission_mode` in
  `plan.json`) because a headless session that prompts is a hung session. The
  blast radius is one throwaway worktree that cannot reach a remote.
- Optional `worker_setting_sources` (e.g. `project,local`) strips user-level
  settings/hooks/memory injections from workers — keeps host-machine config
  from polluting long-horizon runs.

## plan.json Reference

```jsonc
{
  "map": "<map-slug>",
  "integration_branch": "feat/…",     // assembled here; never pushed
  "base_branch": "main",              // integration branch is cut from this
  "concurrency": 3,                   // max workers in flight
  "worktree_root": "../.espalier-worktrees",   // relative to repo root, or absolute
  "worker_platform": "claude",        // claude | codex (headless modes only)
  "worker_mode": "session",           // session | staged (headless; per-stage-group
                                      //   sessions) | inline (master works tickets
                                      //   in-session, one at a time — no headless CLI)
  "worker_setting_sources": "",       // optional --setting-sources for claude workers
  "permission_mode": "bypassPermissions",
  "model": "opus",
  "output_format": "stream-json",     // text buffers until exit — keep this
  "max_budget_usd": 0,                // optional per-worker cost cap; 0/omit = off
  "auto_dashboard": true,             // dispatch pops a read-only watch TUI window
                                      // (deduped per map; skipped headless/CI/
                                      //  MAPRUN_NO_DASHBOARD=1; false = never)
  "heartbeat_stale_seconds": 1800,
  "workspaces": [                     // dependency setup per workspace dir
    { "dir": "backend", "deps": "clone",   // clone | install | none
      "deps_dir": "node_modules",
      "install_cmd": "npm install --no-audit --no-fund" }
  ],
  "union_merge": ["backend/schemas/index.ts"],   // .gitattributes merge=union
  "worker_env": { "CI": "1" },        // build-time seeds; placeholders only
  "verify": {                         // integration verification (see maprun-verify.sh)
    "commands": [{ "name": "backend build", "dir": "backend", "run": "npm run build" }],
    "clean_after_build": [],
    "forbidden_patterns": [],
    "expected_registrations": { "file": "", "pattern": "", "min": 0 }
  },
  "pr": {                             // OPTIONAL — omit and nothing is pushed
    "remote": "origin",               // presence enables slice PRs (maprun-pr.sh)
    "draft": false,                   // open slice PRs as drafts
    "labels": []                      // labels applied to each slice PR
  },
  "clickup": {                        // OPTIONAL — omit for no sync
    "parent": "<task id>", "list": "<list id>",
    "status_map": { "TODO": "to do", "DISPATCHED": "in progress" }
  },
  "harvest": { "project_id": 0, "task_id": 0, "user_id": 0 },   // OPTIONAL
  "tickets": [
    { "key": "short-key",
      "slug": "<espalier/changes/feat/ slug>",
      "name": "Human readable",
      "clickup": "<task id>",         // optional per-ticket
      "deps": ["other-key"],
      "requirement": "feat: … (title of the slice's requirements.md)" }
  ]
}
```

## Anti-Patterns

- **NEVER loop or schedule a wakeup.** One pass, then stop. The human decides
  the cadence; the workers provide the autonomy.
- **NEVER let the master run a pipeline or spawn pipeline subagents in the
  headless modes.** Its whole value there is being cheap, interruptible and
  interactive. (`worker_mode: inline` is the deliberate exception — the plan
  chose to trade that for in-session execution; even then, one ticket at a
  time, in the ticket's worktree, never in the operator's checkout.)
- **NEVER dispatch past an escalation.** The halt rule exists so nothing gets
  built on top of a decision that went wrong.
- **NEVER auto-resolve a merge conflict** beyond the declared union-merged
  registries.
- **NEVER answer a parked question yourself.** It parked precisely because it
  could not be answered from the map, the rules and the requirements.
- **NEVER trust `state.json` over the worktree.** If they disagree, the
  worktree is the fact and the state file is the claim — that is what the
  git-state check in `reap` is for.
- **NEVER carry beliefs across passes.** New pass, new session; `status`
  output is the only memory. A master that "remembers" ticket states acts on
  the past.
